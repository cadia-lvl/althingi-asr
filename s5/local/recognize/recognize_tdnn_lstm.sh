#!/bin/bash

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Decode audio using a LF-MMI tdnn-lstm model. Takes in audio + an optional meta file connecting the audiofile name and the speaker. The final transcript is capitalized and contains punctuation. 
#
# Usage: $0 <audiofile> [<metadata>]
# Example (if want to save the time info as well):
# local/recognize/recognize.sh /data/althingi/corpus_nov2016/audio/rad20160309T151154.flac recognize/chain/ data/local/corpus/metadata.csv &> recognize/chain/log/rad20160309T151154.log

set -e
set -o pipefail

# configs
stage=-1
num_jobs=1
lmwt=8 # Language model weight. Can have big effect. 
score=false

# Which bundle to use
bundle=20180303

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh
. ./conf/path.conf

# Dirs used #
exp=  # Defined in path.conf
bundle=$root_bundle/$bundle
extractor=$bundle/extractor
modeldir=$bundle/acoustic_model
graphdir=$bundle/graph
oldLMdir=$bundle/decoding_lang
newLMdir=$bundle/rescoring_lang

if [ $# -lt 2 ]; then
  echo "This script transcribes Althingi speeches using an Althingi ASR,"
  echo "i.e. made of an LSTM and TDNN acoustic model and an ngram language model"
  echo ""
  echo "Usage: $0 [options] <audiofile> <outputdir> [<metadata>]"
  echo " e.g.: $0 audio/radXXX.mp3 output/radXXX"
  echo ""
  echo "Options:"
  echo "    --lmwt         # language model weight (default: 8)"
  echo "    --bundle       # which model to use, defaults to the newest lstm-tdnn one"
  exit 1;
fi

# Calculate the decoding and denormalization time
begin=$(date +%s)

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

dir=$2 # Outdir
outdir=$dir/$speechname

wdir=$dir/${speechname}_inprocess # I want to keep intermediate files in case of a crash
mkdir -p $wdir
mkdir -p $outdir/{intermediate,log}

# Created
decodedir=${datadir}_segm_hires/decode_3gsmall
#rescoredir=${datadir}_segm_hires/decode_5g

echo "$0 $@"  # Print the command line for logging

if [ $# = 3 ]; then
    speakerfile=$3  # A meta file containing the name of the speaker
elif [ $# = 2 ]; then
    echo -e "unknown",$speechname > ${wdir}/${speechname}_meta.tmp
    speakerfile=${wdir}/${speechname}_meta.tmp
fi

for f in $speechfile $modeldir/final.mdl $graphdir/HCLG.fst \
  $oldLMdir/G.fst $newLMdir/G.carpa $oldLMdir/words.txt $extractor/final.ie; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done  

# Check audio file name format
if ! egrep -q 'rad[0-9]{8}T[0-9]{6}' <(echo $speechname) ; then
  # File is in wrong fromat, print error.
  error 4 ${error_array[4]}
fi

length=$(soxi -D $speechfile) || error 5 ${error_array[5]}

if [ ${length%.*} -lt 1 ]; then
  # The audio file is empty
  error 6 ${error_array[6]}
fi

if [ $stage -le 0 ]; then

    echo "Set up a directory in the right format of Kaldi and extract features"
    local/recognize/prep_audiodata.sh $speechfile $speakerfile $wdir || exit 1;
fi
spkID=$(cut -d" " -f1 $wdir/spk2utt)

if [ $stage -le 3 ]; then

    echo "Segment audio data"
    local/recognize/segment_audio.sh ${wdir} ${wdir}_segm || exit 1;
    mv -t $outdir/intermediate ${wdir}_segm/*silence.txt
fi

if [ $stage -le 4 ]; then

    echo "Create high resolution MFCC features"
    utils/copy_data_dir.sh ${wdir}_segm ${wdir}_segm_hires
    steps/make_mfcc.sh \
	--nj $num_jobs --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" ${wdir}_segm_hires || exit 1;
    steps/compute_cmvn_stats.sh ${wdir}_segm_hires || exit 1;
    utils/fix_data_dir.sh ${wdir}_segm_hires
fi

if [ $stage -le 5 ]; then

    echo "Extracting iVectors"
    mkdir -p ${wdir}_segm_hires/ivectors_hires
    steps/online/nnet2/extract_ivectors_online.sh \
	--cmd "$train_cmd" --nj $num_jobs --ivector-period 5 \
        ${wdir}_segm_hires $extractor \
        ${wdir}_segm_hires/ivectors_hires || exit 1;
fi

if [ $stage -le 6 ]; then
  rm ${wdir}_segm_hires/.error 2>/dev/null || true

  frames_per_chunk=140,100,160
  frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)
  extra_left_context=50
  extra_right_context=0
  
  local/recognize/decode.sh \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --nj $num_jobs --cmd "$decode_cmd" \
    --skip-scoring true \
    --extra-left-context $extra_left_context  \
    --extra-right-context $extra_right_context  \
    --extra-left-context-initial 0 \
    --extra-right-context-final 0 \
    --frames-per-chunk "$frames_per_chunk_primary" \
    --model-dir $modeldir \
    --online-ivector-dir ${wdir}_segm_hires/ivectors_hires \
    $graphdir ${wdir}_segm_hires ${decodedir} || exit 1;
  
  steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" --skip-scoring true \
    ${oldLMdir} ${newLMdir} ${wdir}_segm_hires \
    ${decodedir} ${outdir} || exit 1;
fi

if [ $stage -le 7 ]; then

  echo "Extract the transcript hypothesis from the Kaldi lattice"
  lattice-best-path \
    --lm-scale=$lmwt \
    --word-symbol-table=${oldLMdir}/words.txt \
    "ark:zcat ${outdir}/lat.1.gz |" ark,t:$outdir/intermediate/one-best.tra 2>/dev/null \
    && utils/int2sym.pl -f 2- \
      ${oldLMdir}/words.txt $outdir/intermediate/one-best.tra \
    > ${outdir}/ASRtranscript.txt || error 7 ${error_array[7]};
fi

if [ $stage -le 8 ]; then

  echo "Denormalize the transcript"
  $train_cmd $outdir/log/${speechname}_denormalize.log \
    local/recognize/denormalize.sh \
      $bundle ${outdir}/ASRtranscript.txt \
      ${outdir}/${speechname}.txt || exit 1;
fi

end=$(date +%s)
tottime=$(expr $end - $begin)
echo "total time: $tottime seconds"

if [ $score = true ] ; then

    echo "Estimate the WER"
    # NOTE! Correct for the mismatch in the beginning and end of recordings.
    local/recognize/score_recognize.sh \
	--cmd "$train_cmd" $speechname ${oldLMdir} ${wdir} || exit 1;
fi

mv -t $outdir/log ${wdir}_segm_hires/decode*/log/*
rm -r ${wdir}*

exit 0



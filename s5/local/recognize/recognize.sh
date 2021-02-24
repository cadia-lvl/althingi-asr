#!/bin/bash

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Decode audio using a LF-MMI tdnn model. Takes in audio + an optional meta file connecting the audiofile name and the speaker. The final transcript is capitalized and contains punctuation. 
#
# Usage: $0 <audiofile> <outdir> [<metadata>]
# Example:
# local/recognize/recognize.sh /data/althingi/corpus_nov2016/audio/rad20160309T151154.flac recognize/chain/ data/local/corpus/metadata.csv &> recognize/chain/log/rad20160309T151154.log

set -e
set -o pipefail

# configs
stage=-1
trim=0
num_jobs=1
lmwt=9
rnnlm=false
#ngram_rnnlm=false # Completely unnecessary
score=false

# Which bundle to use
bundle=latest

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

# Dirs used 
bundle=$root_bundle/$bundle
extractor=$bundle/extractor
modeldir=$bundle/acoustic_model
graphdir=$bundle/graph
oldLMdir=$bundle/decoding_lang
newLMdir=$bundle/rescoring_lang

# If RNN-LM rescoring is applied
if $rnnlm ; then  #  -o $ngram_rnnlm
  rnnlmdir=$bundle/rescoring_lang_rnn
  ngram_order=4  # approximate the lattice-rescoring by limiting the max-ngram-order
                 # if it's set, it merges histories in the lattice if they share
                 # the same ngram history and this prevents the lattice from 
                 # exploding exponentially
fi

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $# -lt 2 ]; then
  echo "This script transcribes Althingi speeches using an Althingi ASR,"
  echo "i.e. consisting of a factorized TDNN acoustic model and by default an ngram language model,"
  echo "with the option of rescoring with a RNN language model."
  echo ""
  echo "Usage: $0 [options] <audiofile> <outputdir> [<metadata>]"
  echo " e.g.: $0 audio/radXXX.mp3 output/radXXX"
  echo ""
  echo "Options:"
  echo "    --lmwt         # language model weight (default: 8)"
  echo "    --bundle       # which model to use, defaults to the latest one"
  echo "    --rnnlm        # rescore with an RNN-LM, default: false"
  #echo "    --ngram-rnnlm  # rescore first with an ngram and then with an rnnlm"
  exit 1;
fi

# Calculate the decoding and denormalization time
begin=$(date +%s)

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

dir=$2
outdir=$dir/${speechname}

wdir=$dir/${speechname}_inprocess # I want to keep intermediate files in case of a crash
mkdir -p $wdir $outdir/{intermediate,log}

# Created
decodedir=${wdir}_segm_hires/decode_3gsmall
#rescoredir=${wdir}_segm_hires/decode_5g

if [ $# = 3 ]; then
  speakerfile=$3  # A meta file containing the name of the speaker
elif [ $# = 2 ]; then
  echo -e "unknown",$speechname > ${wdir}/${speechname}_meta.tmp
  speakerfile=${wdir}/${speechname}_meta.tmp
fi

#! $ngram_rnnlm || rescoredir_ngram=${wdir}_segm_hires/decode_5g

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
  samplerate=16000
  if [ $trim -gt 0 ]; then
    # Convert to wav straight away
    sox $speechfile $tmp/$speechname.mp3 trim $trim
    #sox -t$extension $speechfile -c1 -esigned -r$samplerate -G -twav $tmp/$speechname.wav trim $trim
    local/recognize/prep_audiodata.sh $tmp/$speechname.mp3 $speakerfile $wdir || exit 1;
  else
    #wav_cmd="sox -t$extension - -c1 -esigned -r$samplerate -G -twav - "
    local/recognize/prep_audiodata.sh $speechfile $speakerfile $wdir || exit 1;
  fi
fi
spkID=$(cut -d" " -f1 $wdir/spk2utt)

if [ $stage -le 3 ]; then

  echo "Segment audio data"
  local/recognize/segment_audio.sh ${wdir} ${wdir}_segm || exit 1;
  [ -f ${wdir}_segm/*silence.txt ] && mv -t $outdir/intermediate ${wdir}_segm/*silence.txt
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
    --cmd "$train_cmd" --nj $num_jobs \
    ${wdir}_segm_hires $extractor \
    ${wdir}_segm_hires/ivectors_hires || exit 1;
fi

if [ $stage -le 6 ]; then
 
  echo "Decoding"
  frames_per_chunk=150,110,100
  frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)

  # This decoding script is exactly the same as in steps/nnet3/decode.sh
  # except that is allows the decode dir to be positioned outside the model dir
  local/recognize/decode.sh \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --nj $num_jobs --cmd "$train_cmd" \
    --skip-scoring true \
    --frames-per-chunk $frames_per_chunk_primary \
    --model-dir $modeldir \
    --online-ivector-dir ${wdir}_segm_hires/ivectors_hires \
    $graphdir ${wdir}_segm_hires ${decodedir} || exit 1;

  if $rnnlm; then
    echo "RNN-LM rescoring"
    rnnlm/lmrescore_pruned.sh \
      --cmd "$train_cmd --mem 8G" \
      --weight 0.5 --max-ngram-order $ngram_order \
      --skip-scoring true \
      ${oldLMdir} $rnnlmdir \
      ${wdir}_segm_hires ${decodedir} \
      ${outdir} || exit 1;
    
  # elif $ngram_rnnlm; then
  #   echo "Rescoring with both an n-grams and an RNN-LM"
  #   steps/lmrescore_const_arpa.sh \
  #     --cmd "$train_cmd" --skip-scoring true \
  #     ${oldLMdir} ${newLMdir} ${wdir}_segm_hires \
  #     ${decodedir} ${rescoredir_ngram} || exit 1;
  #   cp ${rescoredir_ngram}/lat.1.gz $outdir/intermediate/lat_ngram.1.gz
    
  #   # Lattice rescoring
  #   rnnlm/lmrescore_pruned.sh \
  #     --cmd "$decode_cmd" \
  #     --weight 0.5 --max-ngram-order $ngram_order \
  #     --skip-scoring true \
  #     ${newLMdir} $rnnlmdir \
  #     ${wdir}_segm_hires ${rescoredir_ngram} \
  #     ${outdir} || exit 1;
    
  else
    echo "n-gram rescoring"
    steps/lmrescore_const_arpa.sh \
      --cmd "$train_cmd" --skip-scoring true \
      ${oldLMdir} ${newLMdir} ${wdir}_segm_hires \
      ${decodedir} ${outdir} || exit 1;
  fi
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
      --cmd "$train_cmd" $speechname $oldLMdir $outdir || exit 1;
fi

mv -t $outdir/log ${wdir}_segm_hires/decode*/log/*
rm -r ${wdir}*

exit 0

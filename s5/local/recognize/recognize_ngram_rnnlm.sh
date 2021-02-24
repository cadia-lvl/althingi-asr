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

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# Calculate the decoding and denormalization time
begin=$(date +%s)

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"

dir=$2 # Outdir
datadir=$dir/$speechname
logdir=${dir}/log
mkdir -p ${datadir}
mkdir -p ${logdir}

if [ $# = 3 ]; then
  speakerfile=$3  # A meta file containing the name of the speaker
elif [ $# = 2 ]; then
  echo -e "unknown",$speechname > ${datadir}/${speechname}_meta.tmp
  speakerfile=${datadir}/${speechname}_meta.tmp
else
  echo "Usage: local/recognize/recognize.sh [options] <audiofile> <outputdir> [<metadata>]"
fi

# Dirs used #
# Already existing
exp=/mnt/scratch/inga/exp
extractor=$exp/nnet3/extractor
modeldir=$exp/chain/tdnn_sp
graphdir=${modeldir}/graph_3gsmall
oldLMdir=data/lang_3gsmall
newLMdir=data/lang_5g
rnnlmdir=$exp/rnnlm_lstm_1e

# Variables for lattice rescoring
decodedir=${datadir}_segm_hires/decode_3gsmall
rescoredir_ngram=${datadir}_segm_hires/decode_5g
rescoredir_rnnlm=${rescoredir_ngram}_rnnlm
ngram_order=4 # approximate the lattice-rescoring by limiting the max-ngram-order
# if it's set, it merges histories in the lattice if they share
# the same ngram history and this prevents the lattice from 
# exploding exponentially

if [ $stage -le 0 ]; then

  echo "Set up a directory in the right format of Kaldi and extract features"
  local/recognize/prep_audiodata.sh $speechfile $speakerfile $datadir || exit 1;
fi
spkID=$(cut -d" " -f1 $datadir/spk2utt)

if [ $stage -le 3 ]; then

  echo "Segment audio data"
  local/recognize/segment_audio.sh ${datadir} ${datadir}_segm || exit 1;
fi

if [ $stage -le 4 ]; then

  echo "Create high resolution MFCC features"
  utils/copy_data_dir.sh ${datadir}_segm ${datadir}_segm_hires
  steps/make_mfcc.sh \
    --nj $num_jobs --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd" ${datadir}_segm_hires || exit 1;
  steps/compute_cmvn_stats.sh ${datadir}_segm_hires || exit 1;
  utils/fix_data_dir.sh ${datadir}_segm_hires
fi

if [ $stage -le 5 ]; then

  echo "Extracting iVectors"
  mkdir -p ${datadir}_segm_hires/ivectors_hires
  steps/online/nnet2/extract_ivectors_online.sh \
    --cmd "$train_cmd" --nj $num_jobs --ivector-period 5 \
    ${datadir}_segm_hires $extractor \
    ${datadir}_segm_hires/ivectors_hires || exit 1;
fi

if [ $stage -le 6 ]; then
  rm ${datadir}_segm_hires/.error 2>/dev/null || true

  frames_per_chunk=150,110,100
  frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)
  cp ${modeldir}/{final.mdl,final.ie.id,cmvn_opts,frame_subsampling_factor} ${datadir}_segm_hires || exit 1;

  steps/nnet3/decode.sh \
    --acwt 1.0 --post-decode-acwt 10.0 \
    --nj $num_jobs --cmd "$decode_cmd" \
    --skip-scoring true \
    --frames-per-chunk $frames_per_chunk_primary \
    --online-ivector-dir ${datadir}_segm_hires/ivectors_hires \
    $graphdir ${datadir}_segm_hires ${decodedir} || exit 1;
  
  steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" --skip-scoring true \
    ${oldLMdir} ${newLMdir} ${datadir}_segm_hires \
    ${decodedir} ${rescoredir_ngram} || exit 1;

  # Lattice rescoring
  rnnlm/lmrescore_pruned.sh \
    --cmd "$decode_cmd" \
    --weight 0.5 --max-ngram-order $ngram_order \
    --skip-scoring true \
    ${newLMdir} $rnnlmdir \
    ${datadir}_segm_hires ${rescoredir_ngram} \
    ${rescoredir_rnnlm} || exit 1;
  
fi

if [ $stage -le 7 ]; then

  echo "Extract the transcript hypothesis from the Kaldi lattice"
  lattice-best-path \
    --lm-scale=$lmwt \
    --word-symbol-table=${oldLMdir}/words.txt \
    "ark:zcat ${rescoredir_rnnlm}/lat.1.gz |" ark,t:- &> ${rescoredir_rnnlm}/extract_transcript.log || exit 1;

  # Extract the best path text (tac - concatenate and print files in reverse)
  tac ${rescoredir_rnnlm}/extract_transcript.log | grep -e '^[^ ]\+rad' | sort -u -t" " -k1,1 > ${rescoredir_rnnlm}/transcript.txt || exit 1;

fi

if [ $stage -le 8 ]; then

  echo "Denormalize the transcript"
  $train_cmd ${logdir}/${speechname}_denormalize.log local/recognize/denormalize.sh \
             ${rescoredir_rnnlm}/transcript.txt \
             ${dir}/${speechname}.txt || exit 1;
fi

end=$(date +%s)
tottime=$(expr $end - $begin)
echo "total time: $tottime seconds"

if [ $score = true ] ; then

  echo "Estimate the WER"
  # NOTE! Correct for the mismatch in the beginning and end of recordings.
  local/recognize/score_recognize.sh \
    --cmd "$train_cmd" $speechname ${oldLMdir} ${datadir}/.. || exit 1;
fi

rm -r ${datadir} ${datadir}_segm ${datadir}_segm_hires



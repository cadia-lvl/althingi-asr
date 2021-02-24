#!/bin/bash

# Copyright 2014  Guoguo Chen
#           2016  Reykjavik University (Inga Rún Helgadóttir)
# Apache 2.0

# This script demonstrates how to re-segment long audios into short segments.
# The basic idea is to decode with an existing in-domain acoustic model, and a
# bigram language model built from the reference, and then work out the
# segmentation from a ctm like file.
# To be run from ..

stage=0

. ./cmd.sh
. ./path.sh
. ./conf/path.conf # Define the path of $exp, $data and $mfcc
. ./utils/parse_options.sh

# # Begin configuration section.
# nj=30
# stage=-4

echo "$0 $@"  # Print the command line for logging

. parse_options.sh || exit 1;

if [ $# != 4 ]; then
    echo "Usage: local/run_segmentation.sh [options] <data-dir> <lang-dir> <model-dir> <output-dir>"
    echo " e.g.: local/run_segmentation.sh data/all data/lang exp/tri2_cleaned ${datadir}_reseg"
    exit 1;
fi

datadir=$1
base=$(basename $datadir)
langdir=$2
modeldir=$3
outdir=$4

if [ $stage -le 1 ]; then
  echo "Truncate the long audio into smaller overlapping segments"
  steps/cleanup/split_long_utterance.sh \
    --seg-length 30 --overlap-length 5 \
    ${datadir} ${datadir}_split || exit 1;
fi

if [ $stage -le 2 ]; then
  echo "Make MFCC features and compute CMVN stats"
  steps/make_mfcc.sh \
    --cmd "$train_cmd --time 0-06" --nj 64 \
    ${datadir}_split $exp/make_mfcc/${base}_split $mfcc || exit 1;
  utils/fix_data_dir.sh ${datadir}_split
  steps/compute_cmvn_stats.sh \
    ${datadir}_split \
    $exp/make_mfcc/${base}_split $mfcc || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "Make segmentation graph, i.e. build one decoding graph for each truncated utterance in segmentation."
  local/make_segmentation_graph.sh \
    --cmd "$mkgraph_cmd --time 0-12" --nj 64 \
    ${datadir}_split ${langdir} ${modeldir} \
    ${modeldir}/graph_${base}_split || exit 1;
fi

if [ $stage -le 4 ]; then
  echo "Decode segmentation"
  num_jobs=`cat ${datadir}_split/utt2spk|cut -d' ' -f2|sort -u|wc -l`
  steps/cleanup/decode_segmentation.sh \
    --nj $num_jobs --cmd "$decode_cmd --time 0-12" --skip-scoring true \
    ${modeldir}/graph_${base}_split \
    ${datadir}_split ${modeldir}/decode_${base}_split || exit 1;
fi

if [ $stage -le 5 ]; then
  echo "Get CTM, changed so that it only uses LMWT 10"
  local/get_ctm_one_score.sh \
    --cmd "$decode_cmd --time 0-12" \
    ${datadir}_split ${modeldir}/graph_${base}_split \
    ${modeldir}/decode_${base}_split || exit 1;
fi

if [ $stage -le 6 ]; then
  echo "Make segmentation data dir"
  steps/cleanup/make_segmentation_data_dir.sh \
    --wer-cutoff 0.9 --min-sil-length 0.5 \
    --max-seg-length 15 --min-seg-length 1 \
    ${modeldir}/decode_${base}_split/score_10/${base}_split.ctm \
    ${datadir}_split $outdir || exit 1;
fi

rm -r ${datadir}_split

exit 0;

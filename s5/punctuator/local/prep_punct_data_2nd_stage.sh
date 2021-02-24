#!/bin/bash -e

set -o pipefail

# NOTE! Scripts are crap and need to be updated!
# Preprocess training data for second stage punctuation modelling

id=
ignore_commas=true
suffix=
$ignore_commas && suffix=_noCOMMA

. ./path.sh # $root_* variables and $data, $exp are defined in conf/path.conf
. ./utils/parse_options.sh

# These paths are defined in path.conf
prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
all=$root_intermediate

if [ $# -ne 3 ]; then
  echo "This script preprocesses data for 2nd stage punctuation modelling."
  echo ""
  echo "Usage: $0 <path-to-intermediate-data> <alignment-directory> <output-data-dir-2nd-stage>" >&2
  echo "e.g.: $0 data/all_sept2017 exp/tri4_ali punctuation/data/second_stage" >&2
  exit 1;
fi

datadir=$1; shift
ali_dir=$1; shift # Should contain alignments for the data in $datadir. NOTE! Slow if contains alignments for more datasets than the one in $datadir
out=$1
intermediate=$out/intermediate
mkdir -p $intermediate $out/log

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# NOTE! This just fits if the data was created in run.sh and we are using it
# Text data fit for 2nd stage training
textin_2nd_stage=$datadir/text_expanded
reseg_dir=$data/$(basename ${datadir})_reseg_cleaned #filtered

echo "Input text data is $textin_2nd_stage"
echo "Segmented data used is $reseg_dir"
echo "The alignment data used is $ali_dir"

# Check if the input data and the alignment data are compatible
common_ids=$(comm -12 <(egrep -o "rad[0-9]{8}T[0-9]{6}" $textin_2nd_stage | sort -u) <(egrep -o "rad[0-9]{8}T[0-9]{6}" $ali_dir/log/align_pass1.*.log | cut -d':' -f2 | sort -u) | wc -l)
n_utts=$(wc -l $textin_2nd_stage)
ratio_float=$(echo "scale=3;$common_ids/$(echo $n_utts |cut -d' ' -f1)*100" | bc)
ratio_int=${ratio_float%.*}
if [ $ratio_int -lt 90 ]; then
  echo "low compatibility between input text and the alignment"
  echo "Check your data"
  exit 1;
fi

echo "Preprocess the data"
utils/slurm.pl --mem 8G --time 2-00 ${out}/log/preprocessing_pause_data.log \
       python punctuator/local/preprocessing_pause_data.py \
       $textin_2nd_stage ${out}/althingi.$(basename $datadir)_without_pauses.txt || exit 1;

echo "Make the data pause annotated"
utils/slurm.pl --mem 8G --time 2-00 ${out}/log/make_pause_annotated.log \
       punctuator/local/make_pause_annotated.sh \
       $ali_dir ${out}/althingi.$(basename $datadir)_without_pauses.txt $reseg_dir || exit 1;

# If I want to ignore commas in the training:
if [ ignore_commas = true ]; then
  out_noComma=${out}$suffix/second_stage_${id}$suffix
  mkdir -p $out_noComma/log
  for f in althingi.{train,dev,test}.txt; do
    sed -re 's: ,COMMA::g' ${out}/$f > $out_noComma/$f || exit 1;
  done
fi

echo "Preprocessing done."
    
exit 0;

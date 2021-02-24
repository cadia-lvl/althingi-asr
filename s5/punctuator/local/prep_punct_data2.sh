#!/bin/bash -eu

set -o pipefail

# Preprocess training data for first stage punctuation modelling

id=
ignore_commas=true
suffix=
$ignore_commas && suffix=_noCOMMA

. ./path.sh
. ./utils/parse_options.sh

# The path is defined in path.conf
all=$root_intermediate
#scraped_text_dir=/data/althingi/text_corpora/ #$root_raw_text


if [ $# -ne 4 ]; then
  echo "This script cleans and preprocesses data for punctuation modelling."
  echo ""
  echo "Usage: $0 <basename-input-textfile> <output-data-dir-1st-stage>" >&2
  echo "e.g.: $0 text_PunctuationTraining.txt punctuation/data/first_stage" >&2
  exit 1;
fi

textin=$1; shift
out=$1; shift
intermediate=$out/intermediate
mkdir -p $intermediate $out/log

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

echo "Create the training and dev/test sets"
echo "Input texts are $all/all_*/$textin"
echo "$all/all_nov2016 is reserved for dev and test sets"
# Keep the same test sets as before
cat $all/all_*/$textin | sort -u > $tmp/punct_text_all
cut -d' ' -f1 $all/all_nov2016/utt2spk | cut -d'-' -f2 > $tmp/devtest_uttid
join -j1 $tmp/devtest_uttid $tmp/punct_text_all > $tmp/punct_devtest
comm -13 $tmp/punct_devtest $tmp/punct_text_all | cut -d' ' -f2- > $intermediate/punctuation_text.train.txt

nlines_half=$(echo $((($(wc -l $tmp/punct_devtest | cut -d" " -f1)+1)/2)))
head -n $nlines_half $tmp/punct_devtest | cut -d' ' -f2- > $intermediate/punctuation_text.dev.txt
tail -n +$[$nlines_half+1] $tmp/punct_devtest | cut -d' ' -f2- > $intermediate/punctuation_text.test.txt

echo "Preprocess the data for training"
utils/slurm.pl --mem 8G ${out}/log/preprocessing_trainingdata_cs.log \
	       python punctuator/local/preprocessing_trainingdata_cs.py ${intermediate}/punctuation_text.train.txt ${out}/althingi.train.txt || exit 1;

python punctuator/local/preprocessing_trainingdata_cs.py \
       ${intermediate}/punctuation_text.dev.txt \
       ${out}/althingi.dev.txt || exit 1;

python punctuator/local/preprocessing_trainingdata_cs.py \
       ${intermediate}/punctuation_text.test.txt \
       ${out}/althingi.test.txt || exit 1;

# If I want to ignore commas in the training:
if [ ignore_commas = true ]; then
  out_noComma=${out}$suffix
  mkdir -p $out_noComma/log
  for f in althingi.{train,dev,test}.txt; do
    sed -re 's: ,COMMA::g' $out/$f > $out_noComma/$f || exit 1;
  done
fi

echo "Preprocessing done."
    
exit 0;

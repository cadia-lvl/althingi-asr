#!/bin/bash -e

set -o pipefail

# This script cleans and preprocesses data for punctuation modelling.

#date
d=$(date +'%Y%m%d')

stage=0
id=
ignore_commas=false
suffix=
$ignore_commas && suffix=_noCOMMA

. ./path.sh # root_* and $data defined as well here
. ./utils/parse_options.sh

# These paths are defined in path.conf
prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
punct_transcripts=$root_punctuation_transcripts
punct_transcripts_archive=$root_punct_transcripts_archive
mkdir -p $punct_transcripts_archive

if [ "$suffix" = "_noCOMMA" ]; then
  current_punct_data=$(dirname $(ls -t $root_punctuation_datadir/*/first_stage_noCOMMA/althingi.train.txt | head -n1))
  new_datadir=$root_punctuation_datadir/$d/first_stage_noCOMMA
else
  current_punct_data=$(dirname $(ls -t $root_punctuation_datadir/*/first_stage/althingi.train.txt | head -n1))
  new_datadir=$root_punctuation_datadir/$d/first_stage
fi

mkdir -p $new_datadir/log

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

cat $punct_transcripts/*.* > $tmp/new_transcripts.txt
mv -t $punct_transcripts_archive/ $punct_transcripts/*.*

echo "Preprocess the data for training"
utils/slurm.pl --mem 8G ${new_datadir}/log/preprocessing_trainingdata_cs.log \
       python punctuator/local/preprocessing_trainingdata_cs.py $tmp/new_transcripts.txt $tmp/new_transcripts_processed.txt || exit 1;
cat $current_punct_data/althingi.train.txt $tmp/new_transcripts_processed.txt > ${new_datadir}/althingi.train.txt

# Use the same dev and test data as before
cp $current_punct_data/althingi.dev.txt ${new_datadir}/althingi.dev.txt
cp $current_punct_data/althingi.test.txt ${new_datadir}/althingi.test.txt

# If I want to ignore commas in the training:
if [ $ignore_commas = true ]; then
  for f in althingi.{train,dev,test}.txt; do
    sed -i -re 's: ,COMMA::g' $new_datadir/$f
  done
fi

echo "Preprocessing done."
    
exit 0;

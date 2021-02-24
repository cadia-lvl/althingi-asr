#!/bin/bash -e

. ./path.sh
. ./local/utils.sh
. ./local/array.sh

asrlm_modeldir=/jarnsmidur/asr-lm_models
# Check if a new AM model directory was created at least an hour ago
# Newest AM dir
am_modeldir=$(ls -td $asrlm_modeldir/acoustic_model/*/*/*/* | head -n1)

# Copy the new LMs and decoding graph from the LM server to the decoding server

# The pathnames are not the same in the beginning, between the two servers, cut away what is different
n=$(echo $asrlm_modeldir | egrep -o '/' | wc -l)
am_date=$(basename $am_modeldir)
middle_ampath=$(dirname $am_modeldir | cut -d'/' -f$[$n+2]-)

# Newest language models
# NOTE! This won't work because the symlink will be broken on the decoding server
# How to solve it?
# I need to create a info file or something like that in the AM modeldir that tells what version of the lm was used
#lmdir=$(readlink -f $am_modeldir/lmdir)
lm_modeldir=$(cat $am_modeldir/lminfo)
lm_date=$(basename $lm_modeldir)
middle_lmpath=language_model

decode_amdir=$root_modeldir/$middle_ampath
decode_lmdir=$root_lm_modeldir

if [ -d $decode_lmdir/$lm_date ]; then
  echo "Language model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new language models"
  mkdir -p $decode_lmdir
  cp -r $asrlm_modeldir/$middle_lmpath/$lm_date $decode_lmdir
fi

if [ -d $decode_amdir/$am_date ]; then
  echo "Acoustic model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new acoustic model directory"
  mkdir -p $decode_amdir
  cp -r $asrlm_modeldir/$middle_ampath/$am_date $decode_amdir
  ln -sf $decode_lmdir/$lm_date $decode_amdir/$am_date/lmdir
fi

echo "Update latest"
d=$(basename $(ls -td $root_bundle/20* | head -n1))
if [ $d = $am_date ]; then
  echo "The latest bundle is already from $am_date"
  echo "I won't overwrite it"
else
  local/update_latest.sh || error 1 "ERROR: update_latest.sh failed"
fi

# Add a test here! If failed then reset latest to the bundle before and notify about it!

exit 0;

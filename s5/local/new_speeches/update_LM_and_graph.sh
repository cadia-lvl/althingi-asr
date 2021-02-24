#!/bin/bash -e

set -o pipefail

# Run from the s5 directory
# Take in new speech transcripts cleaned for language modelling and new words,
# confirmed by editors, and update the pronunctiation dictionary,
# the language models, the decoding graph and the latest bundle.

# As this script is written, it is asumed that it will not be run when many the editors are working.
# Otherwise some vocab could be moved straight to the archive and not to the pron dict.

stage=0
pronext=tsv

. ./path.sh # the $root_* variable are defined here
. ./cmd.sh
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

#date
d=$(date +'%Y%m%d')

confirmed_vocab_dir=$root_confirmed_vocab
vocab_archive=$root_confirmed_vocab_archive
prondir=$root_lexicon
current_prondict=$(ls -t $prondir/prondict.* | head -n1)
lm_transcript_dir=$root_lm_transcripts
lm_transcripts_archive=$root_lm_transcripts_archive
lm_training_dir=$root_lm_training
current_LM_training_texts=$(ls -t $lm_training_dir/* | head -n1)
lm_modeldir=$root_lm_modeldir/$d
current_lmdir=$(ls -td $root_lm_modeldir/20*/lang_* | head -n1)
current_lmdir=$(dirname $current_lmdir)

# Temporary dir used when creating data/lang dirs in local/prep_lang.sh
localdict=$root_localdict # Byproduct of local/prep_lang.sh

for f in $current_prondict $current_LM_training_texts; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $stage -le 1 ]; then

  # Do I want to overwrite or not?
  [ -f $prondir/prondict.${d}.* ] && \
  echo "$0: $prondir/prondict.${d}.$pronext already exists. Are you sure you want to overwrite it?" \
  && exit 1;

  n_trans=$(ls $lm_transcript_dir/ | wc -l)
  if [ $n_trans -gt 1 ]; then
    if [ $current_LM_training_texts = $lm_training_dir/LMtext.${d}.txt ]; then
      echo "The current LM training texts were created today"
      echo "We won't override them"
      exit 0;
    fi
    echo "Update the LM training texts"
    cat $current_LM_training_texts $lm_transcript_dir/*.* | egrep -v '^\s*$' > $lm_training_dir/LMtext.${d}.txt
    mv -t $lm_transcripts_archive $lm_transcript_dir/*.* 
  else
    echo "There are no new transcripts to add to the language models"
    exit 0;
  fi

  # Update the prondict if there is new confirmed vocabulary, and move those vocab files to the archive
  n_vocab=$(ls $confirmed_vocab_dir | wc -l)
  if [ $n_vocab -gt 1 ]; then
    echo "Update the pronunciation dictionary"
    cat $confirmed_vocab_dir/*.* $current_prondict | egrep -v '^\s*$' | sort -u > $prondir/prondict.${d}.$pronext
    mv $confirmed_vocab_dir/*.* $vocab_archive/ 
  fi
    
fi

if [ $stage -le 2 ]; then

  echo "Update the lang dir"

  # Make lang dir
  prondict=$(ls -t $prondir/prondict.* | head -n1)
  # I comment out the if loop since for now I tend to manually fix the pronunciation dictionary from time to time
  #if [ $prondict != $current_prondict ]; then
    [ -d $localdict ] && rm -r $localdict
    mkdir -p $localdict $lm_modeldir/lang
    
    local/prep_lang.sh \
      $prondict        \
      $localdict   \
      $lm_modeldir/lang
  #else
  #  mkdir -p $lm_modeldir
  #  cp -r $current_lmdir/lang $lm_modeldir
  #fi
  
fi

if [ $stage -le 3 ]; then
  
  echo "Preparing a pruned trigram language model"
  mkdir -p $lm_modeldir/log
  $train_cmd --mem 12G $lm_modeldir/log/make_LM_3gsmall.log \
    local/make_LM.sh \
      --order 3 --small true --carpa false \
      $(ls -t $lm_training_dir/* | head -n1) $lm_modeldir/lang \
      $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating a pruned trigram language model"

fi

if [ $stage -le 4 ]; then
  echo "Preparing an unpruned 5g LM"
  mkdir -p $lm_modeldir/log
  $train_cmd --mem 20G $lm_modeldir/log/make_LM_5g.log \
    local/make_LM.sh \
      --order 5 --small false --carpa true \
      $(ls -t $lm_training_dir/* | head -n1) $lm_modeldir/lang \
      $localdict/lexicon.txt $lm_modeldir \
    || error 1 "Failed creating an unpruned 5-gram language model"
  
fi

if [ $stage -le 5 ]; then

  echo "Update the decoding graph"
  local/update_graph.sh || error 1 "ERROR: update_graph.sh failed"
  
fi

echo "Done"
exit 0;

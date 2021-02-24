#!/bin/bash -e

set -o pipefail

stage=-1
order=4
small=false # pruned or not
carpa=true

. ./cmd.sh
. ./path.sh
. parse_options.sh || exit 1;

#date
d=$(date +'%Y%m%d')

prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
lm_trainingset=$(ls -t $root_lm_training/* | head -n1)
lm_modeldir=$root_lm_modeldir/$d
localdict=$root_localdict

size=
if [ $small = true ]; then
  size="pruned"
else
  size="unpruned"
fi

type=
if [ $carpa = true ]; then
  type="carpa"
else
  type="fst"
fi

if [ $stage -le 1 ]; then

  echo "Lang preparation"
  [ -d $localdict ] && rm -r $localdict
  mkdir -p $localdict $lm_modeldir/lang
  local/prep_lang.sh \
    $prondict        \
    $localdict   \
    $lm_modeldir/lang
fi

if [ $stage -le 2 ]; then

  echo "Creating a $size ${order}-gram language model, $type"
  mkdir -p $lm_modeldir/log
  local/make_LM.sh \
    --order $order --small $small --carpa $carpa \
    $lm_trainingset $lm_modeldir/lang \
    $localdict/lexicon.txt $lm_modeldir \
  || error 1 "Failed creating a $size ${order}-gram language model"
  
fi

exit 0

#!/bin/bash

# Copyright 2012  Johns Hopkins University (author: Daniel Povey)
#           2015  Guoguo Chen
#           2017  Hainan Xu
#           2017  Xiaohui Zhang

# This script is a copy of the swbd rnn_tdnn_lstm.sh script (affix=1e)
# It trains a LMs on the Althingi LM-training data.

# Begin configuration section.

embedding_dim=1024
lstm_rpd=256
lstm_nrpd=256
stage=-10
train_stage=-10
affix=_1e

# variables for lattice rescoring
run_lat_rescore=false
ngram_order=4 # approximate the lattice-rescoring by limiting the max-ngram-order
              # if it's set, it merges histories in the lattice if they share
              # the same ngram history and this prevents the lattice from 
              # exploding exponentially
pruned_rescore=true

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh
# path.sh calls path.conf where $data, $exp and $mfcc are defined, default to /mnt/scratch/inga/

if [ $# -ne 1 ]; then
  echo "This script trains a RNN language model and uses it to performe lattice rescoring"
  echo ""
  echo "Usage: $0 [options] <text-set>" >&2
  echo "e.g.: $0 ~/data/language_model/training/LMtext_2004-March2018.txt" >&2
  exit 1;
fi

text=$1
echo "training text: $text"

data_dir=$data/rnnlm
dir=$exp/rnnlm_lstm${affix}
mkdir -p $dir/config

decode_dir_suffix=rnnlm${affix}
text_dir=$data_dir/text${affix}

# Use the newest vocabulary
lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)
langdir=$lmdir/lang

set -e

for f in $text $langdir/words.txt; do
  [ ! -f $f ] && \
    echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 0 ]; then
  mkdir -p $text_dir
  echo -n >$text_dir/dev.txt
  # hold out one in every 50 lines as dev data.
  cat $text | awk -v text_dir=$text_dir '{if(NR%50 == 0) { print >text_dir"/dev.txt"; } else {print;}}' >$text_dir/althingi_train.txt
fi

if [ $stage -le 1 ]; then
  cp $langdir/words.txt $dir/config/
  n=`cat $dir/config/words.txt | wc -l`
  echo "<brk> $n" >> $dir/config/words.txt

  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <SPOKEN_NOISE> during training.
  echo "<unk>" >$dir/config/oov.txt

  # Choose weighting and multiplicity of data.
  # The following choices would mean that data-source 'foo'
  # is repeated once per epoch and has a weight of 0.5 in the
  # objective function when training, and data-source 'bar' is repeated twice
  # per epoch and has a data -weight of 1.5.
  # There is no constraint that the average of the data weights equal one.
  # Note: if a data-source has zero multiplicity, it just means you are ignoring
  # it; but you must include all data-sources.
  #cat > exp/foo/data_weights.txt <<EOF
  #foo 1   0.5
  #bar 2   1.5
  #baz 0   0.0
  #EOF  
  cat > $dir/config/data_weights.txt <<EOF
althingi_train   1   1.0
EOF

  # we need the unigram probs to get the unigram features.
  rnnlm/get_unigram_probs.py --vocab-file=$dir/config/words.txt \
                             --unk-word="<unk>" \
                             --data-weights-file=$dir/config/data_weights.txt \
                             $text_dir | awk 'NF==2' >$dir/config/unigram_probs.txt

  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<unk>' \
                           $dir/config/words.txt > $dir/config/features.txt

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=$embedding_dim input=Append(0, IfDefined(-1))
fast-lstmp-layer name=lstm1 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn2 dim=$embedding_dim input=Append(0, IfDefined(-3))
fast-lstmp-layer name=lstm2 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn3 dim=$embedding_dim input=Append(0, IfDefined(-3))
output-layer name=output include-log-softmax=false dim=$embedding_dim
EOF
  rnnlm/validate_config_dir.sh $text_dir $dir/config
fi

if [ $stage -le 2 ]; then
  rnnlm/prepare_rnnlm_dir.sh --cmd "$train_cmd" $text_dir $dir/config $dir
fi

if [ $stage -le 3 ]; then
  rnnlm/train_rnnlm.sh \
    --num-jobs-initial 4 \
    --num-jobs-final 12 \
    --stage $train_stage \
    --num-epochs 10 \
    --cmd "$train_cmd --mem 12G --time 2-00" $dir
fi

# # Calculate the lattice-rescoring time
# begin=$(date +%s)

# if [ $stage -le 4 ] && $run_lat_rescore; then
#   # Used when applying the new rnnlm
#   ngram_lm=$lmdir/lang_3gsmall
#   ac_model_dir=$(ls -td $exp/chain/tdnn* | head -n1) #$exp/chain/tdnn_lstm_2_sp   #tdnn_sp

#   if [ $ngram_lm = $lmdir/lang_3gsmall ]; then
#     LM=3gsmall # if using the small 3-gram G.fst file as old lm
#   elif [ $ngram_lm = $lmdir/lang_5g ]; then
#     LM=5g  # if using the 5-gram carpa file as old lm
#   fi

#   echo "$0: Perform lattice-rescoring on $ac_model_dir"
  
#   pruned=
#   if $pruned_rescore; then
#     pruned=_pruned
#   fi
#   for decode_set in dev eval; do
#     (
#     decode_dir=${ac_model_dir}/decode_${decode_set}_${LM}

#     # Lattice rescoring
    # rnnlm/lmrescore$pruned.sh \
    #   --cmd "$big_memory_cmd" \
    #   --weight 0.5 --max-ngram-order $ngram_order \
    #   $ngram_lm $dir \
    #   $data/${decode_set}_hires ${decode_dir} \
    #   ${decode_dir}_${decode_dir_suffix}
#     ) &
#   done
# fi

# end=$(date +%s)
# tottime=$(expr $end - $begin)
# echo "total time: $tottime seconds"

exit 0

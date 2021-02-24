#!/bin/bash

# Copyright 2012  Johns Hopkins University (author: Daniel Povey)
#           2015  Guoguo Chen
#           2017  Hainan Xu
#           2017  Xiaohui Zhang

# This script trains a backward LMs on the swbd LM-training data, and use it
# to rescore either decoded lattices, or lattices that are just rescored with
# a forward RNNLM. In order to run this, you must first run the forward RNNLM
# recipe at local/rnnlm/run_tdnn_lstm.sh

# It is a copy of kaldi/egs/swbd/s5c/local/tuning/run_tdnn_lstm_back_1e.sh

# %WER 11.1 | 1831 21395 | 89.9 6.4 3.7 1.0 11.1 46.3 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped/score_13_0.0/eval2000_hires.ctm.swbd.filt.sys
# %WER 9.9 | 1831 21395 | 91.0 5.8 3.2 0.9 9.9 43.2 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped_rnnlm_1e/score_11_0.0/eval2000_hires.ctm.swbd.filt.sys
# %WER 9.5 | 1831 21395 | 91.4 5.5 3.1 0.9 9.5 42.5 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped_rnnlm_1e_back/score_11_0.0/eval2000_hires.ctm.swbd.filt.sys

# %WER 15.9 | 4459 42989 | 85.7 9.7 4.6 1.6 15.9 51.6 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped/score_10_0.0/eval2000_hires.ctm.filt.sys
# %WER 14.4 | 4459 42989 | 87.0 8.7 4.3 1.5 14.4 49.4 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped_rnnlm_1e/score_11_0.0/eval2000_hires.ctm.filt.sys
# %WER 13.9 | 4459 42989 | 87.6 8.4 4.0 1.5 13.9 48.6 | exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp/decode_eval2000_sw1_fsh_fg_looped_rnnlm_1e_back/score_10_0.0/eval2000_hires.ctm.filt.sys

# Begin configuration section.

embedding_dim=1024
lstm_rpd=256
lstm_nrpd=256
stage=-10
train_stage=-10
affix=_1e

# variables for lattice rescoring
run_lat_rescore=false
#ac_model_dir=exp/nnet3/tdnn_lstm_1a_adversarial0.3_epochs12_ld5_sp
LM=3gsmall
ngram_order=4 # approximate the lattice-rescoring by limiting the max-ngram-order
              # if it's set, it merges histories in the lattice if they share
              # the same ngram history and this prevents the lattice from 
              # exploding exponentially

. ./path.sh # path.sh calls path.conf where $data, $exp and $mfcc are defined
. ./cmd.sh
. ./utils/parse_options.sh

if [ $# -ne 1 ]; then
  echo "This script trains a backward LMs on the swbd LM-training data, and use it"
  echo "to rescore either decoded lattices, or lattices that are just rescored with"
  echo "a forward RNNLM. In order to run this, you must first run the forward RNNLM"
  echo "recipe at local/rnnlm/run_tdnn_lstm.shThis script trains a RNN language model"
  echo "and uses it to performe lattice rescoring"
  echo ""
  echo "Usage: $0 [options] <text-set>" >&2
  echo "e.g.: $0 ~/data/language_model/training/LMtext.20181220.txt" >&2
  exit 1;
fi

text=$1
echo "training text: $text"

data_dir=$data/rnnlm
dir=$exp/rnnlm_lstm${affix}_backward
mkdir -p $dir/config

decode_dir_suffix_forward=rnnlm${affix}
decode_dir_suffix_backward=rnnlm${affix}_back
text_dir=$data_dir/text${affix}_back

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
  cat $text | awk '{for(i=NF;i>0;i--) printf("%s ", $i); print""}' | awk -v text_dir=$text_dir '{if(NR%50 == 0) { print >text_dir"/dev.txt"; } else {print;}}' >$text_dir/althingi_train.txt
#   cat > $dir/config/hesitation_mapping.txt <<EOF
# hmm hum
# mmm um
# mm um
# mhm um-hum 
# EOF
fi

if [ $stage -le 1 ]; then
  cp $langdir/words.txt $dir/config/
  n=`cat $dir/config/words.txt | wc -l`
  echo "<brk> $n" >> $dir/config/words.txt

  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <SPOKEN_NOISE> during training.
  echo "<unk>" >$dir/config/oov.txt

  cat > $dir/config/data_weights.txt <<EOF
althingi_train   1   1.0
EOF

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
  local/rnnlm/train_rnnlm_no_diagnostic.sh \
    --num-jobs-initial 3 \
    --num-jobs-final 9 \
    --stage $train_stage \
    --num-epochs 10 \
    --cmd "$big_memory_cmd --time 2-00" $dir
fi

# LM=sw1_fsh_fg # using the 4-gram const arpa file as old lm
# if [ $stage -le 4 ] && $run_lat_rescore; then
#   echo "$0: Perform lattice-rescoring on $ac_model_dir"

#   for decode_set in eval2000; do
#     decode_dir=${ac_model_dir}/decode_${decode_set}_${LM}_looped
#     if [ ! -d ${decode_dir}_${decode_dir_suffix_forward} ]; then
#       echo "$0: Must run the forward recipe first at local/rnnlm/run_tdnn_lstm.sh"
#       exit 1
#     fi

#     # Lattice rescoring
#     rnnlm/lmrescore_back.sh \
#       --cmd "$big_memory_cmd" \
#       --weight 0.45 --max-ngram-order $ngram_order \
#       $lmdir/lang_$LM $dir \
#       $data/${decode_set}_hires ${decode_dir}_${decode_dir_suffix_forward}_0.45 \
#       ${decode_dir}_${decode_dir_suffix_backward}_0.45
#   done
# fi

exit 0

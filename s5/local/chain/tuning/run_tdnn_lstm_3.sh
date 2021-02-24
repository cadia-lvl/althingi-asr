#!/bin/bash

# run_tdnn_lstm_3.sh is based on run_tdnn_lstm_1n.sh from the swbd recipe,
# while keeping in mind how much training data I have
# (I'm using 1500 hrs w/ sp, but have 6200 hrs in total)

# %WER 11.07 [ 10404 / 93964, 2354 ins, 3274 del, 4776 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_dev_3gsmall/wer_8_0.0
# %WER 10.33 [ 9710 / 93964, 2273 ins, 3132 del, 4305 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_dev_5g/wer_8_0.0
# %WER 60.47 [ 56817 / 93964, 203 ins, 46427 del, 10187 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_dev_zg/wer_8_0.0
# %WER 10.98 [ 10304 / 93845, 2092 ins, 3470 del, 4742 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_eval_3gsmall/wer_8_0.0
# %WER 10.26 [ 9632 / 93845, 1973 ins, 3386 del, 4273 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_eval_5g/wer_8_0.0
# %WER 60.73 [ 56995 / 93845, 151 ins, 46515 del, 10329 sub ] /mnt/scratch/inga/exp/chain/tdnn_lstm_3_sp/decode_eval_zg/wer_8_0.0

# The dropout was not helpful! 

set -e

# configs for 'chain'
stage=0
train_stage=-10
get_egs_stage=-10
speed_perturb=true

# Put all output on scratch
exp=/mnt/scratch/inga/exp
data=/mnt/scratch/inga/data
mfccdir=/mnt/scratch/inga/mfcc

tdnn_lstm_affix=_3  #affix for TDNN-LSTM directory, e.g. "a" or "b", in case we change the configuration.
dir=$exp/chain/tdnn_lstm${tdnn_lstm_affix} # Note: _sp will get added to this if $speed_perturb == true.

decode_iter=
generate_plots=false
calculate_bias=false
zerogram_decoding=false

# training options
xent_regularize=0.025
self_repair_scale=0.00001
label_delay=5
dropout_schedule='0,0@0.20,0.3@0.50,0'

chunk_left_context=40
chunk_right_context=0
# we'll put chunk-left-context-initial=0 and chunk-right-context-final=0
# directly without variables.
frames_per_chunk=140,100,160

# (non-looped) decoding options
frames_per_chunk_primary=$(echo $frames_per_chunk | cut -d, -f1)
extra_left_context=50
extra_right_context=0
# we'll put extra-left-context-initial=0 and extra-right-context-final=0
# directly without variables.

remove_egs=false
common_egs_dir=

test_online_decoding=false  # if true, it will run the last decoding stage.

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# The iVector-extraction and feature-dumping parts are the same as the standard
# nnet3 setup, and you can skip them by setting "--stage 8" if you have already
# run those things.

suffix=
if [ "$speed_perturb" == "true" ]; then
  suffix=_sp
fi

dir=${dir}$suffix
train_set=train_okt2017_fourth$suffix
ali_dir=$exp/tri5_ali_${train_set} #exp/tri4_cs_ali$suffix
treedir=$exp/chain/tri5_tree$suffix # NOTE!
lang=$data/lang_chain

train_data_dir=$data/${train_set}_hires
train_ivector_dir=$exp/nnet3/ivectors_${train_set}


# if we are using the speed-perturbed data we need to generate
# alignments for it.
local/nnet3/run_ivector_common.sh --stage $stage \
  --speed-perturb $speed_perturb \
  --generate-alignments $speed_perturb || exit 1;

if [ $stage -le 11 ]; then
  # Get the alignments as lattices (gives the CTC training more freedom).
  # use the same num-jobs as the alignments
  nj=$(cat ${ali_dir}/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --nj $nj --cmd "$decode_cmd --time 2-00" $data/$train_set \
    data/lang exp/tri5 $exp/tri5_lats$suffix
  rm $exp/tri5_lats$suffix/fsts.*.gz # save space
fi

if [ $stage -le 12 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r data/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 13 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --context-opts "--context-width=2 --central-position=1" \
      --cmd "$train_cmd --time 2-00" 11000 $data/$train_set $lang $ali_dir $treedir
fi

if [ $stage -le 14 ]; then
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $treedir/tree |grep num-pdfs|awk '{print $2}')
  [ -z $num_targets ] && { echo "$0: error getting num-targets"; exit 1; }
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)

  opts="l2-regularize=0.002"
  linear_opts="orthonormal-constraint=1.0"
  lstm_opts="l2-regularize=0.0005 decay-time=40"
  output_opts="l2-regularize=0.0005 output-delay=$label_delay max-change=1.5 dim=$num_targets"
 
  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-1,0,1,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 $opts dim=1280
  linear-component name=tdnn2l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-layer name=tdnn2 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn3l dim=256 $linear_opts
  relu-batchnorm-layer name=tdnn3 $opts dim=1280
  linear-component name=tdnn4l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-layer name=tdnn4 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn5l dim=256 $linear_opts
  relu-batchnorm-layer name=tdnn5 $opts dim=1280 input=Append(tdnn5l, tdnn3l)
  linear-component name=tdnn6l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn6 $opts input=Append(0,3) dim=1280
  linear-component name=lstm1l dim=256 $linear_opts input=Append(-3,0)

  # check steps/libs/nnet3/xconfig/lstm.py for the other options and defaults
  fast-lstmp-layer name=lstm1 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=128 delay=-3 dropout-proportion=0.0 $lstm_opts
  relu-batchnorm-layer name=tdnn7 $opts input=Append(0,3,tdnn6l,tdnn4l,tdnn2l) dim=1280
  linear-component name=tdnn8l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn8 $opts input=Append(0,3) dim=1280
  linear-component name=lstm2l dim=256 $linear_opts input=Append(-3,0)
  fast-lstmp-layer name=lstm2 cell-dim=1280 recurrent-projection-dim=256 non-recurrent-projection-dim=128 delay=-3 dropout-proportion=0.0 $lstm_opts
  relu-batchnorm-layer name=tdnn9 $opts input=Append(0,3,tdnn8l,tdnn6l,tdnn4l) dim=1280
  linear-component name=tdnn10l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn10 $opts input=Append(0,3) dim=1280
  linear-component name=lstm3l dim=256 $linear_opts input=Append(-3,0)
  fast-lstmp-layer name=lstm3 cell-dim=1280 recurrent-projection-dim=256 non-recurrent-projection-dim=128 delay=-3 dropout-proportion=0.0 $lstm_opts

  ## adding the layers for chain branch
  output-layer name=output input=lstm3 include-log-softmax=false $output_opts

  # adding the layers for xent branch
  # This block prints the configs for a separate output that will be
  # trained with a cross-entropy objective in the 'chain' models... this
  # has the effect of regularizing the hidden parts of the model.  we use
  # 0.5 / args.xent_regularize as the learning rate factor- the factor of
  # 0.5 / args.xent_regularize is suitable as it means the xent
  # final-layer learns at a rate independent of the regularization
  # constant; and the 0.5 was tuned so as to make the relative progress
  # similar in the xent and regular final layers.
  output-layer name=output-xent input=lstm3 learning-rate-factor=$learning_rate_factor $output_opts

EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs
fi

if [ $stage -le 15 ]; then

  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd --time 3-12" \
    --feat.online-ivector-dir $train_ivector_dir \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.0 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.num-chunk-per-minibatch 64,32 \
    --trainer.frames-per-iter 1500000 \
    --trainer.max-param-change 2.0 \
    --trainer.num-epochs 8 \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 16 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.optimization.momentum 0.0 \
    --trainer.deriv-truncate-margin 8 \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $frames_per_chunk \
    --egs.chunk-left-context $chunk_left_context \
    --egs.chunk-right-context $chunk_right_context \
    --egs.chunk-left-context-initial 0 \
    --egs.chunk-right-context-final 0 \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --feat-dir $train_data_dir \
    --tree-dir $treedir \
    --lat-dir $exp/tri5_lats$suffix \
    --dir $dir  || exit 1;
fi

if [ $stage -le 16 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  echo "Make a small 3-gram graph"
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_3gsmall $dir $dir/graph_3gsmall
fi

graph_dir=$dir/graph_3gsmall
iter_opts=
if [ ! -z $decode_iter ]; then
  iter_opts=" --iter $decode_iter "
fi

if [ $stage -le 17 ]; then
  rm $dir/.error 2>/dev/null || true
  for decode_set in dev eval; do
    (
      num_jobs=`cat $data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet3/decode.sh --num-threads 4 \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
        --extra-left-context $extra_left_context  \
        --extra-right-context $extra_right_context  \
        --extra-left-context-initial 0 \
        --extra-right-context-final 0 \
        --frames-per-chunk "$frames_per_chunk_primary" \
        --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
        $graph_dir $data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_3gsmall || exit 1;
      steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        data/lang_{3gsmall,5g} $data/${decode_set}_hires \
        $dir/decode_${decode_set}_{3gsmall,5g} || exit 1;
    ) &
  done
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi
fi

if [ $generate_plots = true ]; then
    echo "Generating plots and compiling a latex report on the training"
    steps/nnet3/report/generate_plots.py \
	--is-chain true $dir $dir/report_tdnn_lstm${tdnn_lstm_affix}$suffix
fi

if [ $zerogram_decoding = true ]; then
  echo "Do zerogram decoding to check the effect of the LM"
  rm $dir/.error 2>/dev/null || true

  echo "Make a zerogram graph"
  utils/slurm.pl --mem 4G --time 0-06 $dir/log/mkgraph_zg.log utils/mkgraph.sh --self-loop-scale 1.0 data/lang_zg $dir $dir/graph_zg
  
  for decode_set in dev eval; do
    (
      num_jobs=`cat $data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet3/decode.sh --num-threads 4 \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
        --extra-left-context $extra_left_context  \
        --extra-right-context $extra_right_context  \
        --extra-left-context-initial 0 \
        --extra-right-context-final 0 \
        --frames-per-chunk "$frames_per_chunk_primary" \
        --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
        $dir/graph_zg $data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_zg || exit 1;
    ) &
  done
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in the zerogram decoding"
    exit 1
  fi
fi

if [ $calculate_bias = true ]; then
  echo "Calculate the bias by decoding a subset of the training set"
  rm $dir/.error 2>/dev/null || true
  for decode_set in train-dev; do
    (
      num_jobs=`cat $data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet3/decode.sh --num-threads 4 \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
        --extra-left-context $extra_left_context  \
        --extra-right-context $extra_right_context  \
        --extra-left-context-initial 0 \
        --extra-right-context-final 0 \
        --frames-per-chunk "$frames_per_chunk_primary" \
        --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
        $graph_dir $data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_3gsmall || exit 1;
    ) &
  done
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in the train-dev decoding"
    exit 1
  fi
fi

exit 0;

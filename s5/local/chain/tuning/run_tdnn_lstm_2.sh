#!/bin/bash

# run_tdnn_lstm_2.sh is based on run_tdnn_lstm_1e.sh from the swbd recipe
# and run_tdnn_lstm_1b.sh from the fisher_swbd recipe.

# %WER 10.19 [ 9578 / 94001, 2170 ins, 3076 del, 4332 sub ] exp/chain/tdnn_lstm_2_sp/decode_dev_3gsmall/wer_8_0.0
# %WER 9.48 [ 8913 / 94001, 2085 ins, 2968 del, 3860 sub ] exp/chain/tdnn_lstm_2_sp/decode_dev_5g/wer_8_0.0
# %WER 58.66 [ 55140 / 94001, 188 ins, 47258 del, 7694 sub ] exp/chain/tdnn_lstm_2_sp/decode_dev_zg/wer_8_0.0
# %WER 10.14 [ 9519 / 93879, 1905 ins, 3378 del, 4236 sub ] exp/chain/tdnn_lstm_2_sp/decode_eval_3gsmall/wer_8_0.0
# %WER 9.48 [ 8899 / 93879, 1828 ins, 3196 del, 3875 sub ] exp/chain/tdnn_lstm_2_sp/decode_eval_5g/wer_8_0.0
# %WER 58.84 [ 55242 / 93879, 144 ins, 47274 del, 7824 sub ] exp/chain/tdnn_lstm_2_sp/decode_eval_zg/wer_8_0.0

set -e

# configs for 'chain'
stage=0
align_stage=0
train_stage=-10
get_egs_stage=-10
speed_perturb=true

# Defined in conf/path.conf, default to /mnt/scratch/inga/{exp,data,mfcc}
exp=
data=
mfccdir=

affix=_2  #affix for TDNN-LSTM directory, e.g. "a" or "b", in case we change the configuration.

# GMM to use for alignments
gmm=tri5
generate_ali_from_lats=false

decode_iter=
generate_plots=false # Generate plots showing how parameters were updated throughout training and log-probability changes
calculate_bias=false
zerogram_decoding=false

# training options
xent_regularize=0.025
self_repair_scale=0.00001
label_delay=5
dropout_schedule=

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
. ./conf/path.conf

# # LMs
lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)
decoding_lang=$lmdir/lang_3gsmall
rescoring_lang=$lmdir/lang_5g
langdir=$lmdir/lang

if [ ! $# = 2 ]; then
  echo "This script trains a deep neural network with both time-delay feed forward layers"
  echo "and long-short-time-memory recurrent layers."
  echo "The new model is also tested on a development set"
  echo ""
  echo "Usage: $0 [options] <input-training-data> <test-data-dir>"
  echo " e.g.: $0 data/train data"
  echo ""
  echo "Options:"
  echo "    --speed_perturb <bool>       # apply speed perturbations, default: true"
  echo "    --generate-ali-from-lats <bool> # ali.*.gz is generated in lats dir, default: false"
  echo "    --affix <affix>              # idendifier for the model, e.g. _1b"
  echo "    --decode-iter <iter>         # iteration of model to test"
  echo "    --generate-plots <bool>      # generate a report on the training"
  echo "    --calculate-bias <bool>      # estimate the bias by decoding a subset of the training set"
  echo "    --zerogram-decoding <bool>   # check the effect of the LM on the decoding results"
  exit 1;
fi

inputdata=$1
testdatadir=$2

( ! cmp $langdir/words.txt $decoding_lang/words.txt || \
! cmp $decoding_lang/words.txt $rescoring_lang/words.txt ) && \
  echo "$0: Warning: vocabularies may be incompatible."

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
$speed_perturb && suffix=_sp
dir=${exp}/chain/tdnn_lstm${affix}${suffix}

train_set=$(basename $inputdata)$suffix
ali_dir=${exp}/${gmm}_ali_${train_set} #exp/tri4_cs_ali$suffix
treedir=${exp}/chain/${gmm}_tree$suffix # NOTE!
lang=${data}/lang_chain

# if we are using the speed-perturbed data we need to generate
# alignments for it.
# # Original
local/nnet3/run_ivector_common.sh --stage $stage \
  --speed-perturb $speed_perturb \
  --generate-alignments $speed_perturb \
  $inputdata $testdatadir $langdir $gmm || exit 1;

# See if regular alignments already exist
if [ -f ${ali_dir}/num_jobs ]; then
  n_alijobs=$(cat ${ali_dir}/num_jobs)
else
  n_alijobs=`cat $data/${train_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
  generate_ali_from_lats=true
  ali_dir=$exp/${gmm}_lats$suffix
fi

if [ $stage -le 11 ]; then
  # Get the alignments as lattices (gives the CTC training more freedom).
  # use the same num-jobs as the alignments
  #nj=$(cat ${ali_dir}/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh \
    --nj $n_alijobs --stage $align_stage \
    --cmd "$decode_cmd --time 4-00" \
    --generate-ali-from-lats $generate_ali_from_lats \
    $data/$train_set $langdir \
    $exp/${gmm} $exp/${gmm}_lats$suffix
  rm ${exp}/${gmm}_lats$suffix/fsts.*.gz # save space
fi

if [ $stage -le 12 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r $langdir $lang
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

  lstm_opts="decay-time=20"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1,2,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 dim=1024
  relu-batchnorm-layer name=tdnn2 input=Append(-1,0,1) dim=1024
  relu-batchnorm-layer name=tdnn3 input=Append(-1,0,1) dim=1024

  # check steps/libs/nnet3/xconfig/lstm.py for the other options and defaults
  fast-lstmp-layer name=fastlstm1 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
  relu-batchnorm-layer name=tdnn4 input=Append(-3,0,3) dim=1024
  relu-batchnorm-layer name=tdnn5 input=Append(-3,0,3) dim=1024
  relu-batchnorm-layer name=tdnn6 input=Append(-3,0,3) dim=1024
  fast-lstmp-layer name=fastlstm2 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts
  relu-batchnorm-layer name=tdnn7 input=Append(-3,0,3) dim=1024
  relu-batchnorm-layer name=tdnn8 input=Append(-3,0,3) dim=1024
  fast-lstmp-layer name=fastlstm3 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $lstm_opts

  ## adding the layers for chain branch
  output-layer name=output input=fastlstm3 output-delay=$label_delay include-log-softmax=false dim=$num_targets max-change=1.5

  # adding the layers for xent branch
  # This block prints the configs for a separate output that will be
  # trained with a cross-entropy objective in the 'chain' models... this
  # has the effect of regularizing the hidden parts of the model.  we use
  # 0.5 / args.xent_regularize as the learning rate factor- the factor of
  # 0.5 / args.xent_regularize is suitable as it means the xent
  # final-layer learns at a rate independent of the regularization
  # constant; and the 0.5 was tuned so as to make the relative progress
  # similar in the xent and regular final layers.
  output-layer name=output-xent input=fastlstm3 output-delay=$label_delay dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5

EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs
fi

if [ $stage -le 15 ]; then

  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd --time 3-12" \
    --feat.online-ivector-dir $exp/nnet3/ivectors_${train_set} \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.num-chunk-per-minibatch 64,32 \
    --trainer.frames-per-iter 1500000 \
    --trainer.max-param-change 2.0 \
    --trainer.num-epochs 6 \
    --trainer.optimization.shrink-value 0.99 \
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
    --feat-dir $data/${train_set}_hires \
    --tree-dir $treedir \
    --lat-dir ${exp}/${gmm}_lats$suffix \
    --dir $dir  || exit 1;
fi

if [ $stage -le 16 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  echo "Make a small 3-gram graph"
  utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $dir $dir/graph_3gsmall
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
        --online-ivector-dir ${exp}/nnet3/ivectors_${decode_set} \
        $graph_dir $data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_3gsmall || exit 1;
      steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        $decoding_lang $rescoring_lang $data/${decode_set}_hires \
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
	--is-chain true $dir $dir/report_tdnn_lstm${affix}$suffix
fi

if [ $zerogram_decoding = true ]; then
  echo "Do zerogram decoding to check the effect of the LM"
  rm $dir/.error 2>/dev/null || true

  if [ ! -d $data/lang_zg ] ; then
    echo "A zerogram language model doesn't exist";
    echo "You need to create it first"
    exit 1;
  fi
    
  echo "Make a zerogram graph"
  utils/slurm.pl --mem 4G --time 0-06 $dir/log/mkgraph_zg.log utils/mkgraph.sh --self-loop-scale 1.0 $data/lang_zg $dir $dir/graph_zg
    
  for decode_set in dev eval; do
    (
      num_jobs=`cat data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet3/decode.sh --num-threads 4 \
        --acwt 1.0 --post-decode-acwt 10.0 \
        --nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
        --extra-left-context $extra_left_context  \
        --extra-right-context $extra_right_context  \
        --extra-left-context-initial 0 \
        --extra-right-context-final 0 \
        --frames-per-chunk "$frames_per_chunk_primary" \
        --online-ivector-dir ${exp}/nnet3/ivectors_${decode_set} \
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

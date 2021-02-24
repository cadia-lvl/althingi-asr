#!/bin/bash
# Copyright 2017 University of Chinese Academy of Sciences (UCAS) Gaofeng Cheng
# Apache 2.0

# This is based on TDNN_LSTM_1b (from egs/swbd/s5c), but using the NormOPGRU to replace the LSTMP,
# and adding chunk-{left,right}-context-initial=0
# Different from the vanilla OPGRU, Norm-OPGRU adds batchnorm in its output (forward direction)
# and renorm in its recurrence. Experiments show that the TDNN-NormOPGRU could achieve similar
# results than TDNN-LSTMP and BLSTMP in both large or small data sets (80 ~ 2300 Hrs).

# ./local/chain/compare_wer_general.sh tdnn_lstm_1a_sp tdnn_lstm_1b_sp tdnn_opgru_1a_sp
# num parameter         39.7M           39.7M           34.9M
# System                tdnn_lstm_1a_sp tdnn_lstm_1b_sp tdnn_opgru_1a_sp
# WER on eval2000(tg)        12.3      12.3      11.7
#           [looped:]        12.2      12.3      11.6
# WER on eval2000(fg)        12.1      12.0      11.7
#           [looped:]        12.1      12.2      11.6
# WER on rt03(tg)            11.6      11.4      11.0
#           [looped:]        11.6      11.6      11.0
# WER on rt03(fg)            11.3      11.1      10.7
#           [looped:]        11.3      11.3      10.8
# Final train prob         -0.074    -0.087    -0.085
# Final valid prob         -0.084    -0.088    -0.093
# Final train prob (xent)        -0.882    -1.015    -0.972
# Final valid prob (xent)       -0.9393   -0.9837   -1.0275

#./steps/info/chain_dir_info.pl exp/chain/tdnn_opgru_1a_sp
#exp/chain/tdnn_opgru_1a_sp: num-iters=2384 nj=3..16 num-params=34.9M dim=40+100->6149 combine=-0.096->-0.095 (over 8) 
#xent:train/valid[1587,2383,final]=(-1.46,-0.960,-0.972/-1.49,-1.02,-1.03) 
#logprob:train/valid[1587,2383,final]=(-0.114,-0.086,-0.085/-0.114,-0.094,-0.093)

# online results
# Eval2000
# %WER 14.7 | 2628 21594 | 87.3 8.5 4.2 2.0 14.7 50.8 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_tg/score_7_0.0/eval2000_hires.ctm.callhm.filt.sys
# %WER 11.7 | 4459 42989 | 89.9 7.0 3.1 1.7 11.7 48.1 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_tg/score_7_0.0/eval2000_hires.ctm.filt.sys
# %WER 8.3 | 1831 21395 | 92.7 4.9 2.4 1.0 8.3 42.2 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_tg/score_10_0.0/eval2000_hires.ctm.swbd.filt.sys
# %WER 14.7 | 2628 21594 | 87.4 8.5 4.1 2.1 14.7 50.5 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_fg/score_7_0.0/eval2000_hires.ctm.callhm.filt.sys
# %WER 11.6 | 4459 42989 | 90.1 6.9 3.0 1.7 11.6 47.6 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_fg/score_7_0.0/eval2000_hires.ctm.filt.sys
# %WER 8.1 | 1831 21395 | 92.9 4.8 2.3 1.1 8.1 41.8 | exp/chain/tdnn_opgru_1a_sp_online/decode_eval2000_fsh_sw1_fg/score_10_0.0/eval2000_hires.ctm.swbd.filt.sys

# online results
# RT03
# %WER 8.9 | 3970 36721 | 92.1 5.3 2.5 1.1 8.9 37.3 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_tg/score_7_0.0/rt03_hires.ctm.fsh.filt.sys
# %WER 11.0 | 8420 76157 | 90.1 6.1 3.8 1.1 11.0 41.0 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_tg/score_9_0.0/rt03_hires.ctm.filt.sys
# %WER 13.0 | 4450 39436 | 88.3 7.7 4.0 1.3 13.0 43.1 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_tg/score_8_0.0/rt03_hires.ctm.swbd.filt.sys
# %WER 8.6 | 3970 36721 | 92.4 4.9 2.8 1.0 8.6 37.2 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_fg/score_8_0.0/rt03_hires.ctm.fsh.filt.sys
# %WER 10.8 | 8420 76157 | 90.4 6.2 3.4 1.2 10.8 40.0 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_fg/score_8_0.0/rt03_hires.ctm.filt.sys
# %WER 12.8 | 4450 39436 | 88.6 7.5 4.0 1.4 12.8 42.5 | exp/chain/tdnn_opgru_1a_sp_online/decode_rt03_fsh_sw1_fg/score_8_0.0/rt03_hires.ctm.swbd.filt.sys
 

set -e

# configs for 'chain'
stage=0
align_stage=0
train_stage=-10
get_egs_stage=-10
speed_perturb=true
affix=
decode_iter=
decode_dir_affix=
dropout_schedule='0,0@0.20,0.2@0.50,0'

# training options
leftmost_questions_truncate=-1
chunk_width=150
chunk_left_context=40
chunk_right_context=0
xent_regularize=0.025
self_repair_scale=0.00001
label_delay=5
# decode options
extra_left_context=50
extra_right_context=0
frames_per_chunk=

remove_egs=false
common_egs_dir=

# GMM to use for alignments
gmm=tri5
generate_ali_from_lats=false

generate_plots=false

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;

# LMs
lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)
decoding_lang=$lmdir/lang_3gsmall
rescoring_lang=$lmdir/lang_5g
zerogramLM=$lmdir/lang_zg
langdir=$lmdir/lang


if [ ! $# = 2 ]; then
  echo "This script trains a factorized time delay deep neural network"
  echo "and tests the new model on a development set"
  echo ""
  echo "Usage: $0 [options] <input-training-data> <test-data-dir>"
  echo " e.g.: $0 data/train_okt2017_500k_cleaned data"
  echo ""
  echo "Options:"
  echo "    --speed-perturb <bool>           # apply speed perturbations, default: true"
  echo "    --generate-ali-from-lats <bool>  # ali.*.gz is generated in lats dir, default: false"
  echo "    --affix <affix>                  # idendifier for the model, e.g. _1b"
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
if [ "$speed_perturb" == "true" ]; then
  suffix=_sp
fi

dir=$exp/chain/tdnn_opgru # Note: _sp will get added to this if $speed_perturb == true.
base=$(basename $dir)
dir=${dir}$affix$suffix
train_set=$(basename $inputdata)$suffix
ali_dir=$exp/${gmm}_ali_${train_set}
treedir=$exp/chain/${gmm}_tree$suffix
lang=$data/lang_chain

# if we are using the speed-perturbed data we need to generate
# alignments for it.
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

if [ $stage -le 9 ]; then
  # Get the alignments as lattices (gives the CTC training more freedom).
  # use the same num-jobs as the alignments
  #nj=$(cat $ali_dir/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh \
    --nj $n_alijobs --stage $align_stage \
    --cmd "$decode_cmd --time 4-00" \
    --generate-ali-from-lats $generate_ali_from_lats \
    $data/$train_set $langdir \
    $exp/${gmm} $exp/${gmm}_lats$suffix
  rm $exp/${gmm}_lats$suffix/fsts.*.gz # save space
fi

if [ $stage -le 10 ]; then
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

if [ $stage -le 11 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --leftmost-questions-truncate $leftmost_questions_truncate \
      --context-opts "--context-width=2 --central-position=1" \
      --cmd "$train_cmd --time 4-00" 11000 $data/$train_set $lang $ali_dir $treedir
fi

if [ $stage -le 12 ]; then
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $treedir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)
  gru_opts="dropout-per-frame=true dropout-proportion=0.0 "

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1,2, ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 dim=1024
  relu-batchnorm-layer name=tdnn2 input=Append(-1,0,1) dim=1024
  relu-batchnorm-layer name=tdnn3 input=Append(-1,0,1) dim=1024

  # check steps/libs/nnet3/xconfig/lstm.py for the other options and defaults
  norm-opgru-layer name=opgru1 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $gru_opts
  relu-batchnorm-layer name=tdnn4 input=Append(-3,0,3) dim=1024
  relu-batchnorm-layer name=tdnn5 input=Append(-3,0,3) dim=1024
  norm-opgru-layer name=opgru2 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $gru_opts
  relu-batchnorm-layer name=tdnn6 input=Append(-3,0,3) dim=1024
  relu-batchnorm-layer name=tdnn7 input=Append(-3,0,3) dim=1024
  norm-opgru-layer name=opgru3 cell-dim=1024 recurrent-projection-dim=256 non-recurrent-projection-dim=256 delay=-3 $gru_opts

  ## adding the layers for chain branch
  output-layer name=output input=opgru3 output-delay=$label_delay include-log-softmax=false dim=$num_targets max-change=1.5

  # adding the layers for xent branch
  # This block prints the configs for a separate output that will be
  # trained with a cross-entropy objective in the 'chain' models... this
  # has the effect of regularizing the hidden parts of the model.  we use
  # 0.5 / args.xent_regularize as the learning rate factor- the factor of
  # 0.5 / args.xent_regularize is suitable as it means the xent
  # final-layer learns at a rate independent of the regularization
  # constant; and the 0.5 was tuned so as to make the relative progress
  # similar in the xent and regular final layers.
  output-layer name=output-xent input=opgru3 output-delay=$label_delay dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5

EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 13 ]; then

  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd --time 3-12" \
    --feat.online-ivector-dir $exp/nnet3/ivectors_${train_set} \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.num-chunk-per-minibatch 64 \
    --trainer.frames-per-iter 1200000 \
    --trainer.max-param-change 2.0 \
    --trainer.num-epochs 4 \
    --trainer.optimization.shrink-value 0.99 \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 16 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.optimization.momentum 0.0 \
    --trainer.deriv-truncate-margin 8 \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $chunk_width \
    --egs.chunk-left-context $chunk_left_context \
    --egs.chunk-right-context $chunk_right_context \
    --egs.chunk-left-context-initial 0 \
    --egs.chunk-right-context-final 0 \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --feat-dir $data/${train_set}_hires \
    --tree-dir $treedir \
    --lat-dir $exp/${gmm}_lats$suffix \
    --dir $dir  || exit 1;
fi

if [ $stage -le 14 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  echo "Make a small 3-gram graph"
  utils/slurm.pl --mem 8G $dir/log/mkgraph.log utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $dir $dir/graph_3gsmall
fi

graph_dir=$dir/graph_3gsmall
iter_opts=
if [ $stage -le 15 ]; then
  rm $dir/.error 2>/dev/null || true
  [ -z $extra_left_context ] && extra_left_context=$chunk_left_context;
  [ -z $extra_right_context ] && extra_right_context=$chunk_right_context;
  [ -z $frames_per_chunk ] && frames_per_chunk=$chunk_width;
  if [ ! -z $decode_iter ]; then
    iter_opts=" --iter $decode_iter "
  fi
  for decode_set in dev eval; do
    (
      num_jobs=`cat $data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l`
      steps/nnet3/decode.sh \
	--acwt 1.0 --post-decode-acwt 10.0 \
	--nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
	--extra-left-context $extra_left_context  \
	--extra-right-context $extra_right_context  \
	--extra-left-context-initial 0 \
	--extra-right-context-final 0 \
	--frames-per-chunk "$frames_per_chunk" \
	--online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
         $graph_dir $data/${decode_set}_hires \
         $dir/decode_${decode_set}${decode_dir_affix:+_$decode_dir_affix}_3gsmall || exit 1;
      steps/lmrescore_const_arpa.sh \
	--cmd "$decode_cmd" \
	$decoding_lang $rescoring_lang $data/${decode_set}_hires \
        $dir/decode_${decode_set}${decode_dir_affix:+_$decode_dir_affix}_{3gsmall,5g} || exit 1;
      ) || touch $dir/.error &
  done
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi
fi

if [ $generate_plots = true ]; then
  echo "Generating plots and compiling a latex report on the training"
  if [[ $(hostname -f) == terra.hir.is ]]; then
    source $CONDAPATH/activate thenv || error 11 $LINENO "Can't activate thenv";
    steps/nnet3/report/generate_plots.py \
      --is-chain true $dir $dir/report_${base}${affix}$suffix
    source $CONDAPATH/deactivate
  else
    steps/nnet3/report/generate_plots.py \
      --is-chain true $dir $dir/report_${base}${affix}$suffix
  fi
fi

exit 0;

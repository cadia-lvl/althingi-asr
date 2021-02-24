#!/bin/bash

# this is the standard "tdnn" system, built in nnet3; it's what we use to
# call multi-splice.

# without cleanup:
# local/nnet3/run_tdnn.sh  --train-set train960 --gmm tri6b --nnet3-affix "" & 


# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

# First the options that are passed through to run_ivector_common.sh
# (some of which are also used in this script directly).
stage=0
decode_nj=32
min_seg_len=1.55
train_set=train
gmm=tri3  # this is the source gmm-dir for the data-type of interest; it
                   # should have alignments for the specified training data.
nnet3_affix=

# Options which are not passed through to run_ivector_common.sh
affix=
train_stage=-10
common_egs_dir=
reporting_email=
remove_egs=true

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

local/nnet3/run_ivector_common.sh --stage $stage \
                                  --min-seg-len $min_seg_len \
                                  --train-set $train_set \
                                  --gmm $gmm \
                                  --nnet3-affix "$nnet3_affix" || exit 1;


gmm_dir=exp/${gmm}
graph_dir=$gmm_dir/graph_tg_bd
ali_dir=exp/${gmm}_ali_${train_set}_sp_comb
dir=exp/nnet3${nnet3_affix}/tdnn${affix:+_$affix}_sp
train_data_dir=data/${train_set}_sp_hires_comb
train_ivector_dir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires_comb


for f in $train_data_dir/feats.scp $train_ivector_dir/ivector_online.scp \
     $graph_dir/HCLG.fst $ali_dir/ali.1.gz $gmm_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 11 ]; then
  steps/nnet3/train_tdnn.sh --stage $train_stage \
    --num-epochs 8 --num-jobs-initial 2 --num-jobs-final 14 \
    --splice-indexes "-4,-3,-2,-1,0,1,2,3,4  0  -2,2  0  -4,4 0" \
    --feat-type raw \
    --online-ivector-dir $train_ivector_dir \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --relu-dim 450 \
    --initial-effective-lrate 0.005 --final-effective-lrate 0.0005 \
    --cmd "$decode_cmd" \
    $train_data_dir data/lang $ali_dir $dir  || exit 1;
fi

## I comment out the following because I get an error regarding one of the config parameters. --max-change is unused.
# if [ $stage -le 11 ]; then
#   echo "$0: creating neural net configs";

#   # create the config files for nnet initialization. Original relu-dim = 1280
#   python steps/nnet3/tdnn/make_configs.py  \
#     --feat-dir $train_data_dir \
#     --ivector-dir $train_ivector_dir \
#     --ali-dir $ali_dir \
#     --relu-dim 640 \
#     --splice-indexes "-2,-1,0,1,2 -1,2 -3,3 -7,2 0"  \
#     --use-presoftmax-prior-scale true \
#     --max-change-per-component 0 \
#    $dir/configs || exit 1;
# fi

# if [ $stage -le 12 ]; then
#   # I added the samples-per-iter and use-gpu arguments. Samples-per-iter was by default 20000 but in train_tdnn.sh it was 400000
#   steps/nnet3/train_dnn.py --stage=$train_stage \
#     --cmd="$decode_cmd" \
#     --feat.online-ivector-dir $train_ivector_dir \
#     --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
#     --trainer.num-epochs 4 \
#     --trainer.optimization.num-jobs-initial 3 \
#     --trainer.optimization.num-jobs-final 16 \
#     --trainer.optimization.initial-effective-lrate 0.0017 \
#     --trainer.optimization.final-effective-lrate 0.00017 \
#     --trainer.samples-per-iter 20000 \
#     --egs.dir "$common_egs_dir" \
#     --egs.cmd="$decode_cmd" \
#     --cleanup.remove-egs $remove_egs \
#     --cleanup.preserve-model-interval 100 \
#     --use-gpu true \
#     --feat-dir=$train_data_dir \
#     --ali-dir $ali_dir \
#     --lang data/lang \
#     --reporting.email="$reporting_email" \
#     --dir=$dir  || exit 1;

# fi

if [ $stage -le 13 ]; then
  # this does offline decoding that should give about the same results as the
    # real online decoding (the one with --per-utt true)
  rm $dir/.error 2>/dev/null || true
  for decode_set in eval dev; do
    (
    steps/nnet3/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
      --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_${decode_set}_hires \
      ${graph_dir} data/${decode_set}_hires $dir/decode_${decode_set}_tg_bd || exit 1
    steps/lmrescore.sh --cmd "$decode_cmd" data/lang_{tg,fg}_bd \
      data/${decode_set}_hires $dir/decode_${decode_set}_{tg,fg}_bd  || exit 1
    #steps/lmrescore_const_arpa.sh \
    #  --cmd "$decode_cmd" data/lang_{tg,fg}_bd \
    #  data/${test}_hires $dir/decode_${test}_{tg,fg}_bd || exit 1
    ) || touch $dir/.error &
  done

  # for test in dev eval; do
  #   (
  #   steps/nnet3/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
  #     --online-ivector-dir exp/nnet3${nnet3_affix}/ivectors_${test}_hires \
  #     ${graph_dir} data/${test}_hires $dir/decode_${test}_tg_bd || exit 1
  #   ) || touch $dir/.error &
  # done
  wait
  [ -f $dir/.error ] && echo "$0: there was a problem while decoding" && exit 1
fi

exit 0;


#!/bin/bash

# Apply RNN LM rescoring

order=3
rnn_ngram_order=4 # approximate the lattice-rescoring by limiting the
                  # max-ngram-order if it's set, it merges histories
                  # in the lattice if they share the same ngram history
                  # and this prevents the lattice from exploding exponentially
pruned_rescore=true
decode_dir_suffix=rnnlm

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "This script performs lattice rescoring using an rnn language model"
  echo ""
  echo "Usage: $0 [options] <rnn-lm-dir> <acoustic-model-dir>" >&2
  echo "e.g.: $0 ~/models/language_model/20180905/rnn $exp/chain/tdnn_2" >&2
  exit 1;
fi

rnnlmdir=$1; shift
ac_model_dir=$1

#rnnlmdir=$(ls -td $root_lm_modeldir/20*/rnn | head -n1) || exit 1
#ac_model_dir=$(ls -td $exp/chain/tdnn* | head -n1)
ngram_lm=$rnnlmdir/../lang_3gsmall

# Calculate the lattice-rescoring time
begin=$(date +%s)

if [ $order = 3 ]; then
  LM=3gsmall # if using the small 3-gram G.fst file as old lm
elif [ $order = 5 ]; then
  LM=5g  # if using the 5-gram carpa file as old lm
fi

echo "$0: Perform lattice-rescoring on $ac_model_dir"

pruned=
if $pruned_rescore; then
  pruned=_pruned
fi
for decode_set in dev eval; do
  (
    decode_dir=${ac_model_dir}/decode_${decode_set}_${LM}

    # Lattice rescoring
    rnnlm/lmrescore$pruned.sh \
      --cmd "$big_memory_cmd" \
      --weight 0.5 --max-ngram-order $rnn_ngram_order \
      $ngram_lm $rnnlmdir \
      $data/${decode_set}_hires ${decode_dir} \
      ${decode_dir}_${decode_dir_suffix} || exit 1;
  ) &
done
wait

end=$(date +%s)
tottime=$(expr $end - $begin)
echo "total time: $tottime seconds"

exit 0;

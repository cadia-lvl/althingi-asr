#!/bin/bash

# Script that calculates the decoding real-time-factor of a model
# To be run from the s5 dir

frames_per_sec=40

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 1 ]; then
  echo "This script calculates the decoding real-time-factor of a model"
  echo ""
  echo "Usage: $0 <decoding-dir>" >&2
  echo "e.g.: $0 exp/chain/tdnn/decoding_dev_3gsmall" >&2
  echo "Options:"
  echo " --frames-per-sec <n>         # The number of frames per second used"
  exit 1;
fi

dir=$1 # $exp/chain/tdnn_2/decode_dev_3gsmall

time_taken=$(egrep -o "Time taken [^ :]+" $dir/log/decode.*.log | cut -d" " -f3 | sed -r 's:s::g' | awk '{sum = sum + $1}END{print sum;}')
frames=$(egrep "Overall log-likelihood" $dir/log/decode.*.log | egrep -o "[0-9]+ frames." | cut -d" " -f1 | awk '{sum = sum + $1}END{print sum;}')

rtf=$(echo "scale=5;$time_taken/$frames*$frames_per_sec" | bc)
echo "Real-time-factor: "$rtf

exit 0;

#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

set -o pipefail

# After segmenting the data calculate words per second
# for each segment - 2016 Inga Rún

if [ $# -ne 1 ]; then
    echo "Usage: $0 <data-dir> " >&2
    echo "Eg. $0 data/all_reseg" >&2
    exit 1;
fi

datadir=$1

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ -f ${datadir}/wps.txt ]; then
  rm ${datadir}/wps.txt
fi
# Calculate the length of each segment
awk 'NR >= 1 { $5 = $4 - $3 } 1' < ${datadir}/segments > $tmp/segments_diff.tmp
awk '{print NF-1" "$0}' < ${datadir}/text  > $tmp/wordcount.tmp
join -1 1 -2 2 $tmp/segments_diff.tmp $tmp/wordcount.tmp > $tmp/wc_sec.tmp # Join on uttID
awk '{ wps=($6)/($5+0.0001) ; wps_r=sprintf("%.2f",wps); print wps_r" "$0 }' \
    < $tmp/wc_sec.tmp > ${datadir}/wps.txt

exit 0


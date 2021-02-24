#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

set -o pipefail

# Select segments to keep based on words/second ratio for each congressman.
# Cut out segments with wps outside 10 and 90 percentiles of all segments
# and with wps outside 5 and 95 percentiles for that particular speaker.

if [ $# -ne 2 ]; then
    echo "Usage: $0 <orig-data-dir> <new-data-dir>" >&2
    echo "Eg. $0 data/all_reseg data/all_reseg_filtered" >&2
    exit 1;
fi

dir=$1
newdir=$2
mkdir -p $newdir

#for s in spk2utt text utt2spk wav.scp wps_stats.txt wps.txt; do
for s in spk2utt text utt2spk wav.scp wps.txt; do
  [ ! -e ${newdir}/$s ] && cp -r ${dir}/$s ${newdir}/$s
done

# Filter using constant values
awk -F" " '{if ($1 > 0.4 && $1 < 5.5) print;}' < ${newdir}/wps.txt > ${newdir}/wps_filtered.txt

# Filter the segments
join -1 1 -2 1 <(cut -d" " -f2 ${newdir}/wps_filtered.txt | sort) <(sort ${dir}/segments) | LC_ALL=C sort > ${newdir}/segments

# Sort and filter the other files
utils/validate_data_dir.sh --no-feats ${newdir} || utils/fix_data_dir.sh ${newdir}

exit 0

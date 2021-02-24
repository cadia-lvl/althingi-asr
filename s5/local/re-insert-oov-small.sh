#!/bin/bash -e

# Copyright 2018  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

set -o pipefail

textfile=$1
wordfile=$2
textfile_wOOV="${textfile%.*}.wOOV.txt"

cp $textfile $textfile_wOOV
for w in $(cat $wordfile); do
  sed -i "s:<word>:$w:" $textfile_wOOV
done

exit 0;

#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

. ./path.sh
. ./local/utils.sh
. ./local/array.sh

if [ $# -ne 2 ]; then
  echo "This script prepares XML text data to be used to train a model in learning"
  echo "the positions of paragraph breaks. It switches the XML tags </mgr><mgr> out for"
  echo "' EOP ', removes the remaining XML tags and splits the data into train/test sets"
  exit 1;
fi

indir=$1
dir=$2 #paragraph/data/may18
mkdir -p $dir

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

for d in $indir/all_*; do
  sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' -e 's:</mgr><mgr>: EOP :g' -e 's:<[^>]*?>: :g' \
    -e 's:^rad[0-9T]+ ::' \
    -e 's:\([^/()<>]*?\)+: :g' -e 's: ,,: :g' -e 's:\.\.+ :. :g' -e 's: ([,.:;?!] ):\1:g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |_+: :g' \
    -e 's: $: EOP :' -e 's:[[:space:]]+: :g' \
    -e 's:(EOP )+:EOP :g' -e 's:([—,—]) EOP:\1:g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9]) EOP :\1. :g' -e 's:EOP[,.:;?!] :EOP :g' \
  < ${d}/text_orig_endanlegt.txt \
  >> ${tmp}/text_noXML_endanlegt.txt || error 13 $LINENO ${error_array[13]};
done

# NOTE! If I want to remove everything that won't be in the ASR/punctuation output, add this above:
# sed -re 's:, | — | — : :g' -e 's:[!;]:.:g' 

# Split up to train, dev and test set
nlines10=$(echo $((($(wc -l ${tmp}/text_noXML_endanlegt.txt | cut -d" " -f1)+1)/10)))
sort -R ${tmp}/text_noXML_endanlegt.txt > ${tmp}/shuffled.tmp || error 13 $LINENO ${error_array[13]};

head -n $[$nlines10/2] ${tmp}/shuffled.tmp \
     > ${dir}/althingi.dev.txt || error 14 $LINENO ${error_array[14]};
tail -n $[$nlines10/2+1] ${tmp}/shuffled.tmp | head -n $[$nlines10/2] \
     > ${dir}/althingi.test.txt || error 14 $LINENO ${error_array[14]};
tail -n +$[$nlines10+1] ${tmp}/shuffled.tmp \
     > ${dir}/althingi.train.txt || error 14 $LINENO ${error_array[14]};

exit 0;

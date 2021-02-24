#!/bin/bash -e

set -o pipefail

ext=

. ./path.sh
. parse_options.sh
. ./local/utils.sh
. ./local/array.sh

if [ $# -ne 3 ]; then
  echo "This script fixes spelling errors in the intermediate parliamentary text transcripts"
  echo "by comparing them to the vocabulary in the final versions."
  echo ""
  echo "Usage: $0 <vocab-in-final> <input-file-wo-ext> <reference-text>" >&2
  echo "e.g.: $0 ${outdir}/words_text_endanlegt.txt ${outdir}/split${nj}/text_exp3_upphaflegt ${outdir}/text_exp3_endanlegt.txt" >&2
  exit 1;
fi

words_all_endanlegt=$1
filepath=$2
reftext=$3

dir=$(dirname $filepath)

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

IFS=$'\n' # Important
for speech in $(cat ${filepath}.${ext})
do
  uttID=$(echo $speech | cut -d" " -f1) || exit 1;
  echo $speech | cut -d" " -f2- | sed 's/[0-9\.,:;?!%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${tmp}/vocab_speech.${ext} || error 14 $LINENO ${error_array[14]}
  
  # Find words that are not in any text_endanlegt speech 
  comm -23 <(sort -u ${tmp}/vocab_speech.${ext}) <(sort -u $words_all_endanlegt) > ${tmp}/vocab_speech_only.${ext} || error 14 $LINENO ${error_array[14]}
  grep $uttID ${reftext} > ${tmp}/text_endanlegt_speech.${ext} || error 14 $LINENO ${error_array[14]};
  cut -d" " -f2- ${tmp}/text_endanlegt_speech.${ext} | sed 's/[0-9\.,:;?!%‰°º]//g' | tr " " "\n" | egrep -v "^\s*$" | sort -u > ${tmp}/vocab_text_endanlegt_speech.${ext} || error 14 $LINENO ${error_array[14]};

  echo $speech > ${tmp}/speech.${ext}

  # Find the closest match in vocab_text_endanlegt_speech.tmp and substitute
  # Commented out the option to fix words where the edit distance was >1.
  # Damerau-Levenshtein considers a single transposition to have distance 1.
  python local/MinEditDist.py ${tmp}/speech.${ext} $dir/text_SpellingFixed.${ext}.txt ${tmp}/vocab_speech_only.${ext} ${tmp}/vocab_text_endanlegt_speech.${ext} &>$dir/log/MinEditDist.log

  ret=$?
  if [ $ret -ne 0 ]; then
    error 1 $LINENO "Error in MinEditDist.py";
  fi
  
done

exit 0;

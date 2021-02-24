#!/bin/bash -e
#
# Copyright: 2015 Robert Kjaran
#
# Compile a zerogram ARPA from the vocabulary of a lang dir
#

. local/utils.sh

if [ $# -ne 2 ]; then
    error "Usage: $0 <lang-dir> <arpa-file>"
fi
dir=$1; shift
arpa=$1; shift

estimate-ngram -order 1 -text <(cat $dir/words.txt | egrep -v "<eps>|<s>|</s>|#" | cut -d' ' -f1) -wl $arpa

exit 0

#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0
# Run from s5 directory

. ./path.sh
. ./local/utils.sh

if [ $# -ne 2 ]; then
  echo "This script creates fst files from Thrax grammar"
  echo "Usage: $0 <thrax-grammar-dir> <output-dir>" >&2
  echo "Eg. $0 local/thraxgrammar $root_text_norm_modeldir/$d" >&2
  exit 1;
fi

indir=$1
outdir=$2
mkdir -p $outdir

for f in $indir/expand.grm $indir/abbreviate.grm; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

# Compile the grammar to expand numbers and abbreviations
# also the one used when selecting which utterances
# to keep for training an expansion language model
thraxmakedep $indir/expand.grm || error 1 "thraxmakedep failed"
make || error 1 "make failed"

# Compile the grammar to abbreviate numbers and abbreviations
# after transcribing text, also the one used to insert periods
# into abbreviations
thraxmakedep $indir/abbreviate.grm || error 1 "thraxmakedep failed"
make || error 1 "make failed"

# Extract the fst from the compiled grammar
# and move the fst to the output dir
farextract --filename_suffix=".fst" $indir/expand.far $indir/abbreviate.far || error 1 "farextract failed"
mv -t $outdir *.fst

exit 0;

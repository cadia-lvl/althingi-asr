#!/bin/bash -e

set -o pipefail

# Creates a base expansion LM training data and model

# Idea from: Sproat, R. (2010). Lightly supervised learning of text normalization: Russian number names.

# Copyright 2016  Reykjavik University (Author: Robert Kjaran)
#           2017  Reykjavik University (Author: Inga Run Helgadottir)
# Apache 2.0

# Usage: local/make_base_expansionLM.sh

stage=-1
order=4
lowercase=false

. ./cmd.sh
. ./path.sh # includes path.conf which sets the $root_* variables e.g.
. parse_options.sh || exit 1;

Leipzig_corpus=$root_leipzig_corpus/isl_sentences_10M.txt
manually_fixed_data=$root_manually_fixed/althingi100_textCS
utf8syms=$root_listdir/utf8.syms
prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
thraxfstdir=$(ls -dt $root_text_norm_modeldir/20* | head -n1)
fstdir=$root_base_text_norm_model

if [ "$lowercase" = false ]; then
  expLMbase=$root_expansionLM_cs_data
  lc=
else
  expLMbase=$root_expansionLM_lc_data
  lc=_lc
fi
mkdir -p $expLMbase/log $fstdir/log

tmp=$(mktemp -d)
cleanup () {
  rm -rf "$tmp"
}
trap cleanup EXIT

for f in $Leipzig_corpus $manually_fixed_data $utf8syms $prondict $thraxfstdir/EXPAND_UTT.fst ; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ $stage -le 0 ]; then
  # Create the training set
  utils/slurm.pl $expLMbase/log/prep_base_expansion_training_subset.log local/prep_expansionLM_training_subset_Leipzig.sh --lowercase $lowercase $Leipzig_corpus $manually_fixed_data $prondict
fi

if [ $stage -le 1 ]; then
  
  echo "Make a word symbol table and map oov words in the Leipzig and Althingi100 text to <unk>"
  # Code from prepare_lang.sh
  cat $expLMbase/wordlist_numbertexts_althingi100.txt | grep -Ev "<num>|<word>|^\s*$" | LC_ALL=C sort | uniq  | awk '
    BEGIN {
      print "<eps> 0";
    }
    {
      if ($1 == "<s>") {
        print "<s> is in the vocabulary!" | "cat 1>&2"
        exit 1;
      }
      if ($1 == "</s>") {
        print "</s> is in the vocabulary!" | "cat 1>&2"
        exit 1;
      }
      printf("%s %d\n", $1, NR);
    }
    END {
      printf("<unk> %d\n", NR+1);
      printf("<num> %d\n", NR+2);
      printf("<word> %d\n", NR+3);
  }' > $fstdir/baseLM_words$lc.txt
  
  # Replace OOVs with <unk>
  zcat $expLMbase/numbertexts_althingi100.txt.gz \
  | utils/sym2int.pl --map-oov "<unk>" -f 2- $fstdir/baseLM_words$lc.txt \
  | utils/int2sym.pl -f 2- $fstdir/baseLM_words$lc.txt | gzip -c > $expLMbase/base_expansionLM_training_texts.txt.gz
  
fi

if [ $stage -le 2 ]; then
  # We need a FST to map from utf8 tokens to words in the words symbol table.
  # f1=word, f2-=utf8_tokens (0x0020 always ends a utf8_token seq)
  utils/slurm.pl \
  $expLMbase/log/words_to_utf8.log \
  awk '$2 != 0 {printf "%s %s \n", $1, $1}' \< $fstdir/baseLM_words$lc.txt \
  \| fststringcompile ark:- ark:- \
  \| fsts-to-transcripts ark:- ark,t:- \
  \| int2sym.pl -f 2- $utf8syms \> $expLMbase/words_to_utf8.txt
  
  utils/slurm.pl --mem 4G \
  $fstdir/log/base_utf8_to_words$lc.log \
  utils/make_lexicon_fst.pl $expLMbase/words_to_utf8.txt \
  \| fstcompile --isymbols=$utf8syms --osymbols=$fstdir/baseLM_words$lc.txt --keep_{i,o}symbols=false \
  \| fstarcsort --sort_type=ilabel \
  \| fstclosure --closure_plus     \
  \| fstdeterminizestar \| fstminimize   \
  \| fstarcsort --sort_type=ilabel \> $fstdir/base_utf8_to_words$lc.fst
  
  
  # EXPAND_UTT is an obligatory rewrite rule that accepts anything as input
  # and expands what can be expanded.
  # Create the fst that works with expand-numbers, using baseLM_words$lc.txt as
  # symbol table. NOTE! I changed map_type from rmweight to arc_sum to fix weight problem
  utils/slurm.pl \
  $fstdir/log/base_expand_to_words$lc.log \
  fstcompose $thraxfstdir/EXPAND_UTT.fst $fstdir/base_utf8_to_words$lc.fst \
  \| fstrmepsilon \| fstmap --map_type=arc_sum \
  \| fstarcsort --sort_type=ilabel \> $fstdir/base_expand_to_words$lc.fst &
  
fi

if [ $stage -le 3 ]; then
  echo "Building ${order}-gram"
  if [ -f $fstdir/base_expansionLM_${order}g.arpa.gz ]; then
    mkdir -p $fstdir/.backup
    mv $fstdir/{,.backup/}base_expansionLM_${order}g.arpa.gz
  fi
  
  # KenLM is superior to every other LM toolkit (https://github.com/kpu/kenlm/).
  # multi-threaded and designed for efficient estimation of giga-LMs
  # It has to be in path.sh
  # NOTE! Why am I getting this error: ERROR: 1-gram discount out of range for adjusted count 2: -0.1530149
  # Fixed using --discount_fallback but I don't like it!!
  lmplz \
  --skip_symbols \
  -o ${order} -S 70% --prune 0 \
  --text $expLMbase/base_expansionLM_training_texts.txt.gz \
  --limit_vocab_file <(cut -d ' ' -f1 $fstdir/baseLM_words$lc.txt | egrep -v '<eps>|<unk>') \
  | gzip -c > $fstdir/base_expansionLM_${order}g.arpa.gz
fi

if [ $stage -le 4 ]; then
  # Get the fst language model. Obtained using the rewritable sentences.
  if [ -f $fstdir/base_expansionLM_${order}g$lc.fst ]; then
    mkdir -p $fstdir/.backup
    mv $fstdir/{,.backup/}base_expansionLM_${order}g$lc.fst
  fi
  
  utils/slurm.pl --mem 12G $fstdir/log/base_expansionLM_${order}g.fst.log \
  arpa2fst "zcat $fstdir/base_expansionLM_${order}g.arpa.gz |" - \
  \| fstprint \
  \| utils/s2eps.pl \
  \| fstcompile --{i,o}symbols=$fstdir/baseLM_words$lc.txt --keep_{i,o}symbols=false \
  \| fstarcsort --sort_type=ilabel \
  \> $fstdir/base_expansionLM_${order}g$lc.fst
  
fi

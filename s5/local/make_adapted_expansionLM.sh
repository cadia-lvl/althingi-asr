#!/bin/bash -e
set -o pipefail
# Idea from: Sproat, R. (2010). Lightly supervised learning of text normalization: Russian number names.

# Copyright 2016  Reykjavik University (Author: Robert Kjaran)
#           2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Usage: local/train_LM_forExpansion.sh [options]

stage=-1
order=4

. ./cmd.sh
. ./path.sh
. parse_options.sh || exit 1;
. ./conf/path.conf

utf8syms=$root_listdir/utf8.syms

if [ $# -ne 4 ]; then
    echo "This script makes an expansion language model by adding the training data we are going to"
    echo "expand to the base data"
    echo ""
    echo "Usage: $0 [options] <text-file> <Leipzig-and-althingi100-base> <outdir>"
    echo "e.g.: $0 --order 4 ~/data/date/cleantext.txt ~/models/text_norm/base ~/data/expansionLM/case_sens ~/data/date"
    echo "Options:"
    echo "    --order         # ngram order (default: 4)"
    exit 1;
fi

textin=$1
fstdir=$2
expLMbase=$3
outdir=$4
mkdir -p $outdir

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

for f in $utf8syms $textin $fstdir/EXPAND_UTT.fst \
$expLMbase/{wordlist_numbertexts_althingi100.txt,numbertexts_althingi100.txt.gz}; do
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ $stage -le 1 ]; then
    
    echo "Make the wordlist and map oov words in the Leipzig text to <unk>"
    
    echo "Add the to-be-expanded text to the LM training text so that no utterances will be rejected"
    head -n1 $textin | cut -d" " -f1 > ${outdir}/first_word.tmp
    if egrep -q "rad[0-9]|[0-9]{10}" ${outdir}/first_word.tmp; then
        # Get the new text vocabulary
        cut -d" " -f2- $textin | tr " " "\n" | sed -r 's/\b[0-9]+[^ ]*/<num>/g' | egrep -v "^\s*$" | sort -u > $outdir/words_input_text.txt
        
        cat <(zcat ${expLMbase}/numbertexts_althingi100.txt.gz) <(cut -d" " -f2- $textin) | gzip -c > $tmp/expansionLM_texts.txt.gz
    else
        tr " " "\n" < $textin | sed -r 's/\b[0-9]+[^ ]*/<num>/g' | egrep -v "^\s*$" | sort -u > $outdir/words_input_text.txt
        
        cat <(zcat ${expLMbase}/numbertexts_althingi100.txt.gz) $textin | gzip -c > $tmp/expansionLM_texts.txt
    fi
    
    # Make a word symbol table. Code from prepare_lang.sh
    cat $expLMbase/wordlist_numbertexts_althingi100.txt $outdir/words_input_text.txt | egrep -v "<num>|<unk>|<word>"| LC_ALL=C sort | uniq  | awk '
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
    }' > $outdir/words.txt
    
    # Replace OOVs with <unk>
    zcat $tmp/expansionLM_texts.txt.gz \
    | utils/sym2int.pl --map-oov "<unk>" -f 2- $outdir/words.txt \
    | utils/int2sym.pl -f 2- $outdir/words.txt | gzip -c > $outdir/expansionLM_training_texts.txt.gz
    
fi

if [ $stage -le 2 ]; then
    # We need a FST to map from utf8 tokens to words in the words symbol table.
    # f1=word, f2-=utf8_tokens (0x0020 always ends a utf8_token seq)
    utils/slurm.pl \
    $outdir/log/words_to_utf8.log \
    awk '$2 != 0 {printf "%s %s \n", $1, $1}' \< $outdir/words.txt \
    \| fststringcompile ark:- ark:- \
    \| fsts-to-transcripts ark:- ark,t:- \
    \| int2sym.pl -f 2- ${utf8syms} \> $outdir/words_to_utf8.txt
    
    utils/slurm.pl --mem 4G \
    $outdir/log/utf8_to_words.log \
    utils/make_lexicon_fst.pl $outdir/words_to_utf8.txt \
    \| fstcompile --isymbols=${utf8syms} --osymbols=$outdir/words.txt --keep_{i,o}symbols=false \
    \| fstarcsort --sort_type=ilabel \
    \| fstclosure --closure_plus     \
    \| fstdeterminizestar \| fstminimize   \
    \| fstarcsort --sort_type=ilabel \> $outdir/utf8_to_words.fst
    
    
    # EXPAND_UTT is an obligatory rewrite rule that accepts anything as input
    # and expands what can be expanded.
    # Create the fst that works with expand-numbers, using words30.txt as
    # symbol table. NOTE! I changed map_type from rmweight to arc_sum to fix weight problem
    utils/slurm.pl \
    $outdir/log/expand_to_words.log \
    fstcompose $fstdir/EXPAND_UTT.fst $outdir/utf8_to_words.fst \
    \| fstrmepsilon \| fstmap --map_type=arc_sum \
    \| fstarcsort --sort_type=ilabel \> $outdir/expand_to_words.fst &
    
fi

if [ $stage -le 3 ]; then
    echo "Building ${order}-gram"
    if [ -f $outdir/expansionLM_${order}g.arpa.gz ]; then
        mkdir -p $outdir/.backup
        mv $outdir/{,.backup/}expansionLM_${order}g.arpa.gz
    fi
    
    # KenLM is superior to every other LM toolkit (https://github.com/kpu/kenlm/).
    # multi-threaded and designed for efficient estimation of giga-LMs
    lmplz \
    --skip_symbols \
    -o ${order} -S 70% --prune 0 0 1 \
    --text $outdir/expansionLM_training_texts.txt.gz \
    --limit_vocab_file <(cut -d " " -f1 $outdir/words.txt | egrep -v "<eps>|<unk>") \
    | gzip -c > $outdir/expansionLM_${order}g.arpa.gz
fi

if [ $stage -le 4 ]; then
    # Get the fst language model. Obtained using the rewritable sentences.
    if [ -f $outdir/expansionLM_${order}g.fst ]; then
        mkdir -p $outdir/.backup
        mv $outdir/{,.backup/}expansionLM_${order}g.fst
    fi
    
    utils/slurm.pl --mem 12G $outdir/log/expansionLM_${order}g.fst.log \
    arpa2fst "zcat $outdir/expansionLM_${order}g.arpa.gz |" - \
    \| fstprint \
    \| utils/s2eps.pl \
    \| fstcompile --{i,o}symbols=$outdir/words.txt --keep_{i,o}symbols=false \
    \| fstarcsort --sort_type=ilabel \
    \> $outdir/expansionLM_${order}g.fst
    
fi

exit 0;

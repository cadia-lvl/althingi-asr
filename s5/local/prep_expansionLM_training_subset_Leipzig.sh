#!/bin/bash -e

set -o pipefail

# This script creates a training set for the expansion LM based on Leipzig data
# and partially manually corrected expanded Alþingi texts
# Creating this base set takes time and the idea is to only run it once

# Copyright 2016  Reykjavik University (Author: Robert Kjaran)
#           2017  Reykjavik University (Author: Inga Run Helgadottir)
# Apache 2.0

# Usage: local/prep_expansionLM_training_subset_Leipzig.sh [options]

nj=60
stage=-1
lowercase=false
corpus=/data/leipzig/isl_sentences_10M.txt

. ./cmd.sh
. ./path.sh # contains path.conf where root_* variables are defined
. parse_options.sh || exit 1;

fstnormdir=$(ls -td $root_text_norm_modeldir/20* | head -n1)
text_norm_lex_dir=$root_thraxgrammar_lex
outdirlc=$root_expansionLM_lc_data

if [ $# -lt 3 ]; then
  echo "The scripts creates a text set to use for the expansion language model,"
  echo "which in turn is used for selecting the most likely expansion of a number"
  echo "or an abbreviation, when multiple ones exist."
  echo ""
  echo "Usage: $0 <Leipzig-corpus-for-Icelandic> <manually-fixed-althingi-text-set>"
  echo "          <pronunciation-dictionary>"
  echo " e.g.: $0 $Leipzig_corpus $root_manually_fixed/althingi100_textCS $prondict"
  exit 1;
fi

corpus=$1
althingitext=$2
prondict=$3

extension="${althingitext##*_}"
if [ $extension = "textLC" ]; then
  lowercase=true
  outdir=$outdirlc
else
  lowercase=false
  outdir=$root_expansionLM_cs_data
fi

intermediate=$outdir/intermediate
intermediatelc=$outdirlc/intermediate
mkdir -p $intermediate $intermediatelc

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

for f in $corpus $fstnormdir/ABBREVIATE_forExpansion.fst $prondict $althingitext \
  $text_norm_lex_dir/{abbr_lexicon.txt,units_lexicon.txt,ordinals_*?_lexicon.txt}; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ -e $outdirlc/wordlist_numbertexts_lc.txt -a -e $outdirlc/numbertexts_Leipzig_lc.txt* ]; then
  echo "The lowercase Leipzig numbertext and wordlist already exists."
  echo "I won't re-create them"
  gzip -d $outdirlc/numbertexts_Leipzig_lc.txt.gz 2>/dev/null
  stage=6
fi

if [ $stage -le 0 ]; then
  
  echo "Convert text file to a Kaldi table (ark)."
  # The archive format is:
  # <key1> <object1> <newline> <key2> <object2> <newline> ...

  # Each text lowercased and given an text_id,
  # which is just the 10-zero padded line number
  awk '{printf("%010d %s\n", NR, tolower($0))}' $corpus \
      > $intermediatelc/texts_LC.txt
fi

if [ $stage -le 1 ]; then
  
  echo "Clean the text a little bit"

  # Rewrite some and remove other punctuations. I couldn't exape
  # the single quote so use a hexadecimal escape

  # 1) Remove punctuations
  # 2) Add space between letters and digits in alphanumeric words
  # 3) Map all numbers to the tag <num>
  # 4) Map to one space between words
  nohup sed -re 's/[^a-yáðéíóúýþæö0-9 ]+/ /g' \
        -e 's/([0-9])([a-záðéíóúýþæö])/\1 \2/g' -e 's/([a-záðéíóúýþæö])([0-9])/\1 \2/g' \
        -e 's/ [0-9]+/ <num>/g' \
        < $intermediatelc/texts_LC.txt \
    | tr -s " " > $intermediatelc/texts_no_puncts.txt
fi

if [ $stage -le 2 ]; then

  echo "Split the text up and compile the lines to linear FSTs"
  
  # We want to process it in parallel. NOTE! One time split_scp.pl complained about $out_scps!
  mkdir -p $intermediatelc/split$nj/
  out_scps=$(for j in `seq 1 $nj`; do printf "$intermediatelc/split%s/texts_no_puncts.%s.txt " $nj $j; done)
  utils/split_scp.pl $intermediatelc/texts_no_puncts.txt $out_scps
  
  # Compile the lines to linear FSTs with utf8 as the token type
  utils/slurm.pl JOB=1:$nj $intermediatelc/log/compile_strings.JOB.log fststringcompile ark:$intermediatelc/split$nj/texts_no_puncts.JOB.txt ark:"| gzip -c > $intermediatelc/texts_fsts.JOB.ark.gz"
fi

if [ $stage -le 3 ]; then	    

  echo "Find out which lines can be rewritten. All other lines are filtered out."
 
  mkdir -p $intermediatelc/abbreviated_fsts
  utils/slurm.pl JOB=1:$nj $intermediatelc/log/abbreviated.JOB.log fsttablecompose --match-side=left ark,s,cs:"gunzip -c $intermediatelc/texts_fsts.JOB.ark.gz |" $fstnormdir/ABBREVIATE_forExpansion.fst ark:- \| fsttablefilter --empty=true ark,s,cs:- ark,scp:$intermediatelc/abbreviated_fsts/abbreviated.JOB.ark,$intermediatelc/abbreviated_fsts/abbreviated.JOB.scp
fi

if [ $stage -le 4 ]; then

  echo "Select the lines in text that are rewriteable, based on key."
  
  IFS=$' \t\n'
  sub_nnrewrites=$(for j in `seq 1 $nj`; do printf "$intermediatelc/abbreviated_fsts/abbreviated.%s.scp " $j; done)

  cat $sub_nnrewrites | awk '{print $1}' | sort -k1 | join - $intermediatelc/texts_no_puncts.txt | cut -d' ' -f2- > $outdirlc/numbertexts_Leipzig_lc.txt
  # Add also one line containing the token <word>, to make it work with expand_small.sh,
  # otherwise, speeches that contain words that are not seen in numbertexts won't be expanded
  # I also need punctuations in there
  # I insert it a few times, so that even though I prune the expansion fst this will stay in
  printf 'þingmaðurinn háttvirti sagði að áform um <word> , væru ekkert annað en hneisa ! með leyfi forseta : á þingskjali þrjátíu og fjögur ; annarri málsgrein . hvað segirðu ? Norður - Kórea og / eða Suður – Kórea\n%.0s' {1..5} >> $outdirlc/numbertexts_Leipzig_lc.txt
fi

if [ $stage -le 5 ]; then
  
  echo "Store a list of words appearing both in the Leipzig subset and the lowercased pronunciation dictionary"

  nohup tr ' ' '\n' < $outdirlc/numbertexts_Leipzig_lc.txt \
    | egrep -v '^\s*$' > $tmp/words \
    && sort --parallel=8 $tmp/words \
    | uniq > $intermediatelc/words_numbertexts_lc.txt
  
  # We select a subset of the vocabulary that also exists in our pronunciation
  # dictionary. Since a lot of the words in the Leipzig corpora are not real words
  comm -12 <(sort -u $intermediatelc/words_numbertexts_lc.txt) <(cut -f1 $prondict | sed -r 's:.*:\L&:' | sort -u) | sort -u > $outdirlc/wordlist_numbertexts_lc.txt
  
fi

if [ $stage -le 6 -a $lowercase = false ]; then

  echo "Make the text approximately case sensitive"
  # Can't fix the casing of words that appear in both cases and we don't have rules for"
  utils/slurm.pl $outdir/log/fix_casing.log local/fix_casing_expansionLM.sh $prondict $outdirlc/wordlist_numbertexts_lc.txt $outdirlc/numbertexts_Leipzig_lc.txt $outdir/numbertexts_Leipzig_cs.txt

fi

if [ $stage -le 7 ]; then
  
  echo "Make a combined list of words from the Leipzig subset and the expanded Althingi subset"
  # I want to map other words to <unk> since they don't appear in these training texts.

  if [ $lowercase = true ]; then
    wordlist=$outdirlc/wordlist_numbertexts_lc.txt
  else
    echo "Store a list of words appearing both in the Leipzig subset and the pronunciation dictionary"
    # Sort the vocabulary based on frequency count
    nohup tr ' ' '\n' < $outdir/numbertexts_Leipzig_cs.txt \
      | egrep -v '^\s*$' > $tmp/words \
      && sort --parallel=8 $tmp/words \
      | uniq > $intermediate/words_numbertexts_cs.txt

    # We select a subset of the vocabulary that also exists in our pronunciation
    # dictionary. Since a lot of the words in the Leipzig corpora are not real words
    comm -12 <(sort -u $intermediate/words_numbertexts_cs.txt) <(cut -f1 $prondict | sort -u) | sort -u > $outdir/wordlist_numbertexts_cs.txt
    
    wordlist=$outdir/wordlist_numbertexts_cs.txt
  fi
  
  # Since the expanded form of some abbreviations did not appear often enough,
  # or at all in the Leipzig texts.
  comm -23 <(cut -d" " -f2- $althingitext | tr " " "\n" | egrep -v "^\s*$" | sort -u) <(sort $wordlist) > $intermediate/vocab_alth_only.txt
  
  cat $wordlist $intermediate/vocab_alth_only.txt > $outdir/wordlist_numbertexts_althingi100.txt

  # Here I add the expanded abbreviations that were filtered out
  abbr_expanded=$(cat $text_norm_lex_dir/abbr_lexicon.txt | cut -f2- | tr " " "\n" | sort -u)
  for abbr in $abbr_expanded
  do
    grep -q "\b${abbr}\b" $outdir/wordlist_numbertexts_althingi100.txt || echo -e $abbr >> $outdir/wordlist_numbertexts_althingi100.txt
  done

  # Add expanded numbers to the list, the token <word> and punctuations
  cut -f2 $text_norm_lex_dir/ordinals_*?_lexicon.txt >> $outdir/wordlist_numbertexts_althingi100.txt
  cut -f2 $text_norm_lex_dir/units_lexicon.txt >> $outdir/wordlist_numbertexts_althingi100.txt
  echo -e "\.\n,\n\?\n\!\n:\n;\n\-\n–\n\/\n<word>" \
       > $tmp/puncts && sed -r 's:\\::g' $tmp/puncts | sort -u \
       >> $outdir/wordlist_numbertexts_althingi100.txt
fi


if [ $stage -le 8 ]; then

  echo "Add the expanded and partly manually corrected 100 hours of Althingi speeches"

  if [ $lowertext = true ]; then
    cat $outdirlc/numbertexts_Leipzig_lc.txt <(cut -d" " -f2- $althingitext) | sed -r 's: +: :g' | gzip > $outdir/numbertexts_althingi100.txt.gz
  else
    cat $outdir/numbertexts_Leipzig_cs.txt <(cut -d" " -f2- $althingitext) | sed -r 's: +: :g' | gzip > $outdir/numbertexts_althingi100.txt.gz
  fi

  # Compress the Leipzig files
  gzip $outdirlc/numbertexts_Leipzig_lc.txt
  gzip $outdir/numbertexts_Leipzig_cs.txt

fi

# Remove big intermediate files
rm -r $intermediatelc $intermediate

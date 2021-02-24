#!/bin/bash -e

set -o pipefail

lex_ext=txt

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -lt 5 ]; then
  echo "I can't help but lowercase the Leipzig corpora when processing it and this script"
  echo "is supposed to restore the capitalization of the text."
  echo ""
  echo "Usage: $0 <list-dir> <pronunciation-dictionary> <Leipzig-wordlist-lowercased> "
  echo "          <Leipzig-text-set> <output-text-file>"
  echo " e.g.: $0 $capitalization_listdir $prondict $outdirlc/wordlist_numbertexts_lc.txt "
  echo "          $outdirlc/numbertexts_Leipzig_lc.txt $outdir/numbertexts_Leipzig_cs.txt"
  exit 1;
fi

wordlist=$3
textin=$4
textout=$5

dir=$(dirname $textout)
intermediate=$dir/intermediate
mkdir -p $intermediate

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
acro_as_words=$(ls -t $root_capitalization/acronyms_as_words.* | head -n1)
named_entities=$(ls -t $root_capitalization/named_entities.* | head -n1)
cut -f2 $root_thraxgrammar_lex/ambiguous_personal_names.$lex_ext > $tmp/ambiguous_names

for f in $acro_as_words $tmp/ambiguous_names $named_entities $prondict $wordlist $textin; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done  
  
echo "Make the text approximately case sensitive"
  # can't fix the casing of words that appear in both cases and we don't have rules for"

  # Capitalize acronyms which are pronounced as words
  # Make the regex pattern
  tr "\n" "|" < $acro_as_words | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > $intermediate/acronyms_as_words_LCpattern.tmp
  srun sed -r "s:(\b$(cat $intermediate/acronyms_as_words_LCpattern.tmp)\b):\U\1:g" $textin > $intermediate/texts_acroCS.txt

  # Find the vocabulary that appears in both cases in text
  cut -f1 $prondict | sort -u | sed -re "s:.+:\l&:" | sort | uniq -cd > $intermediate/vocab_twoCases.tmp

  # Find words that only appear in upper case
  comm -13 <(awk '{print $2 }' $intermediate/vocab_twoCases.tmp | sed -r 's:.*:\u&:') <(cut -f1 $prondict | egrep "^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]" | sort -u) > $intermediate/propernouns.txt

  # Find which of these words appear in the Leipzig subset and should be uppercased
  comm -12 <(sort $wordlist) <(sed -r 's:.*:\L&:' $intermediate/propernouns.txt) > $intermediate/to_uppercase.tmp

  tr "\n" "|" < $intermediate/to_uppercase.tmp  | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > $intermediate/to_uppercase_pattern.tmp

  srun sed -r 's:(\b'$(cat $intermediate/to_uppercase_pattern.tmp)'\b):\u\1:g' $intermediate/texts_acroCS.txt > $intermediate/texts_CaseSens.tmp

  # Make a regex pattern from my ambiguous proper names
  tr "\n" "|" < $tmp/ambiguous_names | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > $intermediate/ambiguous_personal_names_pattern.tmp

  # Switch bleyja to bleia, fiskistofn to fiskstofn, innistæða to innstæða, capitalize companies when followed by ohf, ehf or hf, capitalize ambiguous propernames when there is a middle name
  sed -re 's:\bbleyj(a|u|an|una|unni|unnar|ur|um|urnar|unum|anna)\b:blei\1:g' -e 's:fiskistofn:fiskstofn:g' -e 's:innistæð:innstæð:g' \
      -e 's:\bmc ?([a-z]+):Mc\u\1:gI' -e 's:\byou ?tube:YouTube:gI' \
      -e 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
      -e 's:\b([^ ]+) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
      -e 's:(\b'$(cat $intermediate/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
      < $intermediate/texts_CaseSens.tmp > $intermediate/texts_CaseSens_fix.tmp

  # Now I need to make a case insensitive matching of these patterns, but replace it with the correct casing.
  # Create a sed command file
  cat $named_entities $named_entities | sort | awk 'ORS=NR%2?":":"\n"' | sed -re 's/^.*/s:\\b&/' -e 's/$/:gI/g' > $intermediate/ner_sed_pattern.tmp

  # Fix the casing of known named entities
  /bin/sed -f $intermediate/ner_sed_pattern.tmp $intermediate/texts_CaseSens_fix.tmp > $textout

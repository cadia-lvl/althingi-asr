#!/bin/bash

# Calculate the edit distance between the ASR output and the manually transcribed text.
# I only compair the two texts, no scoring for different LM weights or word insertion penalty.

# Config
remove_comments=true
abbreviate=false
lowercase=false
ignore_punctuations=false
abbr_extra=false
suffix=
lex_ext=txt
bundle=latest

echo "$0 $@"  # Print the command line for logging
. ./path.sh
. ./utils/parse_options.sh
. ./conf/path.conf

if [ $# -ne 3 ]; then
    echo "Usage: $0 [options] <textfile1> <textfile2> <output-dir>"
    echo "e.g.:  local/recognize/estimate_wordEditDistance1b.sh \\"
    echo "  recognize/notendaprof2/Lestur/rad20180219T150803.xml \\"
    echo "  recognize/notendaprof2/ASR/rad20180219T150803.txt recognize/notendaprof2/edit_dist/rad20180219T150803_A_B"
    exit 1;
fi

# If one of the texts is an ASR transcription and one is either a manual transcription
# or an edited ASR text, then text2 should be the unedited ASR transcription
textfile1=$1
textfile2=$2
dir=$3
mkdir -p $dir

base=$(basename "$textfile1")
base="${base%.*}"

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

utf8syms=$bundle/utf8.syms
normdir=$bundle/text_norm
cut -f1 $root_thraxgrammar_lex/abbr_lexicon.$lex_ext | tr " " "\n" | sort -u > $tmp/abbr_list




# Make the abbreviation regex pattern used in punctuation cleaning and correcting capitalization
cat $tmp/abbr_list <(sed -r 's:.*:\u&:' $tmp/abbr_list) \
  | sort -u | tr "\n" "|" | sed '$s/|$//' \
  | perl -pe "s:\|:\\\b\|\\\b:g" \
  > $tmp/abbr_pattern.tmp

# If the text files are xml files I first need to extract the text
n=0
for file in $textfile1 $textfile2; do
  n=$[$n+1]
  # 1) Remove newlines, xml tags and carriage return
  # 2) Remove quotation marks and ellipsis (…), rewrite weird invisible dashes and underscore to a space and add space around the other ones
  # 3) Remove the period after abbreviated middle names
  # 4) For a few abbreviations that often stand at the end of sentences, add a space between the abbr and the period
  # 5) Remove periods inside abbreviations
  # 6) Move EOS punctuation away from the previous word and lowercase what comes after, if the previous word is a number or it is the last word.
  # 7) Move INS punctuations away from the previous word
  # 8) Remove the abbreviation periods
  # 9) Move EOS punctuation away from the previous word and lowercase what comes after
  # 10) Insert a utt ID att the beginning and change spaces to one
  tr "\n" " " < $file | sed -re 's:</mgr></ræðutexti></ræða> <ræðutexti><mgr>: :g' -e 's:(.*)?<ræðutexti>(.*)</ræðutexti>(.*):\2:' \
    -e 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' -e `echo "s/\r//"` \
    -e 's: *<[^<>]*?>: :g' \
    -e 's:[„“…]::g' -e 's:­| |_: :g' -e 's:([—-]): \1 :g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
    -e 's: (gr|umr|sl|millj|nk|mgr)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \3:g' \
    -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e 's:([0-9,.]{3,})([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \3:g' -e 's:([0-9]%)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) :\1 \2 :g' -e 's:([.:?!]+)\s*$: \1 :g' \
    -e 's:([,;]) : \1 :g' \
    -e 's:(\b'$(cat $tmp/abbr_pattern.tmp)')\.:\1:g' \
    -e 's:([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2:g' \
    -e 's:(.*):1 \1:' -e 's: +: :g' \
    > $dir/text$n.tmp
  if [ $remove_comments = true ]; then
    # Remove both comments in parentheses and brackets
    sed -i -re 's:\([^()]*?\): :g' -e 's:\[[^]]*?\]: :g' -e 's: +: :g' $dir/text$n.tmp
  fi
done

if [ $abbreviate = true ]; then
  # Abbreviate to hv., hæstv. and þm. and expand þ.e.
  # Insert missing abbreviation periods into the manual transcript
  for f in $dir/text1.tmp $dir/text2.tmp; do
    sed -i -re 's:([Hh])áttv[^ ]+:\1v.:g' \
      -e 's:þingm[^ ]+:þm.:g' \
      -e 's:([Hh]æstv)[^ ]+:\1.:g' \
      -e 's:þ\.?e\.? :það er :g' \
      -e 's:([Hh]v|þm|[Hh]æstv) :\1. :g' \
      -e 's:og svo framvegis:o.s.frv.:g' \
      -e 's:([0-9]) krón[^ ]+:\1 kr.:g' \
      -e 's:(millj[^ ]+) króna:\1 kr.:g' $f
  done
  if [ $abbr_extra = true ]; then
    # Try to get rid of inconsistencies in denormalization in human transcripts
    d=$(basename $(dirname $textfile1))
    if [ "$d" = "Lestur_clean" ]; then
      fststringcompile ark:$dir/text1.tmp ark:- \
	| fsttablecompose --match-side=left ark,t:- $normdir/ABBREVIATE.fst ark:- \
	| fsts-to-transcripts ark:- ark,t:- \
	| int2sym.pl -f 2- ${utf8syms} | cut -d" " -f2- \
	| sed -re 's: ::g' -e 's:0x0020: :g' \
	| tr "\n" " " | sed -re 's:.*:1 &:' -e "s/[[:space:]]+/ /g" \
	> $dir/tmp && mv $dir/tmp $dir/text1.tmp
    fi
  fi
fi

# Remove punctuations if I want a score on just the speech transcription
if [ $ignore_punctuations = true ]; then
  #suffix=_noPuncts
  for f in $dir/text1.tmp $dir/text2.tmp; do
    sed -i -re 's:([.?!:]) „?([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
      -e 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9 ]//g' \
      -e 's: +: :g' $f
  done
fi

if [ $lowercase = true ]; then
  for f in $dir/text1.tmp $dir/text2.tmp; do
    sed -i -r 's:.*:\L&:g' $f
  done
fi


# Get the word count
file1path=$(dirname "$textfile1")
dir1="${file1path##*/}"
file2path=$(dirname "$textfile2")
dir2="${file2path##*/}"
if [ $dir1 = "Lestur" -a $dir2 = "ASR" ]; then
  wc -w $dir/text1.tmp > $dir/wc_A
  wc -w $dir/text2.tmp > $dir/wc_B
elif [ $dir1 = "Text_D" -a $dir2 = "ASR" ]; then
  wc -w $dir/text1.tmp > $dir/wc_D
  wc -w $dir/text2.tmp > $dir/wc_B
else
  wc -w $dir/text1.tmp > $dir/wc_ref
fi

# Align the two texts
align-text --special-symbol="'***'" ark:$dir/text1.tmp ark:$dir/text2.tmp ark,t:$dir/${base}_aligned.txt &>/dev/null

# Remove the text spoken by the speaker of the house
i=2
refword=$(cut -d" " -f$i $dir/${base}_aligned.txt)
while [ "$refword" = "'***'" ]; do
  i=$[$i+3]
  refword=$(cut -d" " -f$i $dir/${base}_aligned.txt)
done
idx1=$[($i-2)/3+2]
cut -d" " -f1,$idx1- $dir/text2.tmp > $dir/${base}_trimmed.tmp
n_trimmed=$[$(wc -w $dir/${base}_trimmed.tmp | cut -d" " -f1)]

n_ali=$[$(wc -w $dir/${base}_aligned.txt | cut -d" " -f1)-1]
j=$n_ali
refword=$(cut -d" " -f$j $dir/${base}_aligned.txt)
while [ "$refword" = "'***'" ]; do
  j=$[$j-3]
  refword=$(cut -d" " -f$j $dir/${base}_aligned.txt)
done
#idx2=$[($j-2)/3+2+1-$idx1]
idx2=$[$n_trimmed-$[($n_ali-$j)/3]]
cut -d" " -f1-$idx2 $dir/${base}_trimmed.tmp > $dir/${base}_trimmed.txt
rm $dir/${base}_trimmed.tmp

# Get a percentage value over the edit distance
cat $dir/${base}_trimmed.txt | \
  compute-wer --text --mode=present \
    ark:$dir/text1.tmp ark,p:- >& $dir/dist_$base || exit 1;

# Get a view of the alignment between the texts, plus values of
# correct words, substituions, insertions and deletions
cat $dir/${base}_trimmed.txt | \
  align-text --special-symbol="'***'" ark:$dir/text1.tmp ark:- ark,t:- |  \
  utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" > $dir/per_utt_$base || exit 1;

# Get statistics over correct words, substituions, insertions and deletions.
# F.ex. how often "virðulegi" is switched out for "virðulegur" and so on. 
cat $dir/per_utt_$base | \
  utils/scoring/wer_ops_details.pl --special-symbol "'***'" | \
  sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 > $dir/ops_$base || exit 1;

rm $dir/text{1,2}.tmp

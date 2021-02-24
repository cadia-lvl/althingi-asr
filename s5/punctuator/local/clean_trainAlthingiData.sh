#!/bin/bash -eu

set -o pipefail

# 2016 Inga Rún
# Clean the 2005-2015 althingi texts for use in a punctuation restoration model

if [ $# -ne 2 ]; then
    echo "Usage: $0 <texts-to-use-in-LM> <output-clean-texts>" >&2
    echo "Eg. $0 data/all/text_orig_endanlegt.txt ~/data/althingi/postprocessing/texts05-15_clean_for_punct_restoring.txt" >&2
    exit 1;
fi

corpus=$1
out=$2
dir=$(dirname $out)
#prondir=~/data/althingi/pronDict_LM

# tmp=$(mktemp -d)
# cleanup () {
#     rm -rf "$tmp"
# }
# trap cleanup EXIT

# In the following I separate the numbers on "|":
# 1) Remove comments on the form "<!--...-->"
# 2-4) Remove comments like "<truflun>Kliður í salnum.</truflun>"
# 5) Remove the remaining tags
# 6) Remove comments in parentheses
# 7) Remove the uttIDs remove leading spaces and reduce spaces to one between words
sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>|<[^>]*?>: :g' \
    -e 's:\([^/()<>]*?\)+: :g' < ${corpus} \
    | cut -d" " -f2- | sed -re 's/^[ \t]*//' -e 's/[[:space:]]+/ /g'> ${dir}/noXML.tmp

# echo "Remove some punctuations and rewrite roman numerals to numbers"
sed -re 's/[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;\/%‰°º&—–²³¼¾½ _)(-]+//g' -e 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' <${dir}/noXML.tmp > ${dir}/roman.tmp
python3 -c "
import re
import sys
sys.path.insert(0,'local')
import roman
text = open('${dir}/roman.tmp', 'r')
text_out = open('${dir}/noRoman.tmp', 'w')
for line in text:
    match_list = re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', line, flags=0)
    match_list = [elem for elem in match_list if len(elem)>0]
    match_list = list(set(match_list))
    match_list.sort(key=len, reverse=True) # Otherwise it will substitute parts of roman numerals
    line = line.split()
    tmpline=[]
    for match in match_list:
        for word in line:
            number = [re.sub(match,str(roman.fromRoman(match)),word) for elem in re.findall(r'\b(X{0,3}IX|X{0,3}IV|X{0,3}V?I{0,3})\.?,?\b', word) if len(elem)>0]
            if len(number)>0:
                tmpline.extend(number)
            else:
                tmpline.append(word)
        line = tmpline
        tmpline=[]
    print(' '.join(line), file=text_out)

text.close()
text_out.close()
"


echo "Rewrite and remove punctuations that I'm not trying to learn how to restore"

# 1) Remove comments in parentheses and brackets and expand "&"
# 2) Remove punctuations which is safe to remove
# 3) Fix errors like: "bla .Bla" and add missing space between sentences: "bla.Bla"
# 4) Remove "ja" from numbers written like "22ja" and rewrite [ck]?m[23] to [ck]?m[²³]
# 5) Fix spelling errors like "be4stu" and "o0g"
# 6) Remove periods after abbreviated middle names
# 7) In an itemized list, lowercase what comes after the numbering
# 8) For a few abbreviations that often stand at the end of sentences, add a space between the abbr and the period
# 9) Remove periods inside abbreviations
# 10) Move EOS punctuation away from the previous word and lowercase what comes after, if the previous word is a number or it is the last word.
# 11) Move INS punctuations away from the previous word
# 12) Switch hyphen out for space
# 13) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
# 14) Fix spacing around % and degrees celsius
# 15) Remove some dashes (not the kind that is between numbers) and periods at the beginning of lines
# 16-17) Change spaces to one between words, remove empty lines and write    
sed -re 's:\([^/(]*?\): :g' -e 's:\[[^]]*?\]: :g' -e 's:&amp;: og :g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: ,+| \.+|,\.| |__+: :g' \
    -e 's: \.([^\.]):. \1:g' -e 's:([^ ])\.([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1. \2:g' \
    -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: kV : kw :g' -e 's:Wst:\L&:g' \
    -e 's: ([a-záðéíóúýþæö]+)[0-9]([a-záðéíóúýþæö]+): \1\2:g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
    -e 's: ([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \L\2:g' \
    -e 's: (gr|umr|sl|millj|nk|mgr)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
    -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e 's:([0-9,.]{3,})([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) :\1 \2 :g' -e 's:([.:?!]+)\s*$: \1 :g' \
    -e 's:([,;]) : \1 :g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
    -e 's:\b([0-9]+)([^0-9 ,.–/:])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+\.?)-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
    -e 's: +([%‰–°º]):\1:g' -e 's:([°º]) c :\1c :g' -e 's:–([^0-9]): \1:g' -e 's: 0([0-9]): 0 \1:g' \
    -e 's:—|­| |-|_: :g' -e 's:^\. *::g' \
    -e 's/[[:space:]]+/ /g' ${dir}/noRoman.tmp \
    | egrep -v "\(|\)" | egrep -v "^\s*$"  > ${dir}/noPunct.tmp

#     -e 's:\.([a-záðéíóúýþæö]):\1:g' \
#-e 's:\b(þm|hv|hæstv|flm|frsm|hrl|Norðaust|Norðvest|Reykv\. n|Reykv\. s|Suðurk|Suðvest|varaform|dr|e\.t\.v|m\.a\.s|sbr|skv|þ\.e)\.:\1:g' \
#-e 's:([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([0-9,.]{3,})([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{3,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) :\1 \2 :g' -e 's:([.:?!]+)\s*$: \1 :g' \
    # 306 gr.
    # 294 umr.
    # 207 sl.
    #  95 millj.
    #  84 nk.
    #  62 mgr.
    
echo "Remove periods after abbreviations"
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/abbr_lexicon.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u | egrep -v "\b[ck]?m[^a-záðéíóúýþæö]*\b|\b[km]?g\b" > ${dir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/oldspeech_abbr.txt | tr " " "\n" | egrep -v "^\s*$|form|\btil\b" | sed -r 's:\.::' | sort -u >> ${dir}/abbr_lex.tmp
cut -f1 ~/kaldi/egs/althingi/s5/text_norm/lex/simple_abbr.txt | tr " " "\n" | egrep -v "^\s*$" | sort -u >> ${dir}/abbr_lex.tmp
# The abbreviaton could stand at the beginning of a sentence
cat ${dir}/abbr_lex.tmp <(sed -r 's:.*:\u&:' ${dir}/abbr_lex.tmp) | sort -u > ${dir}/abbr_lex_CS.tmp
# Make the regex pattern
sort -u ${dir}/abbr_lex_CS.tmp | tr "\n" "|" | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" > ${dir}/abbr_lex_pattern.txt

sed -r "s:(\b$(cat ${dir}/abbr_lex_pattern.txt))\.:\1:g" ${dir}/noPunct.tmp > ${dir}/noAbbrPeriods.tmp

echo "Lowercase BOS"
sed -re 's:([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' -e 's:^.*:\l&:' ${dir}/noAbbrPeriods.tmp > $out

# echo "Capitalize words in the Althingi texts, that are capitalized in the pron dict"
# comm -12 <(sed -r 's:.*:\L&:' ${prondir}/CaseSensitive_pron_dict_propernouns.txt | sort) <(tr " " "\n" < ${dir}/noAbbrPeriods.tmp | sed -re 's/[^a-záðéíóúýþæö]+//g'| egrep -v "^\s*$" | sort -u) > ${dir}/propernouns_althingi_texts.txt
# # Make the regex pattern
# tr "\n" "|" < ${dir}/propernouns_althingi_texts.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > ${dir}/propernouns_althingi_texts_pattern.tmp

# # Capitalize
# srun sed -r "s:(\b$(cat ${dir}/propernouns_althingi_texts_pattern.tmp)\b):\u\1:g" ${dir}/noAbbrPeriods.tmp > ${dir}/Cap1.tmp

# # Capitalize acronyms which are pronounced as words
# # Make the regex pattern
# tr "\n" "|" < text_norm/acronyms_as_words.txt | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" | sed 's:.*:\L&:' > text_norm/acronyms_as_words_pattern.tmp

# # Capitalize 
# srun sed -r 's:(\b'$(cat text_norm/acronyms_as_words_pattern.tmp)'\b):\U\1:g' ${dir}/Cap1.tmp > ${out}


exit 0

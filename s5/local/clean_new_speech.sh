#!/bin/bash -e

set -o pipefail

# This script cleans up text, which can later be processed further to be used in AMs, LMs or punctuation models.

stage=-1
lex_ext=txt

. ./path.sh
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

if [ $# != 4 ]; then
  echo "Usage: local/clean_new_speech.sh [options] <input-text> <text-out> <punctuation-text-out> <new-vocab>"
  echo "a --stage option can be given to not run the whole script"
  exit 1;
fi

textin=$1; shift 
textout=$1; shift
punct_textout=$1; shift
new_vocab=$1; shift
outdir=$(dirname $textout)
intermediate=$outdir/intermediate
mkdir -p $outdir/{intermediate,log}

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

prondict=$(ls -t $root_lexicon/prondict.* | head -n1) 
bad_words=$(ls -t $root_listdir/discouraged_words.* | head -n1)
cut -f1 $root_thraxgrammar_lex/abbr_lexicon.$lex_ext | tr " " "\n" | sort -u > $tmp/abbr_list
cut -f2 $root_thraxgrammar_lex/acro_denormalize.$lex_ext > $tmp/abbr_acro_as_letters
cut -f2 $root_thraxgrammar_lex/ambiguous_personal_names.$lex_ext > $tmp/ambiguous_names

for f in $textin $prondict $bad_words $tmp/abbr_list $tmp/abbr_acro_as_letters $tmp/ambiguous_names; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

# Quit if the text is missing
if egrep -q 'rad[0-9][^ ]+ *$' $textin ; then
  echo "The XML for $(basename $(dirname $textin)) is empty"
  exit 1
fi

# NOTE! We have environment problems. Quick fix is:
export LANG=en_US.UTF-8

# Make a regex pattern of all abbreviations, upper and lower case.
cat $tmp/abbr_list <(sed -r 's:.*:\u&:' $tmp/abbr_list) \
  | sort -u | tr "\n" "|" | sed '$s/|$//' \
  | perl -pe "s:\|:\\\b\|\\\b:g" \
  > $tmp/abbr_pattern.tmp || error 1 $LINENO "Failed creating pattern of abbreviations";
 
if [ $stage -le 1 ]; then
  echo "Rewrite roman numerals"
  sed -i -r 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' $textin
  python3 -c "
import re,sys
sys.path.insert(0,'local')
import roman
text = open('$textin', 'r')
text_out = open('${intermediate}/text_noRoman.txt', 'w')
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
" || error 1 $LINENO "Error while rewriting roman numerals";
  
fi

if [ $stage -le 2 ]; then

  echo "Rewrite and remove punctuations"
  # 1) Remove comments
  # 2) Rewrite fractions
  # 3) Rewrite law numbers
  # 4) Rewrite time,
  # 5) Change "&amp;" to "og"
  # 6) Remove punctuations which is safe to remove
  # 7) Remove commas used as quotation marks, remove or change "..." -> "." and "??+" -> "?"
  # 8) Deal with double punctuation after words/numbers
  # 9) Remove "ja" from numbers written like "22ja" and fix some incorrectly written units (in case manually written),
  # 10) Fix spelling errors like "be4stu" and "o0g",
  # 11) Rewrite website names,
  # 12) In an itemized list, lowercase what comes after the numbering.
  # 13) Rewrite en dash (x96), regular dash and "tilstr(ik)" to " til ", if sandwitched between words or numbers,
  # 14-15) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
  # 16) Rewrite vulgar fractions
  # 17) Add space before "," when not followed by a number and before ";"
  # 18) Remove the period in abbreviated middle names
  # 19) For measurement units and a few abbreviations that often stand at the end of sentences, add space before the period
  # 20) Remove periods inside abbreviation
  # 21) Move EOS punctuation away from the word and lowercase the next word, if the previous word is a number or it is the last word.
  # 22) Remove the abbreviation periods
  # 23) Move remaining EOS punctuation away from the word and lowercase next word
  # 24) Lowercase the first word in a speech
  # 25) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
  # 26) Switch dashes (exept in utt filenames) and remaining slashes out for space
  # 27) Rewrite thousands and millions, f.ex. 3.500 to 3500,
  # 28) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
  # 29) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
  # 30) Remove punctuation attached to the word behind
  # 31) Fix spacing around % and degrees celsius and add space in a number starting with a zero
  # 32) Fix if the first letter in an acronym has been lowercased.
  # 33) Remove punctuations that we don't want to learn, map remaining weird words to <unk> and fix spacing
  sed -re 's:\([^/()<>]*?\)+: :g' -e 's:\[[^]]*?\]: :g' \
      -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
      -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
      -e 's/([0-9]):([0-9][0-9])/\1 \2/g' \
      -e 's/&amp;/ og /g' \
      -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |__+: :g' \
      -e 's: ,,: :g' -e 's:\.\.+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):. \1:g' -e 's:\.\.+::g' -e 's:([^a-záðéíóúýþæö ]) ?\?\?+:\1:g' -e 's:\?\?+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):? \1:g' -e 's:\?\?+::g' \
      -e 's:\b([^0-9 .,:;?!]+)([.,:;?!]+)([.,:;?!]):\1 \3 :g' -e 's:\b([0-9]+[.,:;?!])([.,:;?!]):\1 \2 :g' -e 's:\b(,[0-9]+)([.,:;?!]):\1 \2 :g' \
      -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: ([kgmt])[wV] : \1W :g' -e 's:Wst:\L&:g' \
      -e 's:\b([a-záðéíóúýþæö]+)[0-9]([a-záðéíóúýþæö]+):\1\2:g' \
      -e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
      -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
      -e 's:([^ ])[–-]([^ 0-9]):\1 \2:g' -e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9]\.?)tilstr[^ 0-9]*?\.?([0-9]):\1 til \2:g' -e 's:([0-9\.%])-+([0-9]):\1 til \2:g' \
      -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
      < ${intermediate}/text_noRoman.txt \
    | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
    | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
          -e 's:([,;])([^0-9]|\s*$): \1 \2:g' -e 's:([^0-9]),:\1 ,:g' \
          -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
          -e 's:[ /]([ck]?m[²³]?|[km]g|[kmgt]?w|gr|umr|sl|millj|nk|mgr|kr|osfrv)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
          -e 's:\.([a-záðéíóúýþæö]):\1:g' \
          -e 's:([0-9,.]{3,})([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) *:\1 \2 :g' -e 's:([.:?!]+)\s*$: \1:g' \
          -e "s:(\b$(cat $tmp/abbr_pattern.tmp))\.:\1:g" \
          -e 's:([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([^0-9])([.:?!]+)([0-9]):\1 \2 \3:g' -e 's:([^0-9])([.:?!]+):\1 \2:g' \
          -e 's:(^[^ ]+) ([^ ]+):\1 \l\2:' \
          -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
          -e 's:—|–|/|tilstr[^ 0-9]*?\.?: :g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
         -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
         -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
         -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
         -e 's: ([.,:;?!])([^ ]): \1 \2:g' \
         -e 's: *%:% :g' -e 's:([°º]) c :°c :g' -e 's: 0([0-9]): 0 \1:g' \
         -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ][^a-záðéíóúýþæö]):\u\1:g' \
         -e 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9\.,?!:; %‰°º²³]+//g' -e 's/ [^ ]*[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+[0-9]+[^ ]*/ <unk>/g' -e 's: [0-9]{10,}: <unk>:g' -e 's: 0[^ ]+: <unk>:g' -e 's/ +/ /g' \
         > ${intermediate}/text_noPuncts.txt || error 13 $LINENO ${error_array[13]};

fi

if [ $stage -le 3 ]; then
  
  echo "Expand 'hv.', 'hæstv.' and 'þm.' in certain circumstances"
  # Use Anna's code to expand hv, hæstv and þm, where there is no ambiguity about the expanded form.
  python3 local/althingi_replace_plain_text.py \
    ${intermediate}/text_noPuncts.txt \
    ${intermediate}/text_exp1.txt
  # Check the return status
  [ $? -ne 0 ] && error 1 $LINENO "Error in althingi_replace_plain_text.py";

  # I don't want to expand acronyms pronounced as letters in the punctuation training text
  echo "make a special text version for the punctuation training texts"
  cp ${intermediate}/text_exp1.txt ${intermediate}/text_exp1_forPunct.txt || error 14 $LINENO ${error_array[14]};

  # Add spaces into acronyms pronounced as letters
  if egrep -q "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" ${intermediate}/text_exp1.txt ; then  
    egrep -o "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" \
      < ${intermediate}/text_exp1.txt \
      > $tmp/acro.tmp || error 14 $LINENO ${error_array[14]};

    if egrep -q "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" $tmp/acro.tmp; then
      egrep "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" \
            < $tmp/acro.tmp > $tmp/asletters.tmp || error 14 $LINENO ${error_array[14]};
      
      cat $tmp/asletters.tmp $tmp/abbr_acro_as_letters \
	| sort -u > $tmp/asletters_tot.tmp || error 14 $LINENO ${error_array[14]};
    else
      cp $tmp/abbr_acro_as_letters $tmp/asletters_tot.tmp || error 14 $LINENO ${error_array[14]};
    fi
  else
    cp $tmp/abbr_acro_as_letters $tmp/asletters_tot.tmp || error 14 $LINENO ${error_array[14]};
  fi

  # Create a table where the 1st col is the acronym and the 2nd one is the acronym with with spaces between the letters
  paste <(cat $tmp/asletters_tot.tmp \
     | awk '{ print length, $0 }' \
     | sort -nrs | cut -d" " -f2) \
  <(cat $tmp/asletters_tot.tmp \
     | awk '{ print length, $0 }' \
     | sort -nrs | cut -d" " -f2 \
     | sed -re 's/./\l& /g' -e 's/ +$//') \
     | tr '\t' ' ' | sed -re 's: +: :g' \
  > $tmp/insert_space_into_acro.tmp || error 14 $LINENO ${error_array[14]};
  
  # Create a sed pattern file: Change the first space to ":"
  sed -re 's/ /\\b:/' -e 's/^.*/s:\\b&/' -e 's/$/:g/g' \
      < $tmp/insert_space_into_acro.tmp \
      > $tmp/acro_sed_pattern.tmp || error 13 $LINENO ${error_array[13]};
  
  /bin/sed -f $tmp/acro_sed_pattern.tmp ${intermediate}/text_exp1.txt \
    > ${intermediate}/text_exp2.txt || error 13 $LINENO ${error_array[13]};
 
fi

if [ $stage -le 4 ]; then
  
  echo "Fix the casing of words in the text and extract new vocabulary"

  #Lowercase what only exists in lc in the prondict and uppercase what only exists in uppercase in the prondict

  # Find the vocabulary that appears in both cases in text
  cut -f1 $prondict | sort -u \
    | sed -re "s:.+:\l&:" \
    | sort | uniq -d \
    > ${tmp}/prondict_two_cases.tmp || error 14 $LINENO ${error_array[14]};

  # Find words that only appear in upper case in the pron dict
  comm -13 <(sed -r 's:.*:\u&:' ${tmp}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]" | sort -u) \
       > ${tmp}/propernouns_prondict.tmp || error 14 $LINENO ${error_array[14]};

  comm -13 <(sort -u ${tmp}/prondict_two_cases.tmp) \
       <(cut -f1 $prondict | egrep "^[a-záðéíóúýþæö]" | sort -u) \
       > ${tmp}/only_lc_prondict.tmp || error 14 $LINENO ${error_array[14]};

  # Find words in the new text that are not in the pron dict
  # Exclude words that are abbreviations, acronyms as letters
  # or writing notations which are incorrect or discouraged by Althingi.
  comm -23 <(cut -d' ' -f2- ${intermediate}/text_exp2.txt \
    | tr ' ' '\n' | egrep -v '[0-9%‰°º²³,.:;?!<> ]' \
    | egrep -v "\b$(cat $tmp/abbr_pattern.tmp)\b" \
    | grep -vf $tmp/abbr_acro_as_letters | grep -vf $bad_words \
    | sort -u | egrep -v '^\s*$' ) \
    <(cut -f1 $prondict | sort -u) \
    > $tmp/new_vocab_all.txt || error 14 $LINENO ${error_array[14]};
  sed -i -r 's:^.*Binary file.*$::' $tmp/new_vocab_all.txt

  if [ -s $tmp/new_vocab_all.txt ]; then
    # Find the ones that probably have the incorrect case
    comm -12 $tmp/new_vocab_all.txt \
	 <(sed -r 's:.+:\l&:' ${tmp}/propernouns_prondict.tmp) \
	 > $intermediate/to_uppercase.tmp || error 14 $LINENO ${error_array[14]};

    comm -12 $tmp/new_vocab_all.txt \
	 <(sed -r 's:.+:\u&:' ${tmp}/only_lc_prondict.tmp) \
	 > $intermediate/to_lowercase.tmp || error 14 $LINENO ${error_array[14]};

    # Lowercase a few words in the text before capitalizing
    tr "\n" "|" < $intermediate/to_lowercase.tmp \
      | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
      > $tmp/to_lowercase_pattern.tmp || error 13 $LINENO ${error_array[13]};

    sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
	< ${intermediate}/text_exp2.txt \
	> ${intermediate}/text_case1.txt || error 13 $LINENO ${error_array[13]};

    # Capitalize
    tr "\n" "|" < $intermediate/to_uppercase.tmp \
    | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
    | sed 's:.*:\L&:' > $tmp/to_uppercase_pattern.tmp || error 13 $LINENO ${error_array[13]};

    sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
	< ${intermediate}/text_case1.txt \
	> ${intermediate}/text_case2.txt || error 13 $LINENO ${error_array[13]};

    # Do the same for the punctuation text
    sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
	< ${intermediate}/text_exp1_forPunct.txt \
	> ${intermediate}/text_case1_forPunct.txt || error 13 $LINENO ${error_array[13]};

    sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
	< ${intermediate}/text_case1_forPunct.txt \
	> ${intermediate}/text_case2_forPunct.txt || error 13 $LINENO ${error_array[13]};

  else
    cp ${intermediate}/text_exp2.txt ${intermediate}/text_case2.txt
    cp ${intermediate}/text_exp1_forPunct.txt ${intermediate}/text_case2_forPunct.txt
  fi
  
  # Sometimes there are personal names that exist both in upper and lowercase, fix if
  # they have accidentally been lowercased
  tr "\n" "|" < $tmp/ambiguous_names \
    | sed '$s/|$//' \
    | perl -pe "s:\|:\\\b\|\\\b:g" \
    | sed 's:.*:\L&:' > $tmp/ambiguous_personal_names_pattern.tmp || error 13 $LINENO ${error_array[13]};

  # Fix personal names, company names which are followed by hf, ohf or ehf. Keep single letters lowercased.
  sed -re 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
      -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
      -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
      -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖ])\b:\l\1:g' -e 's:[º°]c:°C:g' \
      < $intermediate/text_case2.txt > $textout || error 13 $LINENO ${error_array[13]};  

  # And for the punctuation text (add a newline at the end):
  sed -re 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
      -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
      -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
      -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖ])\b:\l\1:g' -e 's:[º°]c:°C:g' -e '$a\' \
      < $intermediate/text_case2_forPunct.txt > $punct_textout || error 13 $LINENO ${error_array[13]};
  
fi

if [ $stage -le 5 ]; then
  # Extract the vocabulary that is truly new, not just words in incorrect cases
  if [ -s $tmp/new_vocab_all.txt ]; then
    echo "Extract the vocabulary that is truly new"
    comm -23 <(comm -23 $tmp/new_vocab_all.txt $intermediate/to_uppercase.tmp) \
       $intermediate/to_lowercase.tmp > $new_vocab || error 14 $LINENO ${error_array[14]};
  fi
fi

exit 0

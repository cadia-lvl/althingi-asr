#!/bin/bash -e

set -o pipefail

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Get the Althingi data on a proper format for kaldi.

stage=-1
nj=24
lex_ext=txt

. ./path.sh # Needed for KALDI_ROOT and ASSET_ROOT
. ./cmd.sh
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

utf8syms=$root_listdir/utf8.syms
prondict=$(ls -t $root_lexicon/prondict.* | head -n1)
# All root_* variables are defined in path.conf
acronyms_as_words=$(ls -t $root_capitalization/acronyms_as_words.* | head -n1)
named_entities=$(ls -t $root_capitalization/named_entities.* | head -n1)
cut -f1 $root_thraxgrammar_lex/abbr_lexicon.$lex_ext | tr " " "\n" | sort -u > $tmp/abbr_list
cut -f2 $root_thraxgrammar_lex/acro_denormalize.$lex_ext > $tmp/abbr_acro_as_letters
cut -f2 $root_thraxgrammar_lex/ambiguous_personal_names.$lex_ext > $tmp/ambiguous_names

if [ $# -ne 3 ]; then
    echo "This script cleans Icelandic parliamentary data, as obtained from the parliament."
    echo "It is assumed that the text data provided consists of two sets of files,"
    echo "the initial text and the final text. The texts in cleaned and normalized and"
    echo "Kaldi directories are created, containing the following files:"
    echo "utt2spk, spk2utt, wav.scp and text"
    echo ""
    echo "Usage: $0 <path-to-original-data> <output-data-dir>" >&2
    echo "e.g.: $0 /data/local/corpus data/all data/all/text_prepared" >&2
    exit 1;
fi

corpusdir=$(readlink -f $1); shift
outdir=$1; shift
punct_textout=$1; shift
textout=$1
intermediate=$outdir/intermediate
mkdir -p $intermediate

[ ! -d $corpusdir ] && echo "$0: expected $corpusdir to exist" && exit 1
for f in $utf8syms $prondict $acronyms_as_words $named_entities \
$tmp/abbr_list $tmp/abbr_acro_as_letters $tmp/ambiguous_names; do
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

# Make the abbreviation regex pattern used in punctuation cleaning and correcting capitalization
cat $tmp/abbr_list <(sed -r 's:.*:\u&:' $tmp/abbr_list) \
| sort -u | tr "\n" "|" | sed '$s/|$//' \
| perl -pe "s:\|:\\\b\|\\\b:g" \
> $tmp/abbr_pattern.tmp || error 1 $LINENO "Failed creating pattern of abbreviations";


# All the files should be the same type: mp3
extension=$(find ${corpusdir}/audio/ -type f | sed -rn 's|.*/[^/]+\.([^/.]+)$|\1|p' | sort -u)

# Need to convert from mp3 to wav
samplerate=16000
# SoX converts all audio files to an internal uncompressed format before performing any audio processing

wav_cmd="sox -t$extension - -c1 -esigned -r$samplerate -G -twav - "

if [ $stage -le 0 ]; then
    
    echo "a) utt2spk" # Connect each utterance to a speaker.
    echo "b) wav.scp" # Connect every utterance with an audio file
    for s in ${outdir}/utt2spk ${outdir}/wav.scp ${intermediate}/filename_uttID.txt; do
        if [ -f ${s} ]; then rm ${s}; fi
    done
    
    IFS=$'\n' # Want to separate on new lines
    for file in $(ls ${corpusdir}/audio/*.$extension)
    do
        filename=$(basename $file | cut -d"." -f1)
        spkID=$(perl -ne 'print "$1\n" if /\bskst=\"([^\"]+)/' ${corpusdir}/text_endanlegt/${filename}.xml | head -n1) # Two ignore the IDs of those that shout something at the speaker
        
        # Print to utt2spk
        printf "%s %s\n" ${spkID}-${filename} ${spkID} | tr -d $'\r' >> ${outdir}/utt2spk
        
        # Make a helper file with mapping between the filenames and uttID
        echo -e ${filename} ${spkID}-${filename} | tr -d $'\r' | LC_ALL=C sort -n >> ${intermediate}/filename_uttID.txt
        
        #Print to wav.scp
        echo -e ${spkID}-${filename} $wav_cmd" < "$(readlink -f $file)" |" | tr -d $'\r' >> ${outdir}/wav.scp
    done
    
    for f in utt2spk wav.scp; do
        sort -u $outdir/$f > $tmp/tmp && mv $tmp/tmp $outdir/$f
    done
    
    echo "c) spk2utt"
    utils/utt2spk_to_spk2utt.pl < ${outdir}/utt2spk > ${outdir}/spk2utt
fi

if [ $stage -le 1 ]; then
    
    echo "d) text" # Each line is utterance ID and the utterance itself
    for n in upphaflegt endanlegt; do
        (
            utils/slurm.pl --time 0-06:00 $outdir/log/extract_text_${n}.log \
            python3 local/extract_text.py $corpusdir/text_${n} $outdir/text_orig_${n}.txt
            ret=$?
            if [ $ret -ne 0 ]; then
                error 1 $LINENO "extract_text.py failed";
            fi
        ) &
    done
    wait;
fi

if [ $stage -le 2 ]; then
    
    echo "Remove xml-tags and comments"
    
    # In the following I separate the numbers on "|":
    # 1) removes comments on the form "<mgr>//....//</mgr>"
    # 2) removes comments on the form "<!--...-->"
    # 3) removes links that were not written like 2)
    # 4) removes f.ex. <mgr>::afritun af þ. 287::</mgr>
    # 5) removes comments on the form "<mgr>....//</mgr>"
    # 6-7) removes comments before the beginning of speeches
    # 8-11) removes comments like "<truflun>Kliður í salnum.</truflun>"
    # 12) removes comments in parentheses
    # 13) (in a new line) Rewrite fractions
    # 14-16) Rewrite law numbers
    # 17-19) Remove comments in a) parentheses, b) left: "(", right "/" or "//", c) left: "/", right one or more ")" and maybe a "/", d) left and right one or more "/"
    # 20) Remove comments on the form "xxxx", used when they don't hear what the speaker said
    # 21-22) Remove the remaining tags and reduce the spacing to one between words
    sed -re 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
    -e 's:\(+[^/()<>]*?\)+: :g' \
    -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
    -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
    -e 's:\([^/<>)]*?/+: :g' -e 's:/[^/<>)]*?\)+/?: :g' -e 's:/+[^/<>)]*?/+: :g' \
    -e 's:xx+::g' \
    -e 's:<[^<>]*?>: :g' -e 's:[[:space:]]+: :g' \
    < ${outdir}/text_orig_upphaflegt.txt \
    > ${outdir}/text_noXML_upphaflegt.txt || error 13 $LINENO ${error_array[13]};
    
    sed -re 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>|<[^>]*?>: :g' \
    -e 's:\([^/()<>]*?\)+: :g' \
    -e 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
    -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
    -e 's:[[:space:]]+: :g' \
    < ${outdir}/text_orig_endanlegt.txt \
    > ${outdir}/text_noXML_endanlegt.txt || error 13 $LINENO ${error_array[13]};
    
    # Sometimes some of the intermediatary text files are empty.
    # I remove the empty files and add corresponding final-text-files in the end
    egrep -v "rad[0-9][^ ]+ *$" \
    < ${outdir}/text_noXML_upphaflegt.txt \
    > $tmp/tmp && mv $tmp/tmp ${outdir}/text_noXML_upphaflegt.txt
    
    # Remove files that exist only in the initial text
    comm -12 \
    <(cut -d" " -f1 ${outdir}/text_noXML_upphaflegt.txt | sort -u) \
    <(cut -d" " -f1 ${outdir}/text_noXML_endanlegt.txt | sort -u) \
    > ${tmp}/common_ids.tmp || error 14 $LINENO ${error_array[14]};
    join -j1 \
    <(sort -u ${tmp}/common_ids.tmp) \
    <(sort -u ${outdir}/text_noXML_upphaflegt.txt) \
    > $tmp/tmp && mv $tmp/tmp ${outdir}/text_noXML_upphaflegt.txt \
    || error 14 $LINENO ${error_array[14]};
    
fi


if [ $stage -le 3 ]; then
    
    echo "Rewrite roman numerals before lowercasing" # Enough to rewrite X,V and I based numbers. L=50 is used once and C, D and M never.
    # Might clash with someones middle name. # The module roman comes from Dive into Python
    for n in upphaflegt endanlegt; do
        (
            sed -i -r 's/([A-Z]\.?)–([A-Z])/\1 til \2/g' ${outdir}/text_noXML_${n}.txt
            python3 -c "
import re
import sys
roman_path='$KALDI_ROOT/egs/althingi/s5/local'
if not roman_path in sys.path:
    sys.path.append(roman_path)
import roman
text = open('${outdir}/text_noXML_${n}.txt', 'r')
text_out = open('${intermediate}/text_noRoman_${n}.txt', 'w')
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
            ret=$?
            if [ $ret -ne 0 ]; then
                error 1 $LINENO "Failed rewriting Roman numerals";
            fi
        ) &
    done
    wait;
fi

if [ $stage -le 4 ]; then
    
    echo "Rewrite and remove punctuations"
    # 1) Remove comments that appear at the end of certain speeches (still here because contained <skáletrað> in original text)
    # 2) Rewrite time,
    # 3) Change "&amp;" to "og"
    # 4) Remove punctuations which is safe to remove
    # 5) Remove commas used as quotation marks, remove or change "..." -> "." and "??+" -> "?"
    # 6) Deal with double punctuation after words/numbers
    # 7) Remove "ja" from numbers written like "22ja",
    # 8) Rewrite [ck]?m[23] to [ck]?m[²³] and "kV" to "kw"
    # 9) Fix spelling errors like "be4stu" and "o0g",
    # 10) Rewrite website names,
    # 11) In an itemized list, lowercase what comes after the numbering.
    # 12) Rewrite en dash (x96), regular dash and "tilstr(ik)" to " til ", if sandwitched between words or numbers,
    # 13-14) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
    # 15) Rewrite vulgar fractions
    # 16) Add space before "," when not followed by a number and before ";"
    # 17) Remove the period in abbreviated middle names
    # 18) Remove periods inside abbreviation
    # 19) For measurement units and a few abbreviations that often stand at the end of sentences, add space before the period
    # 20) Move EOS punctuation away from the word and lowercase the next word, if the previous word is a number or it is the last word.
    # 21) Remove the abbreviation periods
    # 22) Move remaining EOS punctuation away from the word and lowercase next word
    # 23) Lowercase the first word in a speech
    # 24) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
    # 25) Switch dashes (exept in utt filenames) and remaining slashes out for space
    # 26) Rewrite thousands and millions, f.ex. 3.500 to 3500,
    # 27) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
    # 28) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
    # 29) Remove punctuation attached to the word behind
    # 30) Fix spacing around % and degrees celsius and add space in a number starting with a zero
    # 31) Remove "lauk á fyrri spólu"
    # 32) Split into two words, words that are often incorrectly written as one.
    # 33) Fix if the first letter in an acronym has been lowercased.
    # 34) Remove punctuations that we don't want to learn, map remaining weird words to <unk> and fix spacing
    for n in upphaflegt endanlegt; do
        sed -re 's:\[[^]]*?\]: :g' \
        -e 's/([0-9]):([0-9][0-9])/\1 \2/g' \
        -e 's/&amp;/ og /g' \
        -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |__+: :g' \
        -e 's: ,,: :g' -e 's:\.\.+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):. \1:g' -e 's:\.\.+::g' -e 's:([^a-záðéíóúýþæö ]) ?\?\?+:\1:g' -e 's:\?\?+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):? \1:g' -e 's:\?\?+::g' \
        -e 's:\b([^0-9 .,:;?!]+)([.,:;?!]+)([.,:;?!]):\1 \3 :g' -e 's:\b([0-9]+[.,:;?!])([.,:;?!]):\1 \2 :g' -e 's:\b(,[0-9]+)([.,:;?!]):\1 \2 :g' \
        -e 's:([0-9]+)ja\b:\1:g' \
        -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: ([kgmt])[wV] : \1W :g' -e 's:Wst:\L&:g' \
        -e 's:\b([a-záðéíóúýþæö]+)[0-9]([a-záðéíóúýþæö]+):\1\2:g' \
        -e 's:www\.:w w w :g' -e 's:\.(is|net|com|int)\b: punktur \1:g' \
        -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
        -e 's:([^ 0-9])–([^ 0-9]):\1 \2:g' -e 's:([^ ])–([^ ]):\1 til \2:g' -e 's:([0-9]\.?)tilstr[^ 0-9]*?\.?([0-9]):\1 til \2:g' -e 's:([0-9\.%])-+([0-9]):\1 til \2:g' \
        -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
        < ${intermediate}/text_noRoman_${n}.txt \
        | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
        | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
        -e 's:([,;])([^0-9]|\s*$): \1 \2:g' -e 's:([^0-9]),:\1 ,:g' \
        -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
        -e 's:\.([a-záðéíóúýþæö]):\1:g' \
        -e 's:[ /]([ck]?m[²³]?|[km]g|[kmgt]?w|gr|umr|sl|millj|nk|mgr|kr|osfrv)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
        -e 's:([0-9,.]{3,})([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) *:\1 \2 :g' -e 's:([.:?!]+)\s*$: \1:g' \
        -e "s:(\b$(cat $tmp/abbr_pattern.tmp))\.:\1:g" \
        -e 's:([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([^0-9])([.:?!]+)([0-9]):\1 \2 \3:g' -e 's:([^0-9])([.:?!]+):\1 \2:g' \
        -e 's:(^[^ ]+) ([^ ]+):\1 \l\2:' \
        -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
        -e 's:—|–|/|tilstr[^ 0-9]*?\.?: :g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
        -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
        -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
        -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
        -e 's: [.,:;?!]([^ 0-9]): \1:g' \
        -e 's: *%:% :g' -e 's:([°º]) [Cc] :\1c :g' -e 's:([°º])([^cC ]):\1 \2:g' -e 's: 0([0-9]): 0 \1:g' \
        -e 's:lauk á (f|fyrri) ?sp.*::' \
        -e 's:\b(enn|fram|fyrir|meiri|minni)(fremur|þá|hjá|fram|háttar|hlut[ia])\b:\1 \2:gI' \
        -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ][^a-záðéíóúýþæö]):\u\1:g' \
        -e 's/[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9\.,?!:; %‰°º²³]+//g' -e 's/ [^ ]*[A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+[0-9]+[^ ]*/ <unk>/g' -e 's: [0-9]{10,}: <unk>:g' -e 's/ +/ /g' \
        > ${outdir}/text_noPuncts_${n}.txt || error 13 $LINENO ${error_array[13]};
    done
    
fi

if [ $stage -le 5 ]; then
    echo "Expand some abbreviations"
    for n in upphaflegt endanlegt; do
        # Start with expanding some abbreviations using regex
        sed -re 's:\bamk\b:að minnsta kosti:g' \
        -e 's:\bdr\b:doktor:g' \
        -e 's:\betv\b:ef til vill:g' \
        -e 's:\bfrh\b:framhald:g' \
        -e 's:\bfyrrv\b:fyrrverandi:g' \
        -e 's:\bheilbrrh\b:heilbrigðisráðherra:g' \
        -e 's:\biðnrh\b:iðnaðarráðherra:g' \
        -e 's:\binnanrrh\b:innanríkisráðherra:g' \
        -e 's:\blandbrh\b:landbúnaðarráðherra:g' \
        -e 's:\bmas\b:meira að segja:g' \
        -e 's:\bma\b:meðal annars:g' \
        -e 's:\bmenntmrh\b:mennta og menningarmálaráðherra:g' \
        -e 's:\bmkr\b:millj kr:g' \
        -e 's:\bnk\b:næstkomandi:g' \
        -e 's:\bnr\b:númer:g' \
        -e 's:\bnúv\b:núverandi:g' \
        -e 's:\bosfrv\b:og svo framvegis:g' \
        -e 's:\boþh\b:og þess háttar:g' \
        -e 's:\bpr\b:per:g' \
        -e 's:\bsbr\b:samanber:g' \
        -e 's:\bskv\b:samkvæmt:g' \
        -e 's:\bss\b:svo sem:g' \
        -e 's:\bstk\b:stykki:g' \
        -e 's:\btd\b:til dæmis:g' \
        -e 's:\btam\b:til að mynda:g' \
        -e 's:\buþb\b:um það bil:g' \
        -e 's:\butanrrh\b:utanríkisráðherra:g' \
        -e 's:\bviðskrh\b:viðskiptaráðherra:g' \
        -e 's:\bþáv\b:þáverandi:g' \
        -e 's:\bþús\b:þúsund:g' \
        -e 's:\bþeas\b:það er að segja:g' \
        < ${outdir}/text_noPuncts_${n}.txt \
        > ${intermediate}/text_exp1_${n}.txt || error 14 $LINENO ${error_array[14]};
    done
    
    # Capitalize acronyms which are pronounced as words (some are incorrectly written capitalized, e.g. IKEA as Ikea)
    # Make the regex pattern
    tr "\n" "|" < $acronyms_as_words \
    | sed '$s/|$//' \
    | perl -pe "s:\|:\\\b\|\\\b:g" \
    > ${tmp}/acronyms_as_words_pattern.tmp || error 14 $LINENO ${error_array[14]};
    
    for n in upphaflegt endanlegt; do
        # Capitalize
        sed -re 's:(\b'$(cat ${tmp}/acronyms_as_words_pattern.tmp)'\b):\U\1:gI' \
        -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ]{2,})\b:\u\1:g' \
        < ${intermediate}/text_exp1_${n}.txt \
        > ${intermediate}/text_exp1_${n}_acroCS.txt || error 14 $LINENO ${error_array[14]};
        
        # Use Anna's code to expand many instances of hv, þm og hæstv
        python3 local/althingi_replace_plain_text.py \
        ${intermediate}/text_exp1_${n}_acroCS.txt \
        ${intermediate}/text_exp2_${n}.txt
        ret=$?
        if [ $ret -ne 0 ]; then
            error 1 $LINENO "Error in althingi_replace_plain_text.py";
        fi
    done
    
    # I don't want to expand acronyms pronounced as letters in the punctuation training text
    echo "make a special text version for the punctuation training texts"
    cp ${intermediate}/text_exp2_endanlegt.txt ${intermediate}/text_exp2_forPunct.txt || error 14 $LINENO ${error_array[14]};
    
    # Add spaces into acronyms pronounced as letters
    egrep -o "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" \
    < ${intermediate}/text_exp2_{upphaflegt,endanlegt}.txt \
    | cut -d":" -f2 | sort -u > $tmp/acro.tmp || error 14 $LINENO ${error_array[14]};
    
    egrep "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" \
    < $tmp/acro.tmp > $tmp/asletters.tmp || error 14 $LINENO ${error_array[14]};
    
    cat $tmp/asletters.tmp $tmp/abbr_acro_as_letters \
    | sort -u > $tmp/asletters_tot.tmp || error 14 $LINENO ${error_array[14]};
    
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
    > $tmp/acro_sed_pattern.tmp || error 14 $LINENO ${error_array[14]};
    
    for n in upphaflegt endanlegt; do
        /bin/sed -f $tmp/acro_sed_pattern.tmp ${intermediate}/text_exp2_${n}.txt \
        > ${intermediate}/text_exp3_${n}.txt || error 14 $LINENO ${error_array[14]};
    done
fi

if [ $stage -le 6 ]; then
    
    echo "Fix spelling errors"
    # Commented out the option to fix words where the edit distance was >1.
    # Damerau-Levenshtein considers a single transposition to have distance 1.
    # Much faster and fixes most of the errors
    cut -d" " -f2- < ${intermediate}/text_exp3_endanlegt.txt \
    | sed -e 's/[0-9.,:;?!%‰°º]//g' \
    | tr " " "\n" \
    | egrep -v "^\s*$" \
    | sort -u \
    > ${intermediate}/words_text_endanlegt.txt || error 14 $LINENO ${error_array[14]};
    
    cat ${intermediate}/words_text_endanlegt.txt \
    <(cut -f1 $prondict) | sort -u \
    > $intermediate/words_all.txt
    
    if [ -f ${outdir}/text_SpellingFixed.txt ]; then
        rm ${outdir}/text_SpellingFixed.txt
    fi
    
    # Split into subfiles and correct them in parallel
    mkdir -p ${intermediate}/split${nj}/log
    total_lines=$(wc -l ${intermediate}/text_exp3_upphaflegt.txt | cut -d" " -f1) \
    || error 14 $LINENO ${error_array[14]};
    
    ((lines_per_file = (total_lines + nj - 1) / nj)) || error 14 $LINENO ${error_array[14]};
    
    split --lines=${lines_per_file} \
    ${intermediate}/text_exp3_upphaflegt.txt \
    ${intermediate}/split${nj}/text_exp3_upphaflegt. \
    || error 1 $LINENO "Error splitting lines with split";
    
    # Activate a virt environment to be able to use Damerau-Levenshtein edit distance
    source venv3/bin/activate || error 11 $LINENO ${error_array[11]};
    IFS=$'\n' # Important
    for ext in $(ls ${intermediate}/split${nj}/text_exp3_upphaflegt.* | cut -d"." -f2); do
        # NOTE! Can't let the script wait till all the sbatch jobs are finished and can't pass on user-env when use utils/slurm.pl
        
        # sbatch --get-user-env --time=0-6 --job-name=correct_spelling --output=${intermediate}/split${nj}/log/spelling_fixed.${ext}.log --wrap="srun local/correct_spelling.sh --ext $ext $intermediate/words_all.txt ${intermediate}/split${nj}/text_exp3_upphaflegt ${intermediate}/text_exp3_endanlegt.txt"
        (
            utils/slurm.pl ${intermediate}/split${nj}/log/spelling_fixed.${ext}.log local/correct_spelling.sh --ext $ext $intermediate/words_all.txt ${intermediate}/split${nj}/text_exp3_upphaflegt ${intermediate}/text_exp3_endanlegt.txt || error 1 $LINENO "Error running correct_spelling.sh";
        ) &
    done
    deactivate
    
    wait;
    cat ${intermediate}/split${nj}/text_SpellingFixed.*.txt > ${outdir}/text_SpellingFixed.txt
    
fi

if [ $stage -le 7 ]; then
    
    # If the initial text file is empty or does not exist, use the final one instead
    comm -13 \
    <(cut -d" " -f1 ${outdir}/text_SpellingFixed.txt | sort -u) \
    <(cut -d" " -f1 ${intermediate}/text_exp3_endanlegt.txt | sort -u) \
    > ${tmp}/ids_only_in_text_endanlegt.tmp || error 14 $LINENO ${error_array[14]};
    
    join -j1 \
    <(sort -u ${tmp}/ids_only_in_text_endanlegt.tmp) \
    <(sort -u ${intermediate}/text_exp3_endanlegt.txt) \
    >> ${outdir}/text_SpellingFixed.txt || error 14 $LINENO ${error_array[14]};
    
    sort -u ${outdir}/text_SpellingFixed.txt \
    > $tmp/tmp && mv $tmp/tmp ${outdir}/text_SpellingFixed.txt
    
fi

if [ $stage -le 8 ]; then
    echo "Fix the casing of words in the text and extract new vocabulary"
    # Since some casing might be incorrect after the punctuation removal
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
    comm -23 <(cut -d' ' -f2- ${outdir}/text_SpellingFixed.txt \
        | tr ' ' '\n' | egrep -v '[0-9%‰°º²³,.:;?! ]' \
        | egrep -v "\b$(cat $tmp/abbr_pattern.tmp)\b" \
    | grep -vf $tmp/abbr_acro_as_letters | sort -u | egrep -v '^\s*$') \
    <(cut -f1 $prondict | sort -u) \
    > $tmp/new_vocab_all.txt || error 14 $LINENO ${error_array[14]};
    sed -i -r 's:^.*Binary file.*$::' $tmp/new_vocab_all.txt
    
    # Find the ones that probably have the incorrect case
    comm -12 $tmp/new_vocab_all.txt \
    <(sed -r 's:.+:\l&:' ${tmp}/propernouns_prondict.tmp) \
    > $intermediate/to_uppercase.tmp || error 14 $LINENO ${error_array[14]};
    
    comm -12 $tmp/new_vocab_all.txt \
    <(sed -r 's:.+:\u&:' ${tmp}/only_lc_prondict.tmp) \
    > $intermediate/to_lowercase.tmp || error 14 $LINENO ${error_array[14]};
    
    tr "\n" "|" < $intermediate/to_lowercase.tmp \
    | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
    > $tmp/to_lowercase_pattern.tmp || error 14 $LINENO ${error_array[14]};
    
    tr "\n" "|" < $intermediate/to_uppercase.tmp \
    | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
    | sed 's:.*:\L&:' > $tmp/to_uppercase_pattern.tmp || error 14 $LINENO ${error_array[14]};
    
    # Lowercase a few words in the text before capitalizing
    sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
    < ${outdir}/text_SpellingFixed.txt \
    > ${intermediate}/text_case1.txt || error 14 $LINENO ${error_array[14]};
    
    # Capitalize
    sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
    < ${intermediate}/text_case1.txt \
    > ${intermediate}/text_case2.txt || error 14 $LINENO ${error_array[14]};
    
    # Sometimes there are personal names that exist both in upper and lowercase, fix if
    # they have accidentally been lowercased
    tr "\n" "|" < $tmp/ambiguous_names \
    | sed '$s/|$//' \
    | perl -pe "s:\|:\\\b\|\\\b:g" \
    | sed 's:.*:\L&:' > $tmp/ambiguous_personal_names_pattern.tmp
    
    # Fix personal names, company names which are followed by hf, ohf or ehf. Keep single letters lowercased.
    sed -re 's:\byou ?tube\b:YouTube:gI' \
    -e 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
    -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
    -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
    -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖ])\b:\l\1:g' -e 's:([º°])c:\1C:g' \
    < $intermediate/text_case2.txt > $intermediate/text_case3.txt || error 14 $LINENO ${error_array[14]};
    
    # Fix named entities that are incorrectly lowercased
    cat $named_entities $named_entities \
    | sort | awk 'ORS=NR%2?":":"\n"' \
    | sed -re 's/^.*/s:\\b&/' -e 's/$/:gI/g' \
    > $tmp/ner_sed_pattern.tmp
    
    /bin/sed -f $tmp/ner_sed_pattern.tmp \
    < $intermediate/text_case3.txt \
    > ${intermediate}/text_SpellingFixed_CasingFixed.txt || error 14 $LINENO ${error_array[14]};
    
    # Do the same for the punctuation text
    sed -r 's:(\b'$(cat $tmp/to_lowercase_pattern.tmp)'\b):\l\1:g' \
    < ${intermediate}/text_exp2_forPunct.txt \
    > ${intermediate}/text_case1_forPunct.txt || error 14 $LINENO ${error_array[14]};
    
    sed -r 's:(\b'$(cat $tmp/to_uppercase_pattern.tmp)'\b):\u\1:g' \
    < ${intermediate}/text_case1_forPunct.txt \
    > ${intermediate}/text_case2_forPunct.txt || error 14 $LINENO ${error_array[14]};
    
    # The last regex puts a newline at the end of the speech
    sed -re 's:\byou ?tube\b:YouTube:gI' \
    -e 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
    -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
    -e 's:(\b'$(cat $tmp/ambiguous_personal_names_pattern.tmp)'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
    -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖ])\b:\l\1:g' -e 's:([º°])c:\1C:g' -e '$a\' \
    < $intermediate/text_case2_forPunct.txt > $intermediate/text_case3_forPunct.txt || error 14 $LINENO ${error_array[14]};
    
    /bin/sed -f $tmp/ner_sed_pattern.tmp \
    < $intermediate/text_case3_forPunct.txt \
    > $punct_textout || error 14 $LINENO ${error_array[14]};
fi

if [ $stage -le 8 ]; then
    # Join the utterance names with the spkID to make the uttIDs
    join -j 1 \
    <(sort -k1,1 -u ${intermediate}/filename_uttID.txt) \
    <(sort -k1,1 ${intermediate}/text_SpellingFixed_CasingFixed.txt) | cut -d" " -f2- \
    > ${outdir}/text_SpellingFixed_uttID.txt || error 14 $LINENO ${error_array[14]};
    
    if [ -e ${outdir}/text ] ; then
        # we don't want to overwrite old stuff, ask the user to delete it.
        echo "$0: ${outdir}/text already exists: "
        echo "Are you sure you want to proceed?"
        echo "It will overwrite the file"
        echo ""
        echo "  If so, please delete and then rerun"
        exit 1;
    fi
    
    cp ${outdir}/text_SpellingFixed_uttID.txt ${outdir}/text
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-feats ${outdir} || utils/fix_data_dir.sh ${outdir} || exit 1;
    
    mv ${outdir}/text ${textout}
fi

rm -r $intermediate

exit 0

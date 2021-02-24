#!/bin/bash -e

set -o pipefail

# Clean new text, extract new vocabulary and create acoustic, language model and punctuation training texts
# I assume this is automatically run after each speech is submitted by transcribers
# To run from the s5 dir

stage=0
clean_stage=0
vocab_ext=tsv
text_ext=txt

. ./path.sh # the $root_* variable are defined here
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

# #date
# d=$(date +'%Y%m%d')

g2p=$(ls -t $root_g2p/*/g2p.mdl | head -n1)

# Output dirs for LM and AM texts
amdir=$root_am_transcripts
lmdir=$root_lm_transcripts
punctdir=$root_punctuation_transcripts
paragraphdir=$root_paragraph_transcripts
vocabdir=$root_new_vocab
concordancedir=$root_vocab_concordance
mkdir -p $amdir $lmdir $punctdir $paragraphdir $vocabdir $concordancedir

# NOTE! We have environment problems. Quick fix is:
export LANG=en_US.UTF-8

# NOTE! I have to design this with Judy. It would probably be best if this runs automatically
# every time a transcriber has read through an ASR transcript. The editors would then see
# the new vocabulary when they start editing the text. The input and output could be defined
# from the speechname, f.ex.
# NOTE! But what if the editors are in a hurry and start immediately, before the vocab list is ready?
# we will have to make it allowed to not provide a vocab file
if [ $# != 2 ]; then
    echo "Usage: local/extract_new_vocab_and_text.sh [options] <input-file> <output-dir>"
    echo "e.g.: local/extract_new_vocab_and_text.sh xmldata/speechname.xml temp"
fi

infile=$(readlink -f $1); shift
speechname=$(basename $infile)
speechname="${speechname%.*}"
outdir=$1; shift
outdir=${outdir}/$speechname

for f in $infile $g2p; do
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ -d $outdir ]; then
    echo "$outdir already exists, I remove it"
    rm -r $outdir
fi

intermediate=$outdir/intermediate
mkdir -p $outdir/{intermediate,log}

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $stage -le 1 ]; then
    
    echo "Extract text from xml file"
    # Extract text, remove XML tags and carriage return and add the uttID in front.
    tr "\n" " " < $infile \
    | sed -re 's:</mgr></ræðutexti></ræða> <ræðutexti><mgr>: :g' -e 's:(.*)?<ræðutexti>(.*)</ræðutexti>(.*):\2:' \
    -e 's:<mgr>//[^/<]*?//</mgr>|<!--[^>]*?-->|http[^<> )]*?|<[^>]*?>\:[^<]*?ritun[^<]*?</[^>]*?>|<mgr>[^/]*?//</mgr>|<ræðutexti> +<mgr>[^/]*?/</mgr>|<ræðutexti> +<mgr>til [0-9]+\.[0-9]+</mgr>|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
    -e `echo "s/\r//"` -e 's: *<[^<>]*?>: :g' \
    -e "s:^.*:$speechname &:" -e 's: +: :g' \
    > $intermediate/text_orig.txt || error 13 $LINENO ${error_array[13]};
    
    # Quit if the text is missing
    if egrep -q 'rad[0-9][^ ]+ *$' $intermediate/text_orig.txt ; then
        echo "The XML for $speechname is empty"
        exit 1
    fi
    
    echo "Extract the speaker ID"
    spkID=$(perl -ne 'print "$1\n" if /\bskst=\"([^\"]+)/' $infile | head -n1)
    
    # Extract and prepare the text for paragraph model training
    tr "\n" " " < $infile \
    | sed -re 's:(.*)?<ræðutexti>(.*)</ræðutexti>(.*):\2:' \
    -e 's:<!--[^>]*?-->|<truflun>[^<]*?</truflun>|<atburður>[^<]*?</atburður>|<málsheiti>[^<]*?</málsheiti>: :g' \
    -e 's:</mgr><mgr>: EOP :g' -e 's:<[^>]*?>: :g' \
    -e 's:^ +::' \
    -e 's:\([^/()<>]*?\)+: :g' -e 's: ,,: :g' -e 's:\.\.+ :. :g' -e 's: ([,.:;?!] ):\1:g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |_+: :g' \
    -e 's: $: EOP :' -e 's:[[:space:]]+: :g' \
    -e 's:(EOP )+:EOP :g' -e 's:([—,—]) EOP:\1:g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9]) EOP :\1. :g' -e 's:EOP[,.:;?!] :EOP :g' \
    | sed -e '$a\' > $paragraphdir/${spkID}-${speechname}.$text_ext
    
    echo "Clean the text for all uses (AM, LM and for punctuation modelling)"
    local/clean_new_speech.sh --stage $clean_stage $intermediate/text_orig.txt $outdir/cleantext.txt $outdir/punct_text.txt $outdir/new_vocab.txt || error 1 "ERROR: clean_new_speech.sh failed";
    
    # Save the new punctuation training text
    sed -r "s:^$speechname ::" < $outdir/punct_text.txt > $punctdir/${spkID}-${speechname}.$text_ext
fi

if [ $stage -le 2 ]; then
    
    if [ -s $outdir/new_vocab.txt ]; then
        echo "Get the phonetic transcriptions of the new vocabulary"
        local/transcribe_g2p.sh $g2p $outdir/new_vocab.txt \
        > $vocabdir/${spkID}-${speechname}.$vocab_ext \
        || error 1 "ERROR: transcribe_g2p.sh failed"
    fi
    
    # NOTE! The new vocab has to be available in the text editor used at Althingi
    # I need to know where the confirmed words end up!
    
fi

if [ $stage -le 3 ]; then
    
    echo "Expand numbers and abbreviations"
    local/new_speeches/expand_text.sh $outdir/cleantext.txt ${outdir}/text_expanded \
    || error 1 "Expansion failed";
    # Sometimes the "og" in e.g. "hundrað og sextíu" is missing
    perl -pe 's/(hundr[au]ð) ([^ ]+tíu|tuttugu) (?!og)/$1 og $2 $3/g' \
    < ${outdir}/text_expanded > $tmp/tmp && mv $tmp/tmp ${outdir}/text_expanded
    
    # The ${outdir}/text_expanded utterances fit for use in the stage 2 punctuation training
    
    echo "Make a language model training text from the expanded text"
    cut -d' ' -f2- $outdir/text_expanded \
    | sed -re 's:[.:?!]+ *$::g' -e 's:[.:?!]+ :\n:g' \
    -e 's:[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö \n]::g' \
    -e 's: +: :g' \
    > $lmdir/${spkID}-${speechname}.$text_ext || exit 1;
    
    echo "Remove punctuations to make the text better fit for acoustic modelling. Add a spkID."
    sed -re 's: [^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö ] : :g' -e 's: +: :g' -e "s:.*:${spkID}-&:" \
    < ${outdir}/text_expanded > $amdir/${spkID}-${speechname}.$text_ext || exit 1;
    
fi

if [ $stage -le 4 ]; then
    if [ -s $vocabdir/${spkID}-${speechname}.$vocab_ext ]; then
        echo "Find the concordance of the new words"
        python local/new_speeches/concordance_of_new_vocab.py \
        $amdir/${spkID}-${speechname}.$text_ext $vocabdir/${spkID}-${speechname}.$vocab_ext \
        $concordancedir/${spkID}-${speechname}.$vocab_ext \
        || error 1 $LINENO "Failed to find the concordance of the new words";
    fi
fi

# Remove $outdir if all previous steps finished successfully
#rm -r $outdir

exit 0;

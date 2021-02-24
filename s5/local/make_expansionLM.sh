#!/bin/bash -e
set -o pipefail
# Idea from: Sproat, R. (2010). Lightly supervised learning of text normalization: Russian number names.

# Copyright 2016  Reykjavik University (Author: Robert Kjaran)
#           2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Usage: local/train_LM_forExpansion.sh [options]

nj=60
stage=-1
corpus=/data/leipzig/isl_sentences_10M.txt
utf8syms=/data/althingi/lists/utf8.syms
#dir=text_norm
#althdir=data/all

run_tests=false

. ./cmd.sh
. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
    echo "Usage: $0 <text-norm-dir> <althingi-data-dir>" >&2
    echo "Eg. $0 text_norm data/all" >&2
    exit 1;
fi

dir=$1
althdir=$2

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p $dir

lexdir=$root_thraxgrammar_lex

# Convert text file to a Kaldi table (ark).
# The archive format is:
# <key1> <object1> <newline> <key2> <object2> <newline> ...
if [ $stage -le 0 ]; then
    # Each text lowercased and given an text_id,
    # which is just the 10-zero padded line number
    awk '{printf("%010d %s\n", NR, tolower($0))}' $corpus \
    > ${dir}/texts.txt
fi

if [ $stage -le 1 ]; then
    
    echo "Clean the text a little bit"

    # Rewrite some and remove other punctuations. I couldn't exape
    # the single quote so use a hexadecimal escape

    # 1) Remove punctuations
    # 2) Add space between letters and digits in alphanumeric words
    # 3) Map all numbers to the tag <num>
    # 4) Map to one space between words
    nohup sed -e 's/[^a-yáðéíóúýþæö0-9 ]\+/ /g' ${dir}/texts.txt \
	| sed -e 's/\([0-9]\)\([a-záðéíóúýþæö]\)/\1 \2/g' -e 's/\([a-záðéíóúýþæö]\)\([0-9]\)/\1 \2/g' \
	| sed -e 's/ [0-9]\+/ <num>/g' \
        | tr -s " " > ${dir}/texts_no_puncts.txt
	
    # Sort the vocabulary based on frequency count
    nohup cut -d' ' -f2- < ${dir}/texts_no_puncts.txt \
        | tr ' ' '\n' \
        | egrep -v '^\s*$' > $tmp/words \
        && sort --parallel=8 $tmp/words \
            | uniq -c > $tmp/words.sorted \
        && sort -k1 -n --parallel=$[nj>8 ? 8 : nj] \
	    $tmp/words.sorted > ${dir}/words.cnt
    
fi

if [ $stage -le 2 ]; then
    # We select a subset of the vocabulary, every token occurring 30
    # times or more. This removes a lot of non-sense tokens.
    # But there is still a bunch of crap in there
    nohup awk '$2 ~ /[[:print:]]/ { if($1 > 29) print $2 }' \
        ${dir}/words.cnt | LC_ALL=C sort -u > ${dir}/wordlist30.txt

    # # Get the althingi vocabulary
    # cut -d" " -f2- ${althdir}/text_bb_SpellingFixed.txt | tr " " "\n" | sed -e 's/\b[0-9]\+[^ ]*/<num>/g' | grep -v "^\s*$" | sort -u > ${dir}/words_althingi.txt
    # I manually fixed most of the erraneous expansions in the first 100 hours of data I got.
    # Add if there are any words there that are not in the other dataset.
    comm -23 <(cut -d" " -f2- ${althdir}100/text | tr " " "\n" | egrep -v "^\s*$" | sort -u) <(sort ${dir}/words_althingi.txt) >> ${dir}/words_althingi.txt
    
    # Get a list of words solely in the althingi data and add it to wordlist30.txt
    comm -23 <(sort ${dir}/words_althingi.txt) <(sort ${dir}/wordlist30.txt) > ${dir}/vocab_alth_only.txt
    cat ${dir}/wordlist30.txt ${dir}/vocab_alth_only.txt > ${dir}/wordlist30_plusAlthingi.txt
    
    # Here I add the expanded abbreviations that were filtered out
    abbr_expanded=$(cut -f2 $lexdir/abbr_lexicon.txt | tr " " "\n" | sort -u)
    for abbr in $abbr_expanded
    do
	grep -q "\b${abbr}\b" ${dir}/wordlist30_plusAlthingi.txt || echo -e ${abbr} >> ${dir}/wordlist30_plusAlthingi.txt
    done

    # Add expanded numbers to the list
    cut -f2 $lexdir/ordinals_*?_lexicon.txt >> ${dir}/wordlist30_plusAlthingi.txt
    cut -f2 $lexdir/units_lexicon.txt >> ${dir}/wordlist30_plusAlthingi.txt
    
    # Make a word symbol table. Code from prepare_lang.sh
    cat ${dir}/wordlist30_plusAlthingi.txt | grep -v "<num>"| LC_ALL=C sort | uniq  | awk '
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
    }' > $dir/words30.txt

    # Replace OOVs with <unk>
    cat ${dir}/texts_no_puncts.txt \
        | utils/sym2int.pl --map-oov "<unk>" -f 2- ${dir}/words30.txt \
        | utils/int2sym.pl -f 2- ${dir}/words30.txt > ${dir}/texts_no_oovs.txt

    # We want to process it in parallel. NOTE! One time split_scp.pl complained about $out_scps!
    mkdir -p ${dir}/split$nj/
    out_scps=$(for j in `seq 1 $nj`; do printf "${dir}/split%s/texts_no_oovs.%s.txt " $nj $j; done)
    utils/split_scp.pl ${dir}/texts_no_oovs.txt $out_scps
    
fi

if [ $stage -le 3 ]; then
    # Compile the lines to linear FSTs with utf8 as the token type
    utils/slurm.pl --mem 2G JOB=1:$nj ${dir}/log/compile_strings.JOB.log fststringcompile ark:${dir}/split$nj/texts_no_oovs.JOB.txt ark:"| gzip -c > ${dir}/texts_fsts.JOB.ark.gz" &
    
fi

if [ $stage -le 4 ]; then
    # We need a FST to map from utf8 tokens to words in the words symbol table.
    # f1=word, f2-=utf8_tokens (0x0020 always ends a utf8_token seq)
    utils/slurm.pl \
        ${dir}/log/words30_to_utf8.log \
        awk '$2 != 0 {printf "%s %s \n", $1, $1}' \< ${dir}/words30.txt \
        \| fststringcompile ark:- ark:- \
        \| fsts-to-transcripts ark:- ark,t:- \
        \| int2sym.pl -f 2- ${utf8syms} \> ${dir}/words30_to_utf8.txt
 
    utils/slurm.pl --mem 4G \
        ${dir}/log/utf8_to_words30.log \
        utils/make_lexicon_fst.pl ${dir}/words30_to_utf8.txt \
        \| fstcompile --isymbols=${utf8syms} --osymbols=${dir}/words30.txt --keep_{i,o}symbols=false \
        \| fstarcsort --sort_type=ilabel \
        \| fstclosure --closure_plus     \
        \| fstdeterminizestar \| fstminimize   \
        \| fstarcsort --sort_type=ilabel \> ${dir}/utf8_to_words30_plus.fst

 
    # EXPAND_UTT is an obligatory rewrite rule that accepts anything as input
    # and expands what can be expanded. Note! It does not accept capital letters.
    # Create the fst that works with expand-numbers, using words30.txt as
    # symbol table. NOTE! I changed map_type from rmweight to arc_sum to fix weight problem
    utils/slurm.pl \
        ${dir}/log/expand_to_words30.log \
        fstcompose ${dir}/EXPAND_UTT.fst ${dir}/utf8_to_words30_plus.fst \
        \| fstrmepsilon \| fstmap --map_type=arc_sum \
        \| fstarcsort --sort_type=ilabel \> ${dir}/expand_to_words30.fst &

fi

if [ $stage -le 5 ]; then	    
    # we need to wait for the texts_fsts from stage 3 to be ready
    wait
    # Find out which lines can be rewritten. All other lines are filtered out.
    mkdir -p ${dir}/abbreviated_fsts
    utils/slurm.pl JOB=1:$nj ${dir}/log/abbreviated.JOB.log fsttablecompose --match-side=left ark,s,cs:"gunzip -c ${dir}/texts_fsts.JOB.ark.gz |" ${dir}/ABBREVIATE_forExpansion.fst ark:- \| fsttablefilter --empty=true ark,s,cs:- ark,scp:${dir}/abbreviated_fsts/abbreviated.JOB.ark,${dir}/abbreviated_fsts/abbreviated.JOB.scp
fi

if [ $stage -le 6 ]; then
    if [ -f ${dir}/numbertexts_althingi100.txt.gz ]; then
        mkdir -p ${dir}/.backup
        mv ${dir}/{,.backup/}numbertexts_althingi100.txt.gz
    fi

    # Here the lines in text that are rewriteable are selected, based on key.
    IFS=$' \t\n'
    sub_nnrewrites=$(for j in `seq 1 $nj`; do printf "${dir}/abbreviated_fsts/abbreviated.%s.scp " $j; done)
    # cat $sub_nnrewrites \
    #     | awk '{print $1}' \
    #     | sort -k1 \
    #     | join - ${dir}/texts_no_oovs.txt \ 
    #     | cut -d ' ' -f2- \
    #     | gzip -c > ${dir}/numbertexts.txt.gz
    cat $sub_nnrewrites | awk '{print $1}' | sort -k1 | join - ${dir}/texts_no_oovs.txt | cut -d' ' -f2- > ${dir}/numbertexts.txt

    # Introduce the tag <word> which I will use for words that are in words30.txt but not seen in numbertexts.txt.
    # I need to add a fake line containing the tag so that it will be in numbertexts. I do this because otherwise speeches that
    # contain words that are not seen in numbertexts won't be expanded
    echo -e "þingmaðurinn háttvirti sagði að áform um <word> væru ekkert annað en hneisa" >> ${dir}/numbertexts.txt
    
    # Add the 2013-2016 althingi data since it contains a bunch of manually fixed expanded abbreviations and numbers.
    # Should I rather extract only segments containing expanded abbrs and numbers from the segmented 74 hours of Althingi data?
    # numbertexts.txt based solely on Leipzig has 39M words while the 100 speeches from 2013-16 contain 768824 words, so I think
    # it is ok to just add all of it.
    cat ${dir}/numbertexts.txt <(cut -d" " -f2- ${althdir}100/text) | gzip -c > ${dir}/numbertexts_althingi100.txt.gz
    rm ${dir}/numbertexts.txt
fi

if [ $stage -le 7 ]; then
    for n in 3 5; do
        echo "Building ${n}-gram"
        if [ -f ${dir}/numbertexts_althingi100_${n}g.arpa.gz ]; then
            mkdir -p ${dir}/.backup
            mv ${dir}/{,.backup/}numbertexts_althingi100_${n}g.arpa.gz
        fi

        # KenLM is superior to every other LM toolkit (https://github.com/kpu/kenlm/).
        # multi-threaded and designed for efficient estimation of giga-LMs
        /opt/kenlm/build/bin/lmplz \
	    --skip_symbols \
            -o ${n} -S 70% --prune 0 0 1 \
            --text ${dir}/numbertexts_althingi100.txt.gz \
            --limit_vocab_file <(cut -d " " -f1 ${dir}/words30.txt | egrep -v "<eps>|<unk>") \
            | gzip -c > ${dir}/numbertexts_althingi100_${n}g.arpa.gz
    done  
fi

if [ $stage -le 8 ]; then
    # Get the fst language model. Obtained using the rewritable sentences.
    for n in 3 5; do
        if [ -f ${dir}/numbertexts_althingi100_${n}g.fst ]; then
            mkdir -p ${dir}/.backup
            mv ${dir}/{,.backup/}numbertexts_althingi100_${n}g.fst
        fi

        arpa2fst "zcat ${dir}/numbertexts_althingi100_${n}g.arpa.gz |" - \
            | fstprint \
            | utils/s2eps.pl \
            | fstcompile --{i,o}symbols=${dir}/words30.txt --keep_{i,o}symbols=false \
            | fstarcsort --sort_type=ilabel \
                         > ${dir}/numbertexts_althingi100_${n}g.fst
    done
fi

if [ $stage -le 9 ] && $run_tests; then
    # Let's test the training set, or a subset.

    # Combine, shuffle and subset
    sub_nnrewrites=$(for j in `seq 1 $nj`; do printf "${dir}/abbreviated_fsts/abbreviated.%s.scp " $j; done)
    all_cnt=$(cat $sub_nnrewrites | wc -l)
    test_cnt=$[all_cnt * 5 / 1000]
    mkdir -p ${dir}/test
    cat $sub_nnrewrites | shuf -n $test_cnt | LC_ALL=C sort -k1b,1 > ${dir}/test/abbreviated_test.scp

    utils/split_scp.pl ${dir}/test/abbreviated_test.scp ${dir}/test/abbreviated_test.{1..8}.scp

    for n in 3 5; do
        # these narrowed lines should've had all OOVs mapped to <unk>
        # (so we can do the utf8->words30 mapping, without completely
        # skipping lines with OOVs)
	# Neither of the following is working
        #utils/slurm.pl JOB=1:8 ${dir}/log/expand_test${n}g.JOB.log fsttablecompose --match-side=left scp:${dir}/abbreviated_test.JOB.scp ${dir}/expand_to_words30.fst ark:- \| fsttablecompose --match-side=left ark:- ${dir}/numbertexts_althingi100_${n}g.fst ark:- \| fsts-to-transcripts ark:- ark,t:"| utils/int2sym.pl -f 2- ${dir}/words30.txt > ${dir}/expand_texts_test_${n}g.JOB.txt"
	utils/slurm.pl JOB=1:8 ${dir}/log/expand_test${n}g.JOB.log expand-numbers --word-symbol-table=${dir}/words30.txt scp:${dir}/test/abbreviated_test.JOB.scp ${dir}/expand_to_words30.fst ${dir}/numbertexts_althingi100_${n}g.fst ark,t:${dir}/test/expand_texts_test_${n}g.JOB.txt
    done

    wait
fi

# Extremely messy example usage:
# $ fststringcompile ark:<(echo a " hér eru 852 konur . einnig var sagt frá 852 konum sem geta af sér 852 börn . ") ark:- | fsttablecompose ark,p:- "fstsymbols --clear_isymbols --clear_osymbols ${dir}/ABBREVIATE.fst | fstinvert |" ark:- | fsttablecompose ark:- ${dir}/utf8_to_words30_plus.fst ark:- | sed 's/a //' | fstproject --project_output | fstintersect - ${dir}/numbertexts_2g.fst | fstshortestpath | fstrmepsilon  | fsts-to-transcripts scp:"echo a -|" ark,t:- | int2sym.pl -f 2- ${dir}/words30.txt | cut -d' ' -f2-
# Returns: hér eru átta hundruð fimmtíu og tvær konur . einnig var sagt frá átta hundruð fimmtíu og tveimur konum sem geta af sér átta hundruð fimmtíu og tvö börn .


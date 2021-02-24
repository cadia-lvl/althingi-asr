#!/bin/bash
# Copyright 2012-2014  Johns Hopkins University (Author: Daniel Povey, Yenda Trmal)
# Copyright 2017 Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# begin configuration section.
cmd=run.pl
stage=0
stats=true
beam=6
word_ins_penalty=0.0,0.5,1.0
min_lmwt=6
max_lmwt=16 #20
iter=final
#end configuration section.

echo "$0 $@"  # Print the command line for logging
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;
. ./conf.path.conf # defines $data

if [ $# -ne 3 ]; then
    echo "Usage: local/recognize/score_recognize.sh [--cmd (run.pl|queue.pl...)] <speechname> <lang-dir|graph-dir> <decode-dir>"
    echo " Options:"
    echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
    echo "    --stage (0|1|2)                 # start scoring script from part-way through."
    echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
    echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
    exit 1;
fi

speechname=$1
lang_or_graph=$2
dir=$3

symtab=$lang_or_graph/words.txt

for f in $symtab $dir/lat.1.gz $data/dev_hires/text $data/eval_hires/text; do
    [ ! -f $f ] && echo "score_recognize.sh: no such file $f" && exit 1;
done

echo "$0: scoring with word insertion penalty=$word_ins_penalty"

mkdir -p $dir/scoring_kaldi
grep $speechname $data/dev_hires/text $data/eval_hires/text | cut -d":" -f2- | sort | cut -d" " -f2- | tr "\n" " " | sed 's/.*/'$speechname' &/' > $dir/scoring_$speechname/test_filt.txt || exit 1

if [ $stage -le 0 ]; then

    for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
	mkdir -p $dir/scoring_$speechname/penalty_$wip/log

	$cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring_$speechname/penalty_$wip/log/best_path.LMWT.log \
             lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
             lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
             lattice-best-path --word-symbol-table=$symtab ark:- ark,t:- \| \
             utils/int2sym.pl -f 2- $symtab \| cat '>' $dir/scoring_$speechname/penalty_$wip/LMWT.txt || exit 1;

	for lmwt in $(seq $min_lmwt $max_lmwt); do
            sed -r 's/[^ ]+rad[^ ]+//g' $dir/scoring_$speechname/penalty_$wip/$lmwt.txt | tr "\n" " " \
                | sed -re 's/[[:space:]]+/ /g' -e 's/.*/'$speechname'&/' \
                > $dir/scoring_$speechname/penalty_$wip/$lmwt.tmp \
            && mv $dir/scoring_$speechname/penalty_$wip/$lmwt.tmp $dir/scoring_$speechname/penalty_$wip/$lmwt.txt

	    # I need to remove the text spoken by the speaker of the house if I'm to compare with the reference texts
	    align-text --special-symbol="'***'" ark:$dir/scoring_$speechname/test_filt.txt ark:$dir/scoring_$speechname/penalty_$wip/$lmwt.txt ark,t:$dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt &>/dev/null
            i=2
            refword=$(cut -d" " -f$i $dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt)
            while [ "$refword" = "'***'" ]; do
                i=$[$i+3]
                refword=$(cut -d" " -f$i $dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt)
            done
	    idx1=$[($i-2)/3+2]
	    cut -d" " -f1,$idx1- $dir/scoring_$speechname/penalty_$wip/$lmwt.txt > $dir/scoring_$speechname/penalty_$wip/${lmwt}_trimmed.tmp

            j=$[$(wc -w $dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt | cut -d" " -f1)-1]
	    refword=$(cut -d" " -f$j $dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt)
            while [ "$refword" = "'***'" ]; do
                j=$[$j-3]
                refword=$(cut -d" " -f$j $dir/scoring_$speechname/penalty_$wip/${lmwt}_aligned.txt)
            done
	    idx2=$[($j-2)/3+2+1-$idx1]
	    cut -d" " -f1-$idx2 $dir/scoring_$speechname/penalty_$wip/${lmwt}_trimmed.tmp > $dir/scoring_$speechname/penalty_$wip/${lmwt}_trimmed.txt
	    rm $dir/scoring_$speechname/penalty_$wip/${lmwt}_trimmed.tmp
	done
	
	$cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring_$speechname/penalty_$wip/log/score.LMWT.log \
	     cat $dir/scoring_$speechname/penalty_$wip/LMWT_trimmed.txt \| \
	     compute-wer --text --mode=present \
	     ark:$dir/scoring_$speechname/test_filt.txt  ark,p:- ">&" $dir/wer_LMWT_$wip || exit 1;

    done
fi

if [ $stage -le 1 ]; then

    for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
	for lmwt in $(seq $min_lmwt $max_lmwt); do
	    # adding /dev/null to the command list below forces grep to output the filename
	    grep WER $dir/wer_${lmwt}_${wip} /dev/null
	done
    done | utils/best_wer.sh  >& $dir/scoring_$speechname/best_wer || exit 1

    best_wer_file=$(awk '{print $NF}' $dir/scoring_$speechname/best_wer)
    best_wip=$(echo $best_wer_file | awk -F_ '{print $NF}')
    best_lmwt=$(echo $best_wer_file | awk -F_ '{N=NF-1; print $N}')

    if [ -z "$best_lmwt" ]; then
	echo "$0: we could not get the details of the best WER from the file $dir/wer_*.  Probably something went wrong."
	exit 1;
    fi

    if $stats; then
	mkdir -p $dir/scoring_$speechname/wer_details
	echo $best_lmwt > $dir/scoring_$speechname/wer_details/lmwt # record best language model weight
	echo $best_wip > $dir/scoring_$speechname/wer_details/wip # record best word insertion penalty

	$cmd $dir/scoring_$speechname/log/stats1.log \
	     cat $dir/scoring_$speechname/penalty_$best_wip/${best_lmwt}_trimmed.txt \| \
	     align-text --special-symbol="'***'" ark:$dir/scoring_$speechname/test_filt.txt ark:- ark,t:- \|  \
	     utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" \| tee $dir/scoring_$speechname/wer_details/per_utt || exit 1;

	$cmd $dir/scoring_$speechname/log/stats2.log \
	     cat $dir/scoring_$speechname/wer_details/per_utt \| \
	     utils/scoring/wer_ops_details.pl --special-symbol "'***'" \| \
	     sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 \> $dir/scoring_$speechname/wer_details/ops || exit 1;

	$cmd $dir/scoring_$speechname/log/wer_bootci.log \
	     compute-wer-bootci \
             ark:$dir/scoring_$speechname/test_filt.txt ark:$dir/scoring_$speechname/penalty_$best_wip/${best_lmwt}_trimmed.txt \
             '>' $dir/scoring_$speechname/wer_details/wer_bootci || exit 1;

    fi
fi

# If we got here, the scoring was successful.
# As a  small aid to prevent confusion, we remove all wer_{?,??} files;
# these originate from the previous version of the scoring files
rm $dir/wer_{?,??} 2>/dev/null

exit 0;

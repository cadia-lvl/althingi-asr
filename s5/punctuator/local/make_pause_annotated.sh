#!/bin/bash -e

set -o pipefail

. ./path.sh

# NOTE! This file is just crap. Created to test the second stage training. If I am ever going to use a two stage punctuation model I need to do this properly

if [ $# -ne 3 ]; then
  echo "This script creates pause annotated data for 2nd stage punctuation modelling."
  echo ""
  echo "Usage: $0 <alignment-directory> <input-text-data> <segmented-data>" >&2
  echo "e.g.: $0 exp/tri4_ali punctuation/data/second_stage/althingi.all_sept2017_without_pauses.txt data/all_sept2017_reseg_filtered" >&2
  exit 1;
fi

ali_dir=$1; shift # Should be $exp/tri4_ali according to run.sh
text=$1; shift
reseg=$1
dir=$(dirname $text)
intermediate=$dir/intermediate

lang=$(ls -td $root_lm_modeldir/20*/lang | head -n1)

tmp=$(mktemp -d)
cleanup () {
  rm -rf "$tmp"
}
trap cleanup EXIT

# I have alignment files. Use the alignment information from there to extract the silences
mkdir ${ali_dir}/ctm
utils/slurm.pl JOB=1:100 ${ali_dir}/log/ali_to_ctm.JOB.log \
  ali-to-phones --ctm-output ${ali_dir}/final.mdl \
  ark:"gunzip -c ${ali_dir}/ali.JOB.gz|" - \
  > ${ali_dir}/ctm/ali.JOB.ctm &
wait

egrep "rad[0-9]" ${ali_dir}/log/ali_to_ctm.*.log \
  | cut -d':' -f2 | egrep -v "sp[01]" \
  > $intermediate/merged_ctm_all.txt

# Change from int to sym:
int2sym.pl -f 5 $lang/phones.txt \
  ${intermediate}/merged_ctm_all.txt \
  > ${intermediate}/merged_ctm_all_sym.txt

# Let the phones of each word be in a single line:
sed -re "s:.*? ([^ ]+_I):\1:" -e "s:^[^ ]+ 1 (.*?) ([^ ]+_E):\2 \1:" \
  ${intermediate}/merged_ctm_all_sym.txt \
  | perl -pe 'chomp if /_[BI]/' \
  | awk '{ if ($5 !="sil" && !match($5, /^.*?_S/)) $NF=""; if ($5 !="sil" && !match($5, /^.*?_S/)) $(NF-1)=""; print}' \
  > ${intermediate}/merged_ctm_all_sym_edited.txt

# get rid of channel info and start time of each phone/silence
cut -d" " -f1,4- ${intermediate}/merged_ctm_all_sym_edited.txt \
  > ${intermediate}/merged_ctm_all_sym_edited_cut.txt

# Extract information about position and duration of each silence in a segment
python punctuator/local/extract_silence.py \
  ${intermediate}/merged_ctm_all_sym_edited_cut.txt \
  ${intermediate}/sil_all.txt &

cut -d" " -f1 ${intermediate}/sil_all.txt \
  | sort -u > ${tmp}/sil_uttid.tmp
join -j 1 ${tmp}/sil_uttid.tmp <(sort -u $reseg/text) \
  > ${intermediate}/reseg_text.txt

join -j 1 \
  <(cut -d" " -f1 ${intermediate}/reseg_text.txt) \
  <(sort -u ${intermediate}/sil_all.txt) \
  > ${intermediate}/sil_newdata.txt

# Weave together the silence and text info.
python punctuator/local/add_sil_to_segm.py \
  ${intermediate}/reseg_text.txt \
  ${intermediate}/sil_newdata.txt \
  ${intermediate}/pause_annotated_reseg_text.txt

# I want to do the weaving of silence and punctuation info in parallel
nj=100
IFS=$' \t\n'
split_text=$(for j in `seq 1 $nj`; do printf "${dir}/split%s/reseg_text.%s.txt " $nj $j; done)
utils/split_scp.pl <(egrep -v '^ *$' $infile) $split_text
  
# Next I need to get the punctuation tokens as well. I need to make it such that it reads one speech and respective pause annotated segments at a time.
source venv3/bin/activate
  
utils/slurm.pl JOB=1:$nj $dir/log/segment_matching.JOB.log python punctuator/local/segment_matching.py ${dir}/split${nj}/reseg_text.JOB.txt ${intermediate}/pause_annotated_reseg_text.txt ${dir}/split${nj}/reseg_text_pause_punct.JOB.txt

deactivate

# Join all the output files into one file
cat ${dir}/split${nj}/reseg_text_pause_punct.* | sort -u | egrep -v '^ *$' > ${dir}/reseg_text_pause_punct.txt

# Fixing of the output:
# 1) Not all speeches start in a new line.
# 2) When applying the punctuation model the "%" is included in <NUM> hence I need to collapse them:
sed -re 's/>([^ ]+?-rad)/>\n\1/g' \
    -e 's:<NUM> <sil=[0-9.]+> % (<sil=[0-9.]+>):<NUM> \1:g' \
  < ${dir}/reseg_text_pause_punct.txt \
  | sort -u > ${dir}/reseg_text_pause_punct.edited.txt

# Split up to train, dev and test set
nlines20=$(echo $((($(wc -l ${dir}/reseg_text_pause_punct.edited.txt | cut -d" " -f1)+1)/20)))
sort -R ${dir}/reseg_text_pause_punct.edited.txt | cut -d" " -f2- > ${tmp}/shuffled.tmp

head -n $[$nlines20/2] ${tmp}/shuffled.tmp \
  > ${dir}/althingi.dev.txt || exit 1;
tail -n $[$nlines20/2+1] ${tmp}/shuffled.tmp | head -n $[$nlines20/2] \
  > ${dir}/althingi.test.txt || exit 1;
tail -n +$[$nlines20+1] ${tmp}/shuffled.tmp \
  > ${dir}/althingi.train.txt || exit 1;

exit 0;

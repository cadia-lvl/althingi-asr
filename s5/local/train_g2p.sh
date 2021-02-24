#!/bin/bash -e

# Train a g2p model based on the Althingi projects pron dict, excluding foreign words. See: https://github.com/sequitur-g2p/sequitur-g2p

n=4 # Number of training iterations

. ./path.sh
. utils/parse_options.sh

#date
d=$(date +'%Y%m%d')

dictdir=$root_lexicon
prondict=$(ls -t $dictdir/prondict.* | head -n1)
foreign=$(ls -t $dictdir/foreign_wtrans.* | head -n1)
modeldir=$root_g2p/$d #data/local/g2p
intermediate=$modeldir/intermediate
mkdir -p $modeldir/log $intermediate

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

# Remove foreign words
#comm -23 <(sort -u $prondict) <(sort -u $foreign) > $tmp/g2p_all.txt || exit 1;

# 1) Make a train and a test lex
#    Randomly select 200 words for a test set
#sort -R $tmp/g2p_all.txt > ${tmp}/shuffled_prondict.tmp
#head -n 200 ${tmp}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_test.${d}.txt
#tail -n +201 ${tmp}/shuffled_prondict.tmp | sort > ${dictdir}/g2p_train.${d}.txt

# 2) Train a model
#    Train the first model, will be rather poor because it is only a unigram
utils/slurm.pl --mem 4G ${modeldir}/log/g2p_1.${d}.log g2p.py --train ${dictdir}/g2p_train.${d}.txt --devel 5% --encoding="UTF-8" --write-model ${intermediate}/g2p_1.${d}.mdl || exit 1;

#    To create higher order models you need to run g2p.py again a few times
for i in `seq 1 $[$n-1]`; do
    utils/slurm.pl --mem 8G --time 0-08 ${modeldir}/log/g2p_$[$i+1].${d}.log g2p.py --model ${intermediate}/g2p_${i}.${d}.mdl --ramp-up --train ${dictdir}/g2p_train.${d}.txt --devel 5% --encoding="UTF-8" --write-model ${intermediate}/g2p_$[$i+1].${d}.mdl || exit 1;
done

# 3) Evaluate the model
#    To find out how accurately your model can transcribe unseen words type:
g2p.py --model ${intermediate}/g2p_${n}.${d}.mdl --encoding="UTF-8" --test ${dictdir}/g2p_test.${d}.txt || exit 1;

# If happy with the model I would rename it to g2p.mdl
mv ${intermediate}/g2p_${n}.mdl ${modeldir}/g2p.mdl

# 4) Transcribe new words.
#   Prepare a list of words you want to transcribe as a simple text
#   file words.txt with one word per line (and no phonemic
#   transcription), then type:
# g2pmodeldir=$(ls -td $root_g2p/2* | head -n1)
# local/transcribe_g2p.sh $g2pmodeldir/g2p.mdl words.txt > transcribed_words.txt
# The above script contains: g2p.py --apply $wordlist --model $model --encoding="UTF-8"

exit 0;

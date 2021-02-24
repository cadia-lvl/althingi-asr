#!/bin/bash -e

maxtime=1 # Time in days from the decoding graph creation

. ./path.sh
. ./local/utils.sh
. ./local/array.sh

asrlm_modeldir=/jarnsmidur/asr-lm_models # This is the LM server model dir mounted on the decoding server
decode_modeldir=$root_modeldir
decode_lmdir=$root_lm_modeldir
decode_textnormdir=$root_text_norm_modeldir
decode_punctuation=$root_punctuation_modeldir
decode_paragraph=$root_paragraph_modeldir
trans_out=$root_transcription_dir
lirfa_audio=$root_lirfa_audio
bundle=$root_bundle

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

testout=temp/cp_to_decoding #$tmp # Used when testing whether the new ASR version, i.e. latest, is ok.
mkdir -p $testout

# Check if a new decoding graph was created at least an hour ago
# NOTE! I find this a bit uncomfortable. Is it possible to rather get a message when local/new_speeches/update_LM_and_graph.sh has finished?
new_HCLG=$(find $asrlm_modeldir/acoustic_model/chain/5.4/tdnn_*/*/graph_3gsmall/HCLG.fst -cmin +60 -ctime -$maxtime | tail -n1)
if [ -z "$new_HCLG" ]; then
  echo "No new decoding graph found, exit the script.";
  exit 0;
fi

# Copy the new LMs and decoding graph from the LM server to the decoding server
# Newest AM dir
am_modeldir=$(ls -td $asrlm_modeldir/acoustic_model/*/*/*/* | head -n1)

# The pathnames are not the same in the beginning, between the two servers, cut away what is different
n=$(echo $asrlm_modeldir | egrep -o '/' | wc -l)
am_date=$(basename $am_modeldir)
middle_ampath=$(dirname $am_modeldir | cut -d'/' -f$[$n+2]-)
decode_amdir=$decode_modeldir/$middle_ampath

# Newest language models
lm_modeldir=$(cat $am_modeldir/lminfo)
lm_date=$(basename $lm_modeldir)
middle_lmpath=language_model

if [ -d $decode_lmdir/$lm_date ]; then
  echo "Language model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new language models"
  mkdir -p $decode_lmdir
  cp -r $asrlm_modeldir/$middle_lmpath/$lm_date $decode_lmdir
fi
wait;

if [ -d $decode_amdir/$am_date ]; then
  echo "Acoustic model dir already exists on the decoding server"
  echo "I won't overwrite it"
else
  echo "Copy the new acoustic model directory"
  mkdir -p $decode_amdir
  cp -r $asrlm_modeldir/$middle_ampath/$am_date $decode_amdir
  ln -sf $decode_lmdir/$lm_date $decode_amdir/$am_date/lmdir
fi

# Check if there are new versions of the Thrax denormalization FSTs or punct. or paragraph models
# New text de-normalization FSTs
newest_lm_textnorm=$(ls -td $asrlm_modeldir/text_norm/2* | head -n1)
newest_decode_textnorm=$(ls -td $decode_textnormdir/2* | head -n1)
if [ $newest_lm_textnorm -nt $newest_decode_textnorm ]; then
  echo "The LM server contains newer text normalization FSTs"
  cp -r $newest_lm_textnorm $decode_textnormdir
fi

# Comment out since not yet possible to update these models on the LM server
# # New punctuation and paragraph model
# newest_lm_punct=$(ls -td $asrlm_modeldir/punctuation/2* | head -n1)
# newest_decode_punct=$(ls -td $decode_punctuation/2* | head -n1)
# if [ $newest_lm_punct -nt $newest_decode_punct ]; then
#   echo "The LM server contains a newer punctuation model"
#   cp -r $newest_lm_punct $decode_punctuation
# fi

# newest_lm_paragraph=$(ls -td $asrlm_modeldir/paragraph/2* | head -n1)
# newest_decode_paragraph=$(ls -td $decode_paragraph/2* | head -n1)
# if [ $newest_lm_paragraph -nt $newest_decode_paragraph ]; then
#   echo "The LM server contains a newer paragraph model"
#   cp -r $newest_lm_paragraph $decode_paragraph
# fi

echo "Update latest"
d=$(basename $(ls -td $bundle/20* | head -n1))
if [ $d = $am_date ]; then
  echo "The latest bundle is already from $am_date"
  echo "I won't overwrite it"
else
  local/update_latest.sh || error 1 "ERROR: update_latest.sh failed"
fi

echo "Test decoding three speeches using the new ASR version"
fail=0
empty=0
for audio in $(ls -t $lirfa_audio | head -n3); do 
  speechname="${audio%.*}"
  reftext=$trans_out/$speechname/$speechname.txt
  if [ -s $lirfa_audio/$audio -a -s $reftext ]; then

    local/recognize/recognize.sh --trim 0 --rnnlm false $lirfa_audio/$audio $testout &> $testout/$speechname.log

    echo "Compare it with an earlier transcription"
    compute-wer --text --mode=present ark:<(tr "\n" " " < $reftext | sed -e '$a\' | sed -r 's:^.*:1 &:') ark,p:<(tr "\n" " " < $testout/$speechname/$speechname.txt | sed -e '$a\' | sed -r 's:^.*:1 &:') >& $testout/edit_dist_$speechname
    WEDcomp=$(grep WER $testout/edit_dist_$speechname | utils/best_wer.sh | cut -d' ' -f2)
    WEDcomp_int=${WEDcomp%.*}
    if [ $WEDcomp_int -gt 10 ]; then
      echo "FAILED: Bad comparison between new and old transcription of $speechname."
      fail=$[$fail+1]
    fi
  else
    echo "$lirfa_audio/$audio is empty or $reftext is non-existent"
    empty=$[$empty+1]
  fi
done

if [ $fail -eq 3 ]; then
  echo "FAILED: Bad comparison for all speeches"
  echo "Maybe something is wrong with the new ASR version"
  echo "Revert to using the old one"
  second_newest=$(ls -td $bundle/2* | head -n2 | tail -n1)
  ln -s $second_newest $bundle/latest
  exit 1;
elif [ $empty -eq 3 ]; then
  echo "FAILED: Non-existent audio or reference text for all speeches"
  echo "Something is wrong"
  exit 1;
fi

rm -r $testout
echo "Done"

exit 0;

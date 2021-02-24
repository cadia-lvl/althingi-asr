#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Prepare a directory on Kaldi format, containing audio data and some auxiliary info.

stage=-1

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh || exit 1;
. local/utils.sh
. local/array.sh

if [ $# != 3 ]; then
  echo "Usage: local/recognize/prep_audiodata.sh [options] <audiofile> <metadata> <outputdir>" >&2
  echo "e.g.: local/recognize/prep_audiodata.sh data/audio/speech.mp3 data/speech/meta.txt data/speech" >&2
  exit 1;
fi

speechfile=$1
speechname=$(basename "$speechfile")
extension="${speechname##*.}"
speechname="${speechname%.*}"
meta=$2
dir=$3

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

encoding=$(file -i ${meta} | cut -d" " -f3)
if [[ "$encoding" == "charset=iso-8859-1" ]]; then
    iconv -f ISO-8859-1 -t UTF-8 ${meta} > $tmp/meta_prep_audio.tmp && mv $tmp/meta_prep_audio.tmp ${meta}
fi

# SoX converts all audio files to an internal uncompressed format before performing any audio processing
samplerate=16000
wav_cmd="sox -t$extension - -c1 -esigned -r$samplerate -G -twav - "

IFS=$'\n' # Split on new line

if [ $stage -le 0 ]; then

    # Extract the speaker info (when using old speeches)
    grep "$speechname" ${meta} | tr "," "\t" > $tmp/spkname_speechname.tmp
    spkID=$(cut -f1 $tmp/spkname_speechname.tmp | perl -pe 's/[ \.]//g')

    # Extract the speaker info (to use with new speeches). What will be the format of the new meta files? F.ex. comma separated with speakers name in 1st col?
    #spkID=$(cut -f1 ${meta} | perl -pe 's/[ \.]//g')
    
    echo "a) utt2spk" # Connect each speech ID to a speaker ID.
    printf "%s %s\n" ${spkID}-${speechname} ${spkID} | tr -d $'\r' > ${dir}/utt2spk

    # Make a helper file with mapping between the speechnames and uttID
    echo -e ${speechname} ${spkID}-${speechname} | tr -d $'\r' | LC_ALL=C sort -n > $tmp/speechname_uttID.tmp
    
    echo "b) wav.scp" # Connect every speech ID with an audio file location.
    echo -e ${spkID}-${speechname} $wav_cmd" < "$(readlink -f ${speechfile})" |" | tr -d $'\r' > ${dir}/wav.scp

    echo "c) spk2utt"
    utils/utt2spk_to_spk2utt.pl < ${dir}/utt2spk > ${dir}/spk2utt
fi

if [ $stage -le 1 ]; then
    echo "Extracting features"
    steps/make_mfcc.sh \
	--nj 1 \
	--mfcc-config conf/mfcc.conf \
	--cmd "$train_cmd"           \
	${dir} || exit 1;

    echo "Computing cmvn stats"
    steps/compute_cmvn_stats.sh ${dir} || exit 1;
fi

if [ $stage -le 2 ]; then
    
    echo "Make sure all files are created and that everything is sorted"
    utils/validate_data_dir.sh --no-text ${dir} || utils/fix_data_dir.sh ${dir}
fi

IFS=$' \t\n'
exit 0;


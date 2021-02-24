#!/bin/bash -e

set -o pipefail

audio_only=false
xml_only=false
check_all_files=false

. ./path.sh # $data defined here
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

if [ $# -ne 3 ]; then
  echo "This script extract audio files and corresponding transcripts from althingi.is given the start and finish session numbers."
  echo ""
  echo "Usage: $0 <path-to-corpus> <first session> <last session>" >&2
  echo "e.g.: $0 /data/local/corpus_20180612 132 148" >&2
  exit 1;
fi

# $data is defined in path.conf
corpusdir=$1; shift #/data/althingi/corpus_jun2018
start=$1; shift #146
stop=$1; #148

datadir=$data/data_extraction/althingi_info
mkdir -p $corpusdir/{audio,text_endanlegt} $datadir

tmp=$(mktemp -d)
cleanup () {
  rm -rf "$tmp"
}
trap cleanup EXIT

# Extract info about the speeches from althingi.is
srun --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_info.php $datadir/thing $start $stop &> $datadir/log/scraping_althingi_info.log" || error 1 $LINENO "scrape_althingi_info.php failed";

#Parse the info
source venv3/bin/activate
for session in $(seq $start $stop); do
  if [ $session -gt 146 ]; then
    python local/data_extraction/parsing_xml_new.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_mp3_xml_all.txt || error 1 $LINENO "parsing_xml_new.py failed";
  else
    python local/data_extraction/parsing_xml.py ${datadir}/thing${session}.txt ${datadir}/thing${session}_mp3_xml_all.txt || error 1 $LINENO "parsing_xml.py failed";
  fi
  sort -u ${datadir}/thing${session}_mp3_xml_all.txt > $tmp/tmp && mv $tmp/tmp ${datadir}/thing${session}_mp3_xml_all.txt || error 14 $LINENO ${error_array[14]};
done
deactivate

# All speeches already in training and testing sets:
if [ $xml_only = false ]; then
  ls ${corpusdir}/audio/ | cut -d"." -f1 | sort -u \
  > $tmp/ids_in_use_audio || error 14 $LINENO ${error_array[14]};
fi

if [ $audio_only = false ]; then
  ls ${corpusdir}/text_endanlegt/ | cut -d"." -f1 | sort -u \
  > $tmp/ids_in_use_text || error 14 $LINENO ${error_array[14]};
fi

if $check_all_files ; then
  cat $root_intermediate/all*/text | cut -d" " -f1 | cut -d"-" -f2 \
    | sort -u > $tmp/ids_in_use || error 14 $LINENO ${error_array[14]};
  cat $tmp/ids_in_use $tmp/ids_in_use_audio | sort -u > $tmp/tmp && mv $tmp/tmp $tmp/ids_in_use_audio
  cat $tmp/ids_in_use $tmp/ids_in_use_text | sort -u > $tmp/tmp && mv $tmp/tmp $tmp/ids_in_use_text
fi

# Extract the ids of speeches that we don't already have in our data
if [ $xml_only = false ]; then
  if [ -s $tmp/ids_in_use_audio ]; then
    # The perl command removes newline at EOF
    for session in $(seq $start $stop); do
      grep -f $tmp/ids_in_use_audio ${datadir}/thing${session}_mp3_xml_all.txt \
           > $tmp/used_audio.tmp || error 14 $LINENO ${error_array[14]};
      comm -13 <(sort -u $tmp/used_audio.tmp) <(sort -u ${datadir}/thing${session}_mp3_xml_all.txt) \
        | perl -pe 'chomp if eof' \
               > ${datadir}/thing${session}_mp3_xml_new_audio.txt \
        || error 14 $LINENO ${error_array[14]};
    done
  else
    perl -pe 'chomp if eof' ${datadir}/thing${session}_mp3_xml_all.txt \
         > ${datadir}/thing${session}_mp3_xml_new_audio.txt \
      || error 13 $LINENO ${error_array[13]};
  fi
fi

if [ $audio_only = false ]; then
  if [ -s $tmp/ids_in_use_text ]; then
    # Make sure all the files contain xml files and remove newline at EOF
    for session in $(seq $start $stop); do
      grep -f $tmp/ids_in_use_text ${datadir}/thing${session}_mp3_xml_all.txt > $tmp/used_text.tmp
      comm -13 <(sort -u $tmp/used_text.tmp) <(sort -u ${datadir}/thing${session}_mp3_xml_all.txt) \
        | awk -F $'\t' 'NF==4{print}{}' | perl -pe 'chomp if eof' \
       > ${datadir}/thing${session}_mp3_xml_new_text.txt || error 14 $LINENO ${error_array[14]};
    done
  else
    awk -F $'\t' 'NF==4{print}{}' ${datadir}/thing${session}_mp3_xml_all.txt \
      | perl -pe 'chomp if eof' > ${datadir}/thing${session}_mp3_xml_new_text.txt \
      || error 13 $LINENO ${error_array[13]};
  fi
fi

if $audio_only ; then
  # Download the corresponding audio
  for session in $(seq $start $stop); do
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_mp3.php ${datadir}/thing${session}_mp3_xml_new_audio.txt ${corpusdir}/audio &> ${datadir}/log/extraction_thing${session}_audio.log" || error 1 $LINENO "scrape_althingi_mp3.php failed";
  done
elif $xml_only ; then
  for session in $(seq $start $stop); do
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml.php ${datadir}/thing${session}_mp3_xml_new_text.txt ${corpusdir}/text_endanlegt &> ${datadir}/log/extraction_thing${session}_xml.log" || error 1 $LINENO "scrape_althingi_xml.php failed";
  done
else
  # Download the corresponding audio and xml
  for session in $(seq $start $stop); do
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_mp3.php ${datadir}/thing${session}_mp3_xml_new_audio.txt ${corpusdir}/audio &> ${datadir}/log/extraction_thing${session}_audio.log" || error 1 $LINENO "scrape_althingi_mp3.php failed";
    srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml.php ${datadir}/thing${session}_mp3_xml_new_text.txt ${corpusdir}/text_endanlegt &> ${datadir}/log/extraction_thing${session}_xml.log" || error 1 $LINENO "scrape_althingi_xml.php failed";
    #awk -F $'\t' 'NF==4{print}{}' ${datadir}/thing${session}_mp3_xml_new.txt | perl -pe 'chomp if eof' > ${datadir}/thing${session}_mp3_with_xml.txt
    #srun --time=0-12 --nodelist=terra sh -c "php local/data_extraction/scrape_althingi_xml_mp3.php ${datadir}/thing${session}_mp3_with_xml.txt ${corpusdir}/audio ${corpusdir}/text_endanlegt &> ${datadir}/log/extraction_thing${session}.log" &
  done
fi

# I got almost 12000 errors of the form: <html><body>Það hefur komið upp villa. Reyndu aftur síðar.</body></html>, error status 403. Fetching them again worked for a lot of them.

exit 0;

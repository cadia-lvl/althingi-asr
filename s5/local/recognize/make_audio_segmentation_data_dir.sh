#!/bin/bash

# This script is based on steps/cleanup/make_segmentation_data_dir.sh
# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0


# Begin configuration section.
min_seg_length=2
min_sil_length=0.5
# End configuration section.

set -e

echo "$0 $@"

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "This script takes in a file, which contains info on start,"
  echo "end and duration of silences in an audio file, and works out a"
  echo "segmentation and creates a new data directory for the segmentation."
  echo ""
  echo "Usage: $0 [options] <silence-file> <old-data-dir> <new-data-dir>"
  echo " e.g.: $0 data/recognize/radXXX/silence_15dB.tmp data/recognize/radXXX \\"
  echo "                          data/recognize/radXXX_segm"
  echo "Options:"
  echo "    --min-seg-length        # minimum length of segments"
  echo "    --min-sil-length        # minimum length of silence as split point"
  exit 1;
fi

silence_file=$1
old_data_dir=$2
new_data_dir=$3

for f in $silfile $old_data_dir/utt2spk $old_data_dir/wav.scp; do
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

mkdir -p $new_data_dir
cp -f $old_data_dir/wav.scp $new_data_dir
[ -f old_data_dir/spk2gender ] &&  cp -f $old_data_dir/spk2gender $new_data_dir

echo "Create the segmentation."
local/recognize/create_segments_from_silence.pl \
  --min-seg-length $min_seg_length \
  --min-sil-length $min_sil_length \
  $silence_file $new_data_dir/segments || exit 1;

echo "Create the new utt2spk and spk2utt files."
cat $old_data_dir/utt2spk | perl -e '
  ($segm_file, $utt2spk_file_out) = @ARGV;
  open(SEG, "<$segm_file") || die "Error: fail to open $segm_file\n";
  open(UO, ">$utt2spk_file_out") ||
    die "Error: fail to open $utt2spk_file_out\n";
  while (<STDIN>) {
    chomp;
    @col = split;
    @col == 2 || die "Error: bad line $_\n";
    $utt2spk{$col[0]} = $col[1];
  }
  while (<SEG>) {
    chomp;
    @col = split;
    @col == 4 || die "Error: bad line $_\n";
    my $uttID = ($col[0] =~ /^([^_]+)_\d+/)[0]; # Extract what comes before the _0000xx
    #if (defined($wav2spk{$col[1]})) {
    #  print "in if defined\n";
    #  $wav2spk{$col[1]} == $utt2spk{$uttID} ||
    #    die "Error: multiple speakers detected for wav file $col[1]\n";
    #} else {
    $wav2spk{$col[1]} = $utt2spk{$uttID};
    #  print "uttID = $uttID\n";
    #  print "col[0] = $col[0]\n";
    #  print "col[1] = $col[1]\n";
    #  print "wav2spk{$col[1]} = $wav2spk{$col[1]}\n";
    print UO "$col[0] $wav2spk{$col[1]}\n";
    #}
  } ' $new_data_dir/segments $new_data_dir/utt2spk

utils/utt2spk_to_spk2utt.pl $new_data_dir/utt2spk > $new_data_dir/spk2utt

utils/fix_data_dir.sh $new_data_dir

exit 0;

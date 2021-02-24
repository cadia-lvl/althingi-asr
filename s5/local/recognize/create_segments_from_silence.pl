#!/usr/bin/env perl

# Built on steps/cleanup/create_segments_from_ctm.pl
# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

use strict;
use warnings;
use Getopt::Long;

# $SIG{__WARN__} = sub { $DB::single = 1 };

my $Usage = <<'EOU';
This script takes in a file, which contains info on start, end and duration 
of silences in an audio file, and creates a segments file.

A minimum segment length is required before splitting on a silence and the
silence must also be of a minimum length to be used for splitting.

Usage: local/recognize/create_segments_from_silence.pl [options] \
                              <silence info from ffmpeg> <segments>
 e.g.: local/recognize/create_segments_from_silence.pl \
          --min-seg-length $min_seg_length \
          --min-sil-length $min_sil_length \
          $silence_file $new_data_dir/segments

Allowed options:
  --min-seg-length  : Minimum length of new segments (default = 2.0)
  --min-sil-length  : Minimum length of silence as split point (default = 0.5)
EOU

my $min_seg_length = 3.0;
my $min_sil_length = 0.5;
GetOptions(
  'min-seg-length=f' => \$min_seg_length,
  'min-sil-length=f' => \$min_sil_length);
    
if (@ARGV != 2) {
  die $Usage;
}

my ($silfile_in, $segments_out) = @ARGV;

open(SI, "<$silfile_in") || die "Error: fail to open $silfile_in\n";
open(my $SO, ">$segments_out") || die "Error: fail to open $segments_out\n";

# Prints the current segment to file.
sub PrintSegment {
  my ($wav_id, $seg_start, $seg_end, $seg_count, $SO) = @_;

  if ($seg_start > $seg_end) {
    return -1;
  }

  $seg_start = sprintf("%.2f", $seg_start);
  $seg_end = sprintf("%.2f", $seg_end);
  my $seg_id = $wav_id . "_" . sprintf("%05d", $seg_count);
  print $SO "$seg_id $wav_id $seg_start $seg_end\n";
  return 0;
}

# Processes each wav file.
sub ProcessWav {
  my ($min_seg_length, $min_sil_length,
      $current_audio, $SO) = @_;

  my $wav_id = $current_audio->[0]->[0];
  defined($wav_id) || die "Error: empty wav section\n";

  my $audio_dur = $current_audio->[0]->[1];

  my $current_seg_count = 0;
  my $current_time = 0;
  my $sil_dur = 0;
  my $i = 0;
  for ($i = 0; $i < scalar(@{$current_audio}); $i++) {
    my $sil_start = $current_audio->[$i]->[3];
    $sil_dur = $current_audio->[$i]->[7];
    if ($sil_start - $current_time > $min_seg_length && $sil_dur > $min_sil_length) {

      # Create segment
      my $new_time = $sil_start + $sil_dur / 2.0;
      my $ans = PrintSegment($wav_id, $current_time, $new_time,
                             $current_seg_count, $SO);
      $current_seg_count += 1 if ($ans != -1);
      # Update current_time
      $current_time = $new_time;
    }
  }
  # Last segment (NOTE! I subtract 0.1 from the total length of the audio because 
  # I see that ffmpeg and soxi duration measurements can vary. I've seen difference up to 0.06 sec)
  if ($current_time + $sil_dur / 2.0 < $current_audio->[0]->[1] - 1.0) {
    my $ans = PrintSegment($wav_id, $current_time, $current_audio->[0]->[1] - 0.1,
                           $current_seg_count, $SO);
  }
}

# Reads the ctm file and creates the segmentation.
my $previous_wav_id = "";
my @current_wav = ();
while (<SI>) {
  chomp;
  my @col = split;
  @col == 8 || die "Error: bad line $_\n";
  if ($previous_wav_id eq $col[0]) {   
    # Load in everything about one audio
    push(@current_wav, \@col);
  } else {
    if (@current_wav > 0) {
      # Process all info on that audio
      #my @current_wav_silence = ();
      #InsertSilence(\@current_wav, \@current_wav_silence);
      ProcessWav($min_seg_length, $min_sil_length,
                 \@current_wav, $SO);
    }
    # Start loading info on audio
    @current_wav = ();
    push(@current_wav, \@col);
    $previous_wav_id = $col[0];
  }
}

# The last wav file.
if (@current_wav > 0) {
  ProcessWav($min_seg_length, $min_sil_length,
             \@current_wav, $SO);
}

close(SI);
close($SO);

#!/usr/bin/env python
# coding: utf-8

import codecs
import sys
import re
import urllib
import os

def getMP3(stamps,furls):
    """Download an mp3 file from the Althingi website given 
    the date of the speech, plus the start and end times"""

    for line in stamps:
        _,date,start,_,end = line.split()
        mp3url = 'http://www.althingi.is/raedur/?start=' + date + 'T' + start + '&end=' + date + 'T' + end
        furls.write(mp3url + '\n') 

        date = re.sub('-', '', date)
        start = re.sub(':', '', start)
        end = re.sub(':', '', end)

        # The uttID
        rad = 'rad' + date + 'T' + start

        # Put the audio files in the same dir as the urls file
        cwd = os.getcwd()
        path=os.path.dirname(furls.name)
        audio_file_name = cwd + "/" + path + "/" + rad + '.mp3'

        # Extract the audio
        urllib.urlretrieve(mp3url, audio_file_name)


if __name__ == "__main__":
    with codecs.open(sys.argv[2],'a',encoding='utf-8') as furls:
        with codecs.open(sys.argv[1],'r',encoding='utf-8') as fstamps:
            stamps = fstamps.read().splitlines()

            getMP3(stamps,furls)

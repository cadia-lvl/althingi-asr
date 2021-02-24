#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

import sys
import re
from pyxdameraulevenshtein import damerau_levenshtein_distance

def CorrectSpelling(speech,vocab_init,vocab_endanlegt):
    """Use Damerau Levenshtein distance to correct the spelling
    in the intermediate texts"""

    for word in vocab_init:
        #word_dict={}
        replaced = 0
        for w_endanlegt in vocab_endanlegt:
            #dist=MinEditDist(word,w_endanlegt)
            dist = damerau_levenshtein_distance(word, w_endanlegt)
            if dist == 1:
                speech = re.sub(r"\b%s\b" % word,w_endanlegt,speech)
                replaced = 1
                break
        #     else:
        #         word_dict[dist]=w_endanlegt
                
        # # Need to find the min dist and substitute if not already substituted
        # if replaced == 0:
        #     speech = re.sub(r"\b%s\b" % word,word_dict[min(word_dict,key=int)],speech)
            
    return speech

if __name__ == "__main__":

    # speech = sys.argv[1] # sys.argv[1] is a shell variable
    with open(sys.argv[2],'a',encoding='utf-8') as fout:
        with open(sys.argv[1],'r',encoding='utf-8') as fspeech:
            speech = fspeech.read().strip()
            with open(sys.argv[3],'r',encoding='utf-8') as fvoc_init:
                vocab_init = fvoc_init.read().splitlines()
                with open(sys.argv[4],'r',encoding='utf-8') as fvoc_end:
                    vocab_endanlegt  = fvoc_end.read().splitlines()
                    speech_fixed = CorrectSpelling(speech,vocab_init,vocab_endanlegt)
                    print(speech_fixed, file=fout)

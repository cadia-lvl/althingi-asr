#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Find the concordance of new words (+-5 word context)

import os.path
import sys

def load(filename):
    """Read in a two column file and drop the 2nd col"""
    vocab = [] 
    for line in filename: 
        vocab.append(line.split('\t')[0]) 
    return vocab

def find_concordance(textlist, vocabulary):

    l = len(textlist) 
    d=[]
    for word in vocabulary:
        i=[word]
        pos = textlist.index(word) 
        if pos < 6 and pos > l-7: 
            i.append(' '.join(textlist))
        elif pos < 6: 
            i.append(' '.join(textlist[:pos+7]))
        elif pos > l-7: 
            i.append(' '.join(textlist[pos-6:]))
        else: 
            i.append(' '.join(textlist[pos-6:pos+6]))
        d.append('\t'.join(i))
    return d

if __name__ == "__main__":

    # The arguments are the input text, vocabulary and output files
    with open(sys.argv[3],'w') as fout:
        with open(sys.argv[1],'r') as textin:
            with open(sys.argv[2],'r') as fvoc:
                textlist = textin.read().split()[1:] # Skip the uttID
                vocab = load(fvoc) # Drop the phonetic transcriptions
                concordance = find_concordance(textlist, vocab)
                fout.write('\n'.join(concordance))

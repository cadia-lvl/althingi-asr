#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Find the concordance of new words

# NOTE! mini_althingi_corpus.concordance(word) writes to stdout so pipe output to file
# I commented the nltk part out for now, since it is VERY slow. 

import os.path
import sys
# import nltk
# #need these to be installed
# from nltk.corpus import PlaintextCorpusReader
# from nltk.corpus import stopwords
# from urllib import request

def load(filename):
    """Read in a two column file and drop the 2nd col"""
    vocab = [] 
    with open(filename, 'r') as f: 
        for line in f: 
            vocab.append(line.split('\t')[0]) 
    return vocab

def find_concordance(textfile, vocabulary):
    # textdir = os.path.dirname(textfile)
    # textname = os.path.basename(textfile)
    # wordlists = PlaintextCorpusReader(textdir,textname)
    # mini_althingi_corpus = nltk.Text(wordlists.words())
    # #show the concordance of any new vocab found in the speech
    # for word in vocabulary:
    #     print ("\n{}".format(word))
    #     mini_althingi_corpus.concordance(word)

    l = len(textlist)
    for word in vocabulary:
        print ("\n{}".format(word))
        pos = textlist.index(word)
        if pos < 5 and pos > l-6:
            print(' '.join(textlist))
        elif pos < 5:
            print(' '.join(textlist[:pos+6]))
        elif pos > l-6:
            print(' '.join(textlist[pos-5:]))
        else:
            print(' '.join(textlist[pos-5:pos+6]))
   
if __name__ == "__main__":

    if len(sys.argv) > 1:
        textfile = os.path.abspath(sys.argv[1])
    else:
        sys.exit("'textfile' argument missing!")

    if len(sys.argv) > 2:
        vocabfile = os.path.abspath(sys.argv[2])
    else:
        sys.exit("'vocabfile' argument missing!")

    vocab = load(vocabfile)
    with open(textfile,'r') as textin:
        textlist = textin.read().split()[1:] # Skip the uttID
        concordance = find_concordance(textlist, vocab)
        
    #concordance = find_concordance(textfile, vocab)

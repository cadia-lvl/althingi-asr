# coding: utf-8

from __future__ import division
from nltk.tokenize import word_tokenize

import os
import codecs
import re
import sys
import nltk # I had to add these lines, but only needed once
nltk.download('punkt')

NUM = '<NUM>'

EOS_PUNCTS = {".": ".PERIOD", "?": "?QUESTIONMARK", "!": "!EXCLAMATIONMARK", ":": ":COLON"}
#INS_PUNCTS = {",": ",COMMA", ";": ";SEMICOLON", ":": ":COLON", "-": "-DASH"}
INS_PUNCTS = {",": ",COMMA", ";": ";SEMICOLON"}

forbidden_symbols = re.compile(r"[\[\]\(\)\\\>\<\=\+\_\*]")
numbers = re.compile(r"\d")
#multiple_punct = re.compile(r'([\.\?\!\,\:\;\-])(?:[\.\?\!\,\:\;\-]){1,}')
multiple_punct = re.compile(r'([\.\?\!\,\:\;])(?:[\.\?\!\,\:\;]){1,}')

is_number = lambda x: len(numbers.sub("", x)) / len(x) < 0.6

def untokenize(line):
    #return line.replace(" '", "'").replace(" n't", "n't").replace("can not", "cannot")
    return line

def skip(line):

    last_symbol = line[-1]
    if not last_symbol in EOS_PUNCTS:
        return True

    if forbidden_symbols.search(line) is not None:
        return True

    return False

def process_line(line):

    tokens = word_tokenize(line)
    output_tokens = []

    for token in tokens:

        if token in INS_PUNCTS:
            output_tokens.append(INS_PUNCTS[token])
        elif token in EOS_PUNCTS:
            output_tokens.append(EOS_PUNCTS[token])
        elif is_number(token):
            output_tokens.append(NUM)
        else:
            output_tokens.append(token)

    return untokenize(" ".join(output_tokens) + " ")

skipped = 0

with codecs.open(sys.argv[2], 'w', 'utf-8') as out_txt:
    with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

        for line in text:

            line = line.replace("\"", "").strip()
            line = multiple_punct.sub(r"\g<1>", line)
            first_space = line.find(" ")
            uttid, transcript = line[:first_space], line[first_space+1:]
            
            if skip(transcript):
                skipped += 1
                continue

            transcript = process_line(transcript)

            out_txt.write(' '.join([uttid,transcript]) + '\n')

print "Skipped %d lines" % skipped

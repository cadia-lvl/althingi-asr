# coding: utf-8

from nltk.tokenize import word_tokenize

import os
import codecs
import re
import sys

EOS_PUNCTS = {".PERIOD":".", "?QUESTIONMARK":"?"}
INS_PUNCTS = {",COMMA":",", ":COLON":":"}

def process_line(line):

    tokens = word_tokenize(line)
    output_tokens = []

    for token in tokens:

        if token in INS_PUNCTS:
            output_tokens.append(INS_PUNCTS[token])
        elif token in EOS_PUNCTS:
            output_tokens.append(EOS_PUNCTS[token])
        else:
            output_tokens.append(token)

    return " ".join(output_tokens) + " "

with codecs.open(sys.argv[2], 'w', 'utf-8') as out_txt:
    with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

        for line in text:

            line = process_line(line)

            out_txt.write(line + '\n')

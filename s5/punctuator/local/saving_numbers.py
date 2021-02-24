# coding: utf-8

# NOTE I can not use nltk's word_tokenize since the input does not contain punctuations
# and word_tokenize takes ordinal periods as EOS periods if a number comes after.

from __future__ import division
from nltk.tokenize import word_tokenize

import codecs
import re
import sys

NUM = '<NUM>'
numbers = re.compile(r"\d")
is_number = lambda x: len(numbers.sub("", x)) / len(x) < 0.6

def process_line(line):
    
    tokens = line.split()
    output_tokens = []
    num_list = []

    for token in tokens:
        if is_number(token):
            output_tokens.append(NUM)
            num_list.append(token)
        else:
            output_tokens.append(token)

    return [" ".join(output_tokens) + " ", '\n'.join(num_list)]

with codecs.open(sys.argv[3], 'w', 'utf-8') as num_txt:
    with codecs.open(sys.argv[2], 'w', 'utf-8') as out_txt:
        with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

            
            for line in text:

                line, num = process_line(line)

                out_txt.write(line + '\n')
                if len(num) > 0:
                    num_txt.write(num + '\n')


#!/usr/bin/python3

# Takes as input per_spk_err_sorted, which is obtained in the following way:
# perl -ne 'BEGIN{print "ID #segm #words %correct %err\n"} print;' <(grep "sys" per_spk | sed -e "s/[[:space:]]\+/ /g" | cut -d" " -f1,3-5,9 | sort -n -k5) > per_spk_err_sorted

import sys
import matplotlib.pyplot as plt
import numpy as np
with open(sys.argv[1],'r',encoding='utf-8') as f:
    next(f)
    wer = [float(line.strip().split()[4]) for line in f]
        
plt.hist(wer, 30)
plt.xlabel('%WER per speaker')
#plt.ylabel('#Speakers')
plt.ylabel('Frequency')
#plt.title('%WER distribution over speakers')
plt.axis([0, 20, 0, 7])
plt.xticks(np.arange(0, 20, 2))
#plt.grid(True)
plt.show()

# with open(sys.argv[1],'r',encoding='utf-8') as f:
#     wer = [float(line.strip().split()[6]) for line in f]
#
# plt.hist(wer, 100)
# plt.xlabel('%WER per utterance')
# plt.ylabel('Frequency')
# plt.title('%WER distribution over utterances')
# plt.axis([0, 50, 0, 1600])
# plt.xticks(np.arange(0, 50, 5))
# plt.show()

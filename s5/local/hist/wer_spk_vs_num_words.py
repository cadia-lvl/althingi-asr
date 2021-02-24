#!/usr/bin/python3

# Check connection between the amount of data per spk and wer

# Takes as input per_spk_err_sorted, which is obtained in the following way:
# perl -ne 'BEGIN{print "ID #segm #words %correct %err\n"} print;' <(grep "sys" per_spk | sed -e "s/[[:space:]]\+/ /g" | cut -d" " -f1,3-5,9 | sort -n -k5) > per_spk_err_sorted

import sys
import matplotlib.pyplot as plt
import numpy as np
with open(sys.argv[1],'r',encoding='utf-8') as f:
    next(f)
    list_f = [line.strip().split() for line in f]
words=[float(list[2]) for list in list_f]
wer=[float(list[4]) for list in list_f]
m, b = np.polyfit(words, wer, 1)
plt.plot(words, wer, 'o')
plt.plot(words, m*int(words) + b, '-')
plt.xlabel('#Words per speaker')
plt.ylabel('%WER per speaker')
#plt.title('%WER distribution over speakers')
plt.axis([0, 5000, 0, 20])
#plt.xticks(np.arange(0, 22, 2))
#plt.grid(True)
plt.show()

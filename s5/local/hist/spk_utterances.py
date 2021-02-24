#!/usr/bin/python3

# Takes as input wps_stats.txt

import sys
import matplotlib.pyplot as plt
import numpy as np
with open(sys.argv[1],'r',encoding='utf-8') as f:
    n_utterances = [float(line.strip().split()[2]) for line in f]
        
plt.hist(n_utterances, 400)
plt.xlabel('Number of utterances per speaker')
plt.ylabel('#Speakers')
#plt.axis([0, 1000, 0, 20])
#plt.xticks(np.arange(0, 1000, 100))
plt.grid(True)
plt.show()

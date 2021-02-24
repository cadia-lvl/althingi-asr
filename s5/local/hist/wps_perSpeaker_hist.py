#!/usr/bin/python3

# Takes as input wps_stats.txt, created by wps_speakerDependent.py

import sys
import matplotlib.pyplot as plt
import numpy as np

with open(sys.argv[1],'r',encoding='utf-8') as f:
    # Median wps per speaker
    wps = [float(line.strip().split()[11]) for line in f.readlines()]

plt.hist(wps, 30)
plt.xlabel('Words/second')
plt.ylabel('# Speakers')
plt.title('Median words per second per speaker')
#plt.axis([0, 5, 0, 30])
plt.grid(True)
plt.show()

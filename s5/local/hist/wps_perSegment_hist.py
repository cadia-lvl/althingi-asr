#!/usr/bin/python3

# Takes as input wps.txt, created by words_per_second.sh
# Does not show outliers, i.e. segments with wps > 5

import sys
import matplotlib.pyplot as plt
import numpy as np

with open(sys.argv[1],'r',encoding='utf-8') as f:
    # wps per segment
    wps = [float(line.strip().split()[0]) for line in f.readlines()]
            
plt.hist(wps, 100)
plt.xlabel('Words/second')
plt.ylabel('# Segments')
plt.title('Words per second in Althingi segments')
plt.axis([0, 5, 0, 50000])
plt.grid(True)
plt.show()

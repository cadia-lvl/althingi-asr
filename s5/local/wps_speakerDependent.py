#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Calculate some statistics about the word per second ratio distributions for each speaker
# Takes as input the folder containing wps.txt (which was created with words_per_second.sh).

import sys
import numpy as np

out = open(sys.argv[1]+'/wps_stats.txt','w',encoding='utf-8')
with open(sys.argv[1]+'/wps.txt','r',encoding='utf-8') as f:
    lines=f.read().splitlines()

spk_dict={}
speakers = set([line.split()[2].split('-')[0] for line in lines])
for spk in speakers:
    spk_dict[spk] = [float(line.split()[0]) for line in lines if line.split()[2].split('-')[0]==spk]

for spk in spk_dict.keys():
    #perc = np.percentile(spk_dict[spk],[3,5,10,50,90,95,97])
    perc = np.percentile(spk_dict[spk],[1,3,50,97,99])
    print('{} #speeches: {} mean: {:04.2f} variance: {:04.2f} percentiles: {}'.format(spk,len(spk_dict[spk]),np.mean(spk_dict[spk]),np.var(spk_dict[spk])," ".join(format(p, "4.2f") for p in perc)),file=out)

out.close()
          

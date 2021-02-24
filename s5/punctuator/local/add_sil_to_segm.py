#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

import sys
import codecs

with codecs.open(sys.argv[3],'w',encoding='utf-8') as fout:
    with codecs.open(sys.argv[1],'r',encoding='utf-8') as ftext:
        with codecs.open(sys.argv[2],'r',encoding='utf-8') as fsil:
            while True:
                segm = ftext.readline().strip().split()
                sil = fsil.readline().strip().split()
                if not segm: break
                if not sil: break
                newsegm=[]
                if segm[0] == sil[0]:
                    newsegm.append(segm[0])
                    for word in segm[1:]:
                        newsegm.extend([word,'<sil=0.000>'])
                    if len(sil) > 1:
                        for it in sil[1::2]:
                            # I do not consider silences that come before a segment.
                            if int(it) != 0:
                                newsegm[2*int(it)]='<sil='+sil[sil.index(it)+1]+'>'
                else:
                    sys.exit("ERROR: Incompatible utterance IDs")
                    
                fout.write(' '.join(newsegm)+'\n')        
     

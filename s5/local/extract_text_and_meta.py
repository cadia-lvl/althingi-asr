#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import glob
import os
import codecs
import re
#from bs4 import BeautifulSoup

with codecs.open(sys.argv[3],'w',encoding='utf-8') as fout_meta:
    with codecs.open(sys.argv[2],'w',encoding='utf-8') as fout:
        xmlpaths = glob.glob(os.path.join(sys.argv[1],'*.xml'))    
        for file in xmlpaths:
            file_base = os.path.splitext(os.path.basename(file))[0]
            with codecs.open(file,'r',encoding='utf-8') as fin:
                #soup = BeautifulSoup(fin, 'lxml-xml')
                #speech=soup.find('ræðutexti')
                data=fin.read().replace('\n', ' ')
                if re.search('<ræðutexti>(.*)</ræðutexti>',data) == None:
                    print(file_base, file=fout)
                else:
                    body_txt = re.search('<ræðutexti>(.*)</ræðutexti>',data).group()
                    topic = re.search('<málsheiti>(.*)</málsheiti>',data).group()
                    skst = re.search('skst=\"([^"]+)\" ',data).group()
                    #text = ' '.join([file_base, speech]).strip().replace('\n', ' ')
                    text = ' '.join([file_base, body_txt]).strip().replace('\n', ' ')
                    meta = ' '.join([file_base, skst, topic]).strip()
                    print(text, file=fout)
                    print(meta, file=fout_meta)

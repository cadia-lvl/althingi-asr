#!/usr/bin/env python
# coding: utf-8

# Extract after what word in a segment there is a silence and how long it is. I extract that information from a file in the following format:

# # uttID duration sil/phones
# ÞorS-rad20130910T152716_00003 0.240 sil 
# ÞorS-rad20130910T152716_00003 0.070 v_B ɛ_I r̥_I k_I ɛ_I p_I n_I ɪ_E  
# ÞorS-rad20130910T152716_00003 0.040 s_B t_I j_I ou_I r_I t_I n_I a_I r_I ɪ_I n_I a_I r_E  
# ÞorS-rad20130910T152716_00003 0.030 ɛː_B r_I ʏ_E  
# ÞorS-rad20130910T152716_00003 0.110 s_B c_I iː_I r_E  
# ÞorS-rad20130910T152716_00003 0.230 sil 
# ÞorS-rad20130910T152716_00004 0.250 sil 
# ÞorS-rad20130910T152716_00004 0.060 p_B ai_I h_I t_E  
# ÞorS-rad20130910T152716_00004 0.120 s_B t_I aː_I ð_I a_E  
# ÞorS-rad20130910T152716_00004 0.050 i_B s_I t_I l_I ɛ_I n_I s_I k_I r_I a_E  
# ÞorS-rad20130910T152716_00004 0.050 h_B eiː_I m_I ɪ_I l_I a_E  
# ÞorS-rad20130910T152716_00004 0.420 sil 
# ÞorS-rad20130910T152716_00004 0.060 ɔː_B ɣ_E 

# The duration is only correct for the silences

import sys
import codecs

with codecs.open(sys.argv[2],'w',encoding='utf-8') as fout:
    with codecs.open(sys.argv[1],'r',encoding='utf-8') as fin:
        table = fin.read().strip().splitlines()

        #total=[]
        uttid=""
        uttlist=[]
        for line in table:
            l=line.split()
            if uttid != l[0]:
                if uttid != "":
                    #total.append(uttlist)
                    fout.write(' '.join(uttlist) + '\n')
                i=0
                uttid=l[0]
                uttlist=[uttid]
            
            if l[2]=="sil":
                uttlist.append(' '.join([str(i),l[1]]))
            else:
                i+=1
        # For the last segment
        fout.write(' '.join(uttlist) + '\n')
                

        

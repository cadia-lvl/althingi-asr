#!/usr/bin/env python
# encoding: utf-8

import sys
import codecs
import re
from fuzzywuzzy import fuzz
from fuzzywuzzy import process # Fuzzy matching

def match(segments,speech):
    """Match short segments, clean of punctuations but containing pause information, to punctuation training texts, which contain punctuation tokens, but are otherwise similar (whole speeches). The short segments have no abbreviations, while the whole speeches are partially unexpanded.
    """
    # Punctuation token pattern
    p=re.compile("[^ a-záðéíóúýþæöA-ZÁÐÉÍÓÚÝÞÆÖ0-9<][A-Z]+")
    #p=re.compile("[.,:;?!][A-Z]+")

    match_dict=match_dictionary() # For finding correct expansions of abbreviations
    approx_match_dict=approx_match_dictionary() # Expands abbreviations to the stem that is common beween all forms of the word
    
    # loop through the speech
    j=0 
    speechlist=speech.split()
    newsegments=[]
    for segment in segments:
        segmlist=segment.split()
        # Length without pause tokens
        l=len(segmlist[1::2])

        # Number of punctuations in the current speech part
        npunct=len(re.findall(p,' '.join(speechlist[j:j+l]), flags=0))
        # The speech part excluding punctuations
        speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
        
        indices = [i for i,x in enumerate(speechtrans) if x == "<NUM>"]

        # Try to match the words that come before and after the "<NUM>" token with words in the segment.
        # Collapse what comes between into <NUM>
        if indices !=[]:
            segmlist=collapse_num(speechtrans,segmlist,indices,match_dict)

        if segmlist==[]:
                print("Returned segment is empty: ", segment.split()[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)

        trans=segmlist[1::2]
        l=len(trans)
        npunct=len(re.findall(p,' '.join(speechlist[j:j+l+npunct]), flags=0))
        speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]

        # Calculate the Levenshtein score between the pause-annotated segment and the punctation text segment
        score=fuzz.ratio(' '.join(trans),' '.join(speechtrans))
        
        try:
            speechlist[j+l+npunct-1]
        except IndexError:
            print(speechlist[0],": index out of range. Segment: ",segmlist[0])
            print("Continue to next speech")
            return '\n'.join(newsegments)

        # Fix if last word is a punctuation or if first/last is an abbreviation
        first=speechlist[j]
        last=speechlist[j+l+npunct-1]
        if first in approx_match_dict.keys():
            first=approx_match_dict[first]

        if p.match(last):
            last=speechlist[j+l+npunct-2]
        if last in approx_match_dict.keys():
            last=approx_match_dict[last]

        k=j

        # Slide the window one word to the right and see if the Levenshtein distance decreases
        while fuzz.ratio(trans[0],first) < 80 or fuzz.ratio(trans[-1],last) < 80 or score < 85:
            j+=1
            npunct=len(re.findall(p,' '.join(speechlist[j:j+l+npunct]), flags=0))
            try:
                speechlist[j+l+npunct-1]
            except IndexError:
                print(speechlist[0],": index out of range. Segment: ",segmlist[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)

            # Check if a punctuation comes afterwards. If the last word in the segment
            # was the last word in the speech then nothing happens.
            try:
                if p.match(speechlist[j+l+npunct]):
                    npunct+=1
            except IndexError:
                pass
            
            speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]
            indices = [i for i,x in enumerate(speechtrans) if x == "<NUM>"]

            if indices !=[]:
                segmlist=collapse_num(speechtrans,segmlist,indices,match_dict)

            if segmlist==[]:
                print("Returned segment is empty: ", segment.split()[0])
                print("Continue to next speech")
                return '\n'.join(newsegments)

            trans=segmlist[1::2]
            l=len(trans)
            speechtrans=[word for word in speechlist[j:j+l+npunct] if p.match(word)==None]

            score=fuzz.ratio(' '.join(trans),' '.join(speechtrans))

            first=speechlist[j]
            last=speechlist[j+l+npunct-1]
            if first in approx_match_dict.keys():
                first=approx_match_dict[first]
            if p.match(last):
                last=speechlist[j+l+npunct-2]
            if last in approx_match_dict.keys():
                last=approx_match_dict[last]

            did_break=False
            if j>k+70:
                print("Match not found for segment: ", segmlist[0])
                print("Continue to next segment")
                j = k+l-4
                did_break=True
                break

        # Use the best match to create the pause annotated data for step 2 of the punctuation model
        if not did_break:
            try:
                if p.match(speechlist[j+l+npunct]):
                    npunct+=1
            except IndexError:
                pass
        
            newsegments.append(weave_output(speechlist[j:j+l+npunct],segmlist,p))
            j=j+l+npunct

    return '\n'.join(newsegments)+'\n'

def weave_output(speech_list,segment_list,p):
    """Use the best match to create the pause annotated data for step 2 of the punctuation model"""

    newsegm=[segment_list[0]] # Start with the uttID
    textit=0
    pauseit=2 # Skip words. Use the ones from the punct. transcript
        
    # Weave together the two segments
    while textit < len(speech_list) and pauseit < len(segment_list)+2:
        if p.match(speech_list[textit]):
            newsegm.append(speech_list[textit])
            textit+=1
        else:
            newsegm.append(speech_list[textit])
            newsegm.append(segment_list[pauseit])
            textit+=1
            pauseit+=2

    return ' '.join(newsegm)

def collapse_num(speechpart,slist,indices,match_dict):
    """Search for a match between the words that come before and after the "<NUM>" token 
       in the punctuation text and words in the pause-annotated segment.
       Collapse what comes between the matched words in the pause-annotated segment to <NUM>
    """
    for idx in indices:
        if idx == 0:
            idx_segm_before = [-1]
            if speechpart[idx+1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[idx+1]],' '.join(slist))
                idx_segm_after = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_after = [i for i,x in enumerate(slist) if x == speechpart[idx+1]]
                
        elif idx == len(slist[1::2])-1:
            if speechpart[idx-1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[idx-1]],' '.join(slist))
                idx_segm_before = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_before = [i for i,x in enumerate(slist) if x == speechpart[idx-1]]
            idx_segm_after = [len(slist)]

        elif idx >= len(slist[1::2]):
            print("idx is out of bounds")
            continue
        
        else:
            pidx=idx
            if speechpart[pidx-1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[pidx-1]],' '.join(slist))
                idx_segm_before = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_before = [i for i,x in enumerate(slist) if x == speechpart[pidx-1]]
            nidx=idx
            if speechpart[nidx+1] in match_dict.keys():
                mo=re.findall(match_dict[speechpart[nidx+1]],' '.join(slist))
                idx_segm_after = [i for i,x in enumerate(slist) if x in mo]
            else:
                idx_segm_after = [i for i,x in enumerate(slist) if x == speechpart[nidx+1]]
            if idx_segm_after == []:
                idx_segm_after = [len(slist)]       

        slist=best_num_match(speechpart,slist,idx_segm_before,idx_segm_after)
    return slist

def match_dictionary():
    """Maps abbreviations to regular expressions, containing all 
       possible expanded forms of the corresponding abbreviation"""
    k=["%","bls","gr","hv","hæstv","kl","klst","km","kr","málsl",\
       "málsgr","mgr","millj","nr","tölul","umr","þm","þskj","þús"]
    v=[r'prósent[a-záðéíóúýþæö]*',r'blaðsíð[a-záðéíóúýþæö]*\b',\
       r'\bgrein(?:ar)?\b',r'háttvirt[a-záðéíóúýþæö]*\b',\
       r'hæstvirt[a-záðéíóúýþæö]*\b',r'\bklukkan\b',\
       r'\bklukkustund[a-záðéíóúýþæö]*\b',r'\bkílómetr[a-záðéíóúýþæö]*\b',\
       r'\bkrón(?:a|u|ur|um)?\b',r'\bmálslið[a-záðéíóúýþæö]*\b',\
       r'málsgrein[a-záðéíóúýþæö]*',r'málsgrein[a-záðéíóúýþæö]*',\
       r'milljón[a-záðéíóúýþæö]*',r'\bnúmer\b',r'\btölulið[a-záðéíóúýþæö]*\b',\
       r'\bumræð[a-záðéíóúýþæö]+\b',r'\bþingm[a-záðéíóúýþæö]+',\
       r'þingskj[a-záðéíóúýþæö]*',r'\bþúsund[a-záðéíóúýþæö]*\b']
    d={}
    for i in range(len(k)):
        d[k[i]] = v[i]
    return d

def approx_match_dictionary():
    """Maps abbreviations to the part of the expanded form that is common beween all forms of the word"""
    k=["%","bls","gr","hv","hæstv","kl","klst","km","kr","málsl",\
       "málsgr","mgr","millj","nr","tölul","umr","þm","þskj","þús"]
    v=['prósent','blaðsíð',\
       'grein','háttvirt',\
       'hæstvirt','klukkan',\
       'klukkustund','kílómetr',\
       'krón','málslið',\
       'málsgrein','málsgrein',\
       'milljón','númer','tölulið',\
       'umræð','þingm',\
       'þingskj','þúsund']
    d={}
    for i in range(len(k)):
        d[k[i]] = v[i]
    return d

def best_num_match(speechpart,slist,idx_segm_before,idx_segm_after):
    """Calculates which collapse to <NUM> gives the best match"""
    strans_best=0
    slist_best=[]
    for ia in idx_segm_after:
        for ib in idx_segm_before:
            if ib < ia:
                slist2=slist[:ib+2]
                slist2.append("<NUM>")
                slist2.extend(slist[ia-1:])
                trans=slist2[1::2]
                ltrans=len(trans)
                strans=fuzz.ratio(' '.join(trans),' '.join(speechpart[:ltrans]))
                
                if strans > strans_best:
                    strans_best=strans
                    slist_best=slist2

    return slist_best

    
if __name__ == '__main__' :

    with codecs.open(sys.argv[1],'r',encoding='utf-8') as ftext:
        speeches = ftext.read().strip().splitlines()
        with codecs.open(sys.argv[2],'r',encoding='utf-8') as fpause:
            segments = fpause.read().strip().splitlines()
            with codecs.open(sys.argv[3],'a',encoding='utf-8') as fout:
                
                for speech in speeches:
                    uttid = speech.split(' ', 1)[0]
                    speech_segments = [line for line in segments if uttid in line]
                    
                    newsegments = match(speech_segments,speech)
                    fout.write(newsegments)


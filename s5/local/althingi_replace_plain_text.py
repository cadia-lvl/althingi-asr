#!/usr/bin/env python3

# Copyright 2017  Reykjavik University (Author: Anna Björk Nikulásdóttir)
# Apache 2.0

# Replaces occurrences of 'hv.' in Alþingi speeches. The abbrevation for 'háttvirtur' will be expanded in combination with words ending
# with differents forms of 'maður' and with the genitive of 'nefnd', 'nefndar'.
#
# Examples:
# 'ekki sammála hv. þingmanni' -> 'ekki sammála háttvirtum þingmanni'
# 'þakka þingmanninum hv. sérstaklega' -> 'þakka þingmanninum háttvirta sérstaklega'
# 'fyrir hönd hv. efnahags- og viðskiptanefndar' -> 'fyrir hönd háttvirtrar efnahags- og viðskiptanefndar' (only handles exact this pattern)
#
# Copyright 2016 Anna Björk Nikulásdóttir
#

import sys, re

if (len(sys.argv) < 3):
        print("Need 2 arguments: input file and output file!")
        sys.exit()


def replace_hv(text, tag, group2replace):
        """Expand hv. in the cases where the form is known from
        the form of the word behind"""
        if (tag.endswith("maður")):
                newtext = re.sub(group2replace, "háttvirtur", text)
        elif (tag.endswith("mann")):
                newtext = re.sub(group2replace, "háttvirtan", text)
        elif (tag.endswith("manni")):
                newtext = re.sub(group2replace, "háttvirtum", text)
        elif (tag.endswith("manns")):
                newtext = re.sub(group2replace, "háttvirts", text)
        elif (tag.endswith("mönnum")):
                newtext = re.sub(group2replace, "háttvirtum", text)
        elif (tag.endswith("manna")):
                newtext = re.sub(group2replace, "háttvirtra", text)
        elif (tag.endswith("maðurinn")):
                newtext = re.sub(group2replace, "háttvirti", text)
        elif (tag.endswith(("manninn", "manninum", "mannsins"))):
                newtext = re.sub(group2replace, "háttvirta", text)
        elif (tag.endswith(("mennirnir", "mennina", "mönnunum", "mannanna"))):
                newtext = re.sub(group2replace, "háttvirtu", text)
        elif (tag.endswith(("nefndar"))):
                newtext = re.sub(group2replace, "háttvirtrar", text)
        else:
                newtext = text
        return newtext

def replace(text, matched_text, tag):
        start_pos = text.find(matched_text)
        end_pos = start_pos + len(matched_text)
        replaced = replace_hv(matched_line, tag, HV_ABBR)
        text = text[:start_pos] + replaced + text[end_pos:]
        return text


HV_ABBR = "hv"
ICE_WORDCHARS = '[\wáéíóúýöæþð]'

regex_1 = '(hv)\s+(' + ICE_WORDCHARS + '+(maður|mann|manni|manns|menn|mönnum|manna))[\W]'
regex_2 = '(' + ICE_WORDCHARS + '+(menn|maðurinn|manninn|manninum|mannsins|mennirnir|mönnunum|mannanna))\s+(hv)[\W]'
regex_3 = '(hv)\s+(' + ICE_WORDCHARS + '+-\s+og\s+' + ICE_WORDCHARS + '+nefndar)[\W]'

pattern_1 = re.compile(regex_1, re.IGNORECASE)
pattern_2 = re.compile(regex_2, re.IGNORECASE)
pattern_3 = re.compile(regex_3, re.IGNORECASE)

in_file = open(sys.argv[1])

# look for matches of all patterns line by line, replace 'hv.' where possible and assemble the text again.
result_lines = []
for line in in_file:
        text = line.strip()
        match_list = pattern_1.findall(text)
        # on find returns a list of ('hv.', 'þingmaður', 'maður')
        for t in match_list:
                matched_line = ' '.join(t[:2])
                text = replace(text, matched_line, t[1])


        match_list = pattern_2.findall(text)
        # on find returns a list of ('þingmaðurinn', 'maðurinn', 'hv.')
        for t in match_list:
                matched_line = t[0] + " " + t[2]
                text = replace(text, matched_line, t[0])


        match_list = pattern_3.findall(text)
        # on find returns a list of ('hv.' 'efnahags- og viðskiptanefndar')
        for t in match_list:
                matched_line = ' '.join(t)
                text = replace(text, matched_line, "nefndar")

        result_lines.append(text)

in_file.close()

result = '\n'.join(result_lines)

out_file = open(sys.argv[2], 'w')
out_file.write(result)
out_file.close()

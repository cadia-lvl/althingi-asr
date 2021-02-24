# An ASR recipe and speech corpus of Icelandic parliamentary speeches
##### Prepared by Inga Rún Helgadóttir, Anna Björk Nikulásdóttir, Róbert Kjaran and Jón Guðnason
##### Created in Reykjavik University, Iceland


### ABOUT THE ALTHINGI PARLIAMENTARY SPEECH CORPUS

All performed speeches in the Icelandic parliament, Althingi, are transcribed and published. Our corpus consists of 130 thousand Althingi speeches, aligned and segmented, with 309 speakers. The total duration of the data set is roughly 6300 hours and it contains about 60M word tokens. 

#### TO DOWNLOAD THE DATA, PRONUNCIATION DICTIONARY AND LANGUAGE MODELS

The data for acoustic model training, language modelling and post processing of the ASR output are available at [www.malfong.is](http://www.malfong.is/index.php?lang=en&pg=althingisraedur)
The original data, which consists of whole parliamentary speeches, that are not ready for speech recognition, are also available there.

#### PUBLICATION ON ALTHINGI DATA AND ASR #####
Details on the corpora can be found in the following publication. We appreciate if you cite it if you intend to publish.
@inproceedings{Inga2017,
        Title = {Building an ASR corpus using Althingi’s Parliamentary Speeches},
        Author = {Inga Rún Helgadóttir and Róbert Kjaran and Anna Björk Nikulásdóttir and Jón Guðnason},
        Booktitle = {Proceedings of INTERSPEECH},
        Year = {2017},
        Address = {Stockholm, Sweden},
        Month = {August}

### ABOUT THIS REPOSITORY

#### SCRIPTS
The subdirectory of this directory, s5, contains scripts for the following three steps:
1) Data normalization, alignment and segmentation.
2) Training of an ASR
3) Postprocessing of the ASR output, including punctuation restoration, capitalization and denormalization of numbers and common abbreviations
4) In kaldi/src/fstbin there are two files, fststringcompile.cc and expand-numbers.cc, that are not in the official Kaldi toolkit. They are used for the expansion of abbreviations and numbers in the process of text normalization.

#### EXTERNAL TOOLS NEEDED

- [OpenGrm Thrax](http://www.opengrm.org/): For number and abbreviation expansion. As well as for the postprocessing of the ASR output.
  - Requires [OpenFst 1.6.0](http://www.openfst.org/twiki/bin/view/FST/WebHome) or higher, configured with the ```--enable-grm``` flag (installed when installing Kaldi).
- [KenLM](https://kheafield.com/code/kenlm/): For language modelling, fast and allows pruning.
- [Sequitur-g2p](https://github.com/sequitur-g2p/sequitur-g2p): For grapheme-to-phoneme conversion (not needed when the pronunciation dictionary is ready). It is part of the Kaldi installation but fails if Swig has not been installed.
  - Requires: [Swig](http://www.swig.org) and numpy
- [FFmpeg](https://ffmpeg.org/): Used for silence detection when using the ASR to recognize long speeches.
- [Punctuator2](https://github.com/ottokart/punctuator2):  For punctuation restoration. (It is already in ```egs/althingi/s5/punctuator2```)
  - Requires: [Theano](https://github.com/Theano/Theano) and python 2.7 and numpy
- Most python scripts in the repo use python3 but punctuator2 and some Kaldi scripts use python2.7

#### INSTALLATION

 For Debian installation follow the instructions in `s5/installdebian.sh`

#### WER RESULTS OBTAINED USING OUR CORPORA AND SETTINGS.

Using a 1215 hour, recleaned and resegmented subset of the data corpus, with n-gram language models, an automatic speech recognizer with a 8.52% word error rate has been developed. Re-scoring with RNN language models, we can get the WER down to 7.91%. The acoustic model used is a factorized form of time-delay neural networks. The recipe is based on the Switchboard recipe in the Kaldi toolkit (D. Povey et al., 2011) [http://kaldi-asr.org](http://kaldi-asr.org/).

#### DOCUMENTATION

Further information about where to store data and models, how to run the ASR and how to update the different parts of it are in the file `ASRdocumentation.md`

License
----
This is an open source project with the Apache 2.0 Licence.

#!/bin/bash
#Authors: Inga Run Helgasdottir and Judy Fong
# OS: Debian or Ubuntu
# minimum RAM: 8 GB
# minimum CPU: 4 
# Description: These instructions assume this is a fresh install of the repo 
#   in the user's home folder where 
# a) you have a lexicon and want to create models or
# b) all you want to do is decode audio files from existing models.

#(1)
git clone https://github.com/cadia-lvl/kaldi.git althingi-kaldi
# This is done by kaldi/tools make so not necessary: git clone https://github.com/xianyi/OpenBLAS.git

# (2)
# Install the necessary packages

sudo apt-get update
sudo apt-get upgrade
sudo apt-get install g++ # might need the 4.8 version but 5 should work, 6 definitely won't work
sudo apt-get install python-dev python-pip
sudo apt-get install swig
sudo apt-get install python-numpy python-scipy python-matplotlib ipython 
sudo apt-get install -y zlib1g-dev make automake autoconf libtool subversion gfortran libatlas3-base
sudo apt-get install build-essential libboost-all-dev cmake libbz2-dev liblzma-dev
sudo apt-get install ffmpeg
sudo apt-get install sox libsox-fmt-mp3 #to make recognize work with the default althingi mp3s
sudo apt install bc
sudo pip install nltk #only works if you are installing to the correct python version (2.7)

# ERRORS:

# If getting errors from making ivectors, then it may be a memory problem. 
# Therefore, please refer to kaldi/tools/Makefile section: openblas_compiled

# which will tell you how to fix the NUM_THREADS/ "Program is Terminated. Because you tried to allocate too many memory
# # regions." error.
  
# But our solution is to have at least 4 CPUs and 8-16 GB of RAM

# (3)
# First, run the usual kaldi installations in kaldi/tools and kaldi/src
# Make sure thrax is enabled in tools/Makefile

# They will recommend you install missing dependencies so do that. Then,

# if have to, run 'make 'in tools multiple times do:
make distclean 
sudo rm -rf OpenBLAS


#compile kaldi with optimizations (-O3) on.
#That can be x10 speedup in some cases

#Make sure to install the necessary external tools mentioned on kaldi/egs/althingi/README.md
# Swig and numpy necessary for sequitur
cd /opt/althingi-kaldi/tools/
#make sure sequitur is installed from tools/extra
./extras/check_dependencies.sh
make -j &> kaldi.tools.log &
# If the openfst and sequitur symlinks have not been created I create them
ln -s /opt/althingi-kaldi/tools/openfst-1.6.7 /opt/althingi-kaldi/tools/openfst
ln -s /opt/althingi-kaldi/tools/sequitur-g2p /opt/althingi-kaldi/tools/sequitur

cd /opt/althingi-kaldi/src
./configure --shared --openblas-root=../tools/OpenBLAS/install
make -j > kaldi.tools.log
make depend -j
make -j
cd /opt

# (4a)
# thrax should be enabled on the kaldi openfst install, but you will still need to install it if you do any data preparation or do a denormalization step

# export $LD_LIBRARY_PATH=/usr/local/lib put this in the .bashrc file
wget https://www.openfst.org/twiki/pub/GRM/ThraxDownload/thrax-1.2.7.tar.gz
tar -zxvf thrax-1.2.7.tar.gz
cd thrax-1.2.7
#You have to make sure the thrax configuration file has the right flags and points to the right repositories.
CPPFLAGS=-I/opt/althingi-kaldi/tools/openfst/include/ LDFLAGS=-L/opt/althingi-kaldi/tools/openfst/lib/ ./configure --enable-static=no
#if you can figure out how to make this work, please submit a pull request with the fix: --enable-readline=yes 
make &> thrax-installer.log &
sudo make install
cd ../

# (4b)
# Mitlm is used when segmenting. Install it:
git clone https://github.com/mitlm/mitlm.git
sudo apt-get install autoconf-archive
cd mitlm
autoreconf -i
./configure
make
sudo make install
cd ../

#Install KenLM and all dependencies - Done in tools Makefile
# punctuator2 is now included and should no longer require python 2.7 but it needs to be tested to be sure
# currently
# wget https://kheafield.com/code/kenlm.tar.gz
# tar -zxvf kenlm.tar.gz
# mkdir -p kenlm/build
# cd kenlm/build
# cmake ..
# make -j2
#cd ../../

# (4c)
#Install the conda environment for Theano
#install miniconda
# Install into /opt/miniconda2 and choose to initialize in .bashrc
wget https://repo.anaconda.com/miniconda/Miniconda2-latest-Linux-x86_64.sh
bash Miniconda2-latest-Linux-x86_64.sh

#I created a conda environment: 
conda create -n thenv python=2.7
sudo pip install miniconda Theano

#environment location: /home/lirfa/.conda/envs/thenv
conda activate thenv
conda deactivate

#NOTE! The site-packages are not in the $PATH so I actually added $CONDAPATH and /usr/lib/python2.7/site-packages/ to $PATH. I hope that won't cause problems. CONDAPATH=/tools/miniconda2/bin
#theano asked that mkl would be installed. I  installed it with
conda install mkl-service

#I have the problem that a lot of python modules are in 
#/tools/miniconda2/lib/python2.7/site-packages/ which is not in sys.path so I created the file  so now they are.
#(recommended here: https://stackoverflow.com/questions/12257747/adding-a-file-path-to-sys-path-in-python)
# NOTE! We had to do the following on terra:
#touch /home/lirfa/.conda/envs/thenv/lib/python2.7/site-packages/paths.pth
conda install Theano

# I need a gpu backend - NOTE! Fails on the lm server!
# Follow the instructions here: http://deeplearning.net/software/libgpuarray/installation.html
# The main things we need to install are
#make sure cmake is at least 3.0
conda install cython
conda install nose
git clone https://github.com/Theano/libgpuarray.git
cd libgpuarray
# And follow instructions

# (5)
# Modify cmd.sh to run from your local computer or from a cluster

# (6)
# Modify path.sh and conf/path.conf to use the relevant paths
# Make sure the paths to external tools like sequitur kenlm are correct
cd /opt
ln -s /opt/althingi-kaldi/egs/althingi/s5/ ASR
cd ASR
. ./path.sh
ln -sfn ../../wsj/s5/utils utils
ln -sfn ../../wsj/s5/steps steps
ln -sfn ../../wsj/s5/rnnlm rnnlm

# (7)
# Install a virtual python 3.5 environment
pip install virtualenv
virtualenv -p /usr/bin/python3.5 venv3
source venv3/bin/activate
pip install -r venv3_requirements.txt
deactivate

# (8)
# Set up the input and output data and model directories based on the structure in conf/path.conf
# NOTE! Make sure you have updated path.sh and conf/path.conf to fit the server setup you want
#config file for making directories for models and importing models, Althingi_setup.sh
Althingi_setup.sh
# don't overwrite models, just have them versioned with timestamps/subdirectories, maybe map it with an SQL database

# (9)
# Move necessary data over to the new server

# (10)
#Run the script: 
./local/compile_grammar.sh
#to compile the ABBR_AND_DENORM.fst and INSERT_PERIODS.fst yourself
# Copy the required FSTs from terra first

# (11)
# Should have been put in earlier: you compile kaldi with optimizations (-O3) on.
# That can be x10 speedup in some cases

# The default nltk installations are local to each user so make sure theyŕe installed for all users who execute recognize/local/recognize.sh and other scripts which require punctuation.
# the nltk_data directory needs to have 775 permissions


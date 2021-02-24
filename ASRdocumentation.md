## Althingi ASR documentation ##

#### Some notes about running and updating the Althingi ASR. ####
**NOTE!** This is customized for those running and maintaining the actual Althingi ASR, which is hosted on three servers, so if you are not doing that you can ignore all talk about different servers.

### OUTLINE ###
1. Explaining the code, data and model storage structure 
2. Using the ASR system, incl. the post-processing
3. Updating the ASR to its latest version
4. Post-processing
5. Updating lists
6. Updating the lexicon, language models, decoding graph and the bundle `latest`
7. Updating the punctuation model
8. Updating the paragraph model
9. Updating the acoustic model

### 1. The code, data and model storage structure ###

There are 8 base directories (two are so far only on the language model server and one on the decoding server):
* kaldi
	* The code for the Althingi ASR lies within the egs directory in kaldi, i.e. in ```kaldi/egs/althingi/s5```. Scripts are run from the s5 directory.
* bundle
	*  In ```bundle``` are gathered together data or models needed to run the ASR, i.e. each bundle contains a version of the ASR. Each subdirectory is marked by its creation date. That is to make sure that the models and data used are compatible with each other. The latest version is used when running the ASR.
* data
	* Contains the data needed to train the different models that are parts of the ASR or necessary for the training of it. The subdirectories are:
		* acoustic_model
			* Data used to train the acoustic model. Split into train/test and the directories are set up according to how kaldi wants them. These are copies of the actual data used, which is stored in $data (in my case that is on a different drive, $data is /mnt/scratch/inga/data). New AM training data will be put in a subdirectory called transcripts, one file for each speech.
		* expansionLM
			* Data used to train the expansion language model, which is used to  normalize the acoustic and language model training data . By normalize I mean to write out for example abbreviations and numbers as words. E.g. "Þann 23. mars" -> "Þann tuttugasta og þriðja mars"
		* intermediate
			* Contains the corpora at a few different steps of cleaning. Helpful to me when I need to check things. Not needed in production.
		* language_model
			* Data used to train the language model, normalized and split on EOS markers. New lm training data will be put in a subdirectory called transcripts, one file for each speech. After they are used in a lm they are moved to a subsubdirectory called archive.
		* lexicon
			* Contains the pronunciation dictionary (also called lexicon), grapheme to phoneme training dictionary, a list of foreign words with manual phonetic transcriptions (so they can easily be excluded from the g2p dict) and three subdirectories; new_vocab, confirmed vocab and dict. The last one is a temporary directory created when updating the language model. The other two are part of the automatic updates of the pronunciation dictionary. new_vocab also contains the subdirectory concordance which contains the concordance of the new words. Each of these new directories also contains a subdirectory called archive where the files can be moved to after the words are used in a lexicon. I guess it will mostly be used in the confirmed_vocab dir.
		* manually_fixed
			* This is old data from the time I first started to normalize the text data. The normalization results were poor for many abbreviations and numbers, not seen often enough written out in text. Hence I manually went through the text set I had at the time and fixed most of the expansions.
		* paragraph
			* Data used to train the paragraph model
		* punctuation
			* Data used to train the punctuation model. In the subdirectories marked by a date the data is processed for training. New punctuation training data will be put in a subdirectory called transcripts, one file for each speech. The data there has not gone through the preprocession step og mapping e.g. "." to ".PERIOD". 
		* As mentioned above: In `data/{acoustic_model,language_model,punctuation}/transcripts` the new transcripts, fixed by a transcriber at Althingi, end up, after being cleaned to fit for training for the different models, ready to be added to the training sets.
* lists
	* `discouraged_words.20161101.txt`: A list over writing notations which are incorrect or discouraged at Althingi, used when extracting new vocabulary. When I've gotten e-mails from the chief editor at Althingi to change the preferences for some words I've manually changed this list and the lexicon in use. The date in the filename is the date of the file they sent me containing which words they prefer to use when there are multiple options, i.e. 'bleyja' or 'bleia', or when some erroneous versions of a word are common. I thought I would be creating new versions of this list when new preferences arrived, but I haven't done it so far. The editors should be allowed to add/remove words from this list and changes to this list should also affect the lexicon in use. 
	* utf8.syms: a list of utf8 symbols.
	* venv3_requirements.txt and thenv_requirements.txt contain requirements for python 3.5 and python 2.7 virtual environments, respectively. The latter one is a conda environment used by Theano for the punctuation and paragraph models. 
	* Also, three subdirectories, which I had thought would be the main directories for lists, but now are not much used since most lists have to reside within the `local/thraxgrammar/lex` directory and I don't want to maintain unnecessarily many lists:
		* capitalization
			* Contains lists used when correcting the capitalization of texts. This was only used when pre-processing originally the big text sets received from Althingi or Leipzig, It is not used when text are cleaned with `clean_new_speech.sh`.
		* parliamentarians
			* A list which maps between the names and abbreviations (used as speaker IDs) of the parliamentarians. Also one with the gender listed as well.
		* text_norm
			* Contains a symlink to `local/thraxgrammar/lex`, which contains files used when normalizing or denormalizing the texts.
* models
	* Contains subdirectories with the different models or weighted finite state transducers used by the ASR or in the training data processing for it.
		* acoustic_model
			* Contains three subdirectories: 
				* chain/5.4 contains the neural network acoustic model. The model is a so-called chain model and the version of Kaldi used is 5.4. Different nnet architectures are as subdirectories. The current model is in tdnn_1_clean_sp. It is a time-delay deep neural network, re-cleaned and segmented data is used for training and speed perturbations are applied.
				* extractor contains the i-vector extractor
				* gmm contains a small Gaussian mixture model used for the alignment and segmentation of training data.
		* g2p
			* Contains the grapheme to phoneme model
		* language_model
			* All compatible language models are together in a subdirectory marked by the creation date. If a RNN language model exists for a specific vocabulary it will be with the n-grams in a date marked directory.
		* paragraph
			* The paragraph model used
		* punctuation
			* The punctuation model used. Inside the subdirectories is a file called info which states whether the model is a one or two stage model and whether it includes the prediction of commas or not.
		* text_norm
			* The date directories contain finite state transducers used for normalization and denormalization of text, the directory called base contains FSTs to use for the expansion of abbreviations and numbers based on a basic text set, not the full training set.

On the decoding server we have also:
* transcription_output
	* The raw text versions of the ASR transcripts. Each subdirectory is named after the speechname, and the final transcript, after automatic postprocessing, bears the same name, i.e. rad[year|month|day]T[hour|min|sec].txt. Inside each subdirectory is also a directory called intermediate, which contains the text at different postprocessing steps. It is used by me when checking how the steps work. Can probably be  removed in production.
	* A logs directory containing the overall logs from each speech, sublogs are in the speechname directories.

On the language model server we have also:
* logs
	* There we put the logs from training data cleaning and new vocab script and from the LM and graph updating script
* raw
	* ASR transcripts that have been reviewed by a transcriber or an editor is added to `raw/speeches/upphaflegt`. They are the XML transcripts we use to extract new training texts and find new words from. 

**Important:** Paths to all the main directories are defined in `conf/path.conf`. All the directories described above have a corresponding `$root_` variable. E.g. the list directory is `$root_listdir`. That is so that I can move these directories without the scripts failing.

In `conf/path.conf` the directories `$data`, `$exp`, `$mfcc` and `$mfcc_hires`  are also defined. This script is automatically run when I run path.sh. They define especially where the acoustic models should be trained. On Terra they point towards `/mnt/scratch/inga/` 

**Important:** path.sh is different for different servers. The directories listed above, including the location of Kaldi, are not one the same drive for the decoding and LM server. They are in the directory of lirfa on the decoding server, but on `/opt` on the LM server.

### 2. Using the ASR system, incl. post-processing ###

The ASR searches for new speeches and runs automatically. However, to just run one speech, one can either run `local/recognize.sh` or `local/recognize.sbatch` from the s5 directory. The latter is a run script for the former which puts it in the Slurm queue. It can be run like this:
> sbatch --export=audio=/path/to/audio/audio.mp3,outdir=/path/to/output,trim=0,rnnlm=false local/recognize/recognize.sbatch

The API usage is documented in the README file in Judys bitbucket page. She can give you access.

### 3. Updating the ASR to its latest version ###
Every time anything that is part of a bundle has been updated, the ASR version in use, called `latest`, should be updated. The script `local/update_latest.sh` checks which are the newest versions of everything in a bundle and uses them to create a new bundle, named by the creation date and `latest` becomes a symlink to it. It is usually run without any arguments. 

### 4. Post-processing ###
Before the post-processing the ASR transcript is just a stream of words. All numbers and abbreviations are written out and there are no punctuations or paragraph splits in the text. Such a text is difficult to read. 

The post-processing is done in a few steps.
1. The first step is to write numbers with numerals and apply many denormalization rules to law numbers, time, websites, ratios, abbreviations and more. A thrax grammar is used for this step, defined in `local/thraxgrammar/abbreviate.grm` and compiled into `ABBR_AND_DENORM.fst`. Some of the grammar rules depend on lists in ``local/thraxgrammar/lex/`. If either a rule or a list is updated the grammar FST needs to be re-compiled. That is done by running: 
	`local/compile_grammar.sh local/thraxgrammar <outputdir>`
See `run.sh` in the `s5` directory. To make the resulting FSTs go into the correct place in the data structure the output directory is chosen as `$root_text_norm_modeldir/<current date>`.
Thrax can be problematic, for example if only a list is changed then it does not realize a change has been made. Hence a space needs to be added and removed, or something equally stupid, in the grammar file for it to recompile.
These FSTs are part of the ASR bundle, so if no more changes are to be made the bundle should be updated.
2. Punctuation is added. Updating the model requires an update of `latest`. How to update that model and the paragraph model will be explained later. 
3. Abbreviation periods are added. This is a step I would like to skip. I just need to change how I deal with punctuations first. The way the system works now, I need to remove all periods that are not part of an ordinal or marks the end of a sentence. Hence, these are added after the punctuation model is applied. If an abbreviation is added to `abbreviate_if_followed_byNumber.txt`, `abbreviate_if_preceded_wNumber.txt`, `abbreviate_words.txt` or `kjordaemi_abbr.txt` in `local/thraxgrammar/lex`, which needs a period with it, I need to update the list `local/thraxgrammar/lex/abbr_periods.txt`, used to create INSERT_PERIODS.fst too, and then recompile as in the first step.
4. Next come some regular expressions to abbreviate "hæstvirtur", "háttvirtur" and "þingmaður", remove repititions and more. These can changed without anything more to it. 
5. Finally the text is split into paragraphs. Updating the model requires an update of `latest`.

### 5. Updating lists ###
Lists are used in data pre- and post-processing. They are plain text files and most of them are stored in `local/thraxgrammar/lex`. Some are in `$root_listdir` and there is a sym link there to the thraxgrammar lexicon directory. I had intended to move all lists to `$root_listdir` but Thrax doesn't accept relative paths. 
Updating the lists is easy. If, e.g. a new acronym, which is pronounced as letters, like "ÁTVR", is to be added, it is added to `acro_denormalize.txt` in `thraxgrammar/lex/`. A new abbreviation like "a.m.k." needs to be added to `abbr_lexicon.txt`,  `abbreviate_words.txt` (if supposed to be abbreviated in the output independent of the context) and `abbr_periods.txt` in `thraxgrammar/lex/`. 

The main thing is to know which lists to change. Many of the lists in `thraxgrammar/lex` are static and won't have to be touched. However, here is an explanation of the others:
* abbreviate_if_followed_byNumber.txt
	* Abbreviate if a number comes after. Used in post-processing.
* abbreviate_if_preceded_wNumber.txt
	* Abbreviate if a number comes before. Used in post-processing.
* abbreviate_words.txt
	* Abbreviate in all circumstances. Used in post-processing.
* abbr_lexicon.txt
	* All expansion possibilities of words.  Used in pre-processing.
* abbr_periods.txt
	* How to insert periods into abbreviations. Used in post-processing.
* acro_denormalize.txt
	* How to re-write acronyms pronounced as letters in the denormalization step, e.g. "h t t p s" -> "https" and "e s b" -> "ESB". Used in post-processing.
* ambiguous_personal_names.txt
	* Capitalize these names if followed by a family name, or if a middle name comes in between.
* dash.txt
	* Write a dash in these word compounds. Used in post-processing.
* kjordaemi_abbr.txt
	* Abbreviate the names of electoral districts. Used in post-processing.

It is important to re-compile the Thrax grammar after making changes and update the bundle afterwards.

### 6. Updating the lexicon, language models, decoding graph and the bundle `latest` ###

The script `extract_new_vocab_and_text.sh` in `local/new_speeches` is run automatically every time a transcriber has submitted corrections to an ASR text. It cleans the text and creates three training texts: for AM, LM and punctuation training. It also extracts new vocabulary and saves it, along with phonetic transcriptions in a directory called `new_vocab` in my `data/lexicon` directory. All these files are called the same name: spkID-rad[year|month|day]T[hour|min|sec].txt. The concordance of the new words is also saved. I have an sbatch script called get_vocab_and_text.sbatch which runs it on the Slurm queue.

An editor can view the new vocabulary and decide whether to save it or not. Saved new words end up in another directory called `confirmed_vocab` in the same place as the `new_vocab` dir.

The script `update_LM_and_graph.sh` will be run regularly to update the LMs and decoding graph used in the latest bundle, i.e. latest version of the ASR. It checks if there are any new language model texts in `data/language_model/transcripts` and the LM training corpus is updated. If there are no new files the script exits. If there are any vocabulary files in `confirmed_vocab`, the pronunciation dictionary is updated. The sbatch script `run_LM_update.sbatch` runs it on the Slurm queue. For now there is a cron job which runs the lexicon, LM and graph updates once a month. It is run on the language model server at Althingi. The script `cp_to_decodingASR.sh` in `local` is run on the decoding server to copy the models over and update `latest`.

### 7. Updating the punctuation model ###
The punctuation model is obtained using the recipe for punctuator 2: <https://github.com/ottokart/punctuator2> . 

The scripts for preparing the data and training the model are in the directory called `punctuator` under the `s5` dir. The `run.sh` script should be cleaned up a bit. The reason is that different methods were used for data obtained early as to later data. I did two tests using also pause annotated data, that code was just put together so that I could test it, and is not ready for general use. The results were not as good as the one-stage results. But using the training data I have, the model can be easily trained by following the steps in `run.sh`. Default is a one stage training, i.e. only using text data, and learning the following punctuation marks: period, comma, colon and question mark.

### 8. Updating the paragraph model ###
I modified the punctuation model to learn paragraph brakes. The code is in the directory `paragraph` under `s5`. The model can be trained by following the steps in `run.sh`

### 9. Updating the acoustic model ###
The acoustic model is the one that takes by far the longest to train. One needs a corpus of well aligning audio and text data, segmented into pieces short enough to train on, approx. 10 seconds long. To obtain that one can approximately follow the run script I have in the `s5` directory. Some steps will have to be modified, but most steps to obtain a fully functioning ASR should be there, in the approximate order. The neural network architecture I use is from the Switchboard recipe and can be found in `local/chain/run_tdnn.sh`. The current ASR version (from December 2018) is trained on re-cleaned and segmented data, 1215 hrs, in `$root_am_modeldir/20181218` on Terra (also available on www.malfong.is).
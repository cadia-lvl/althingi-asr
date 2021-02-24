#!/bin/bash -e

set -o pipefail

# Prepare data for punctuation model training, train the model, compare with the test sets and calculate the errors.

#date
d=$(date +'%Y%m%d')

stage=0
ignore_commas=false
suffix=
$ignore_commas && suffix=_noCOMMA
id= #_april2018 or exp_lr_decay_k0.8
two_stage=false                 # one or two stage training
continue_with_previous=false    # continue training an existing model
update_datasets=true

. ./path.sh # root_* and $data defined as well here
. ./utils/parse_options.sh
. ./local/utils.sh
. ./local/array.sh

cleaned=$data/postprocessing
mkdir -p $cleaned/log

modeldir=$root_punctuation_modeldir/${d}
datadir=$root_punctuation_datadir/$d/first_stage$id
datadir_2nd_stage=$root_punctuation_datadir/$d/second_stage$id
mkdir -p $datadir/log $modeldir/log
$two_stage && mkdir -p $datadir_2nd_stage/log

# Save the info on the model in a file called info in the modeldir
if [ $two_stage = true ]; then
  echo "two stage training" > $modeldir/info
else
  echo "one stage training" > $modeldir/info
fi

if [ $ignore_commas = true ]; then
  echo "without commas" >> $modeldir/info
else
  echo "with commas" >> $modeldir/info
fi

# NOTE! Review! This is what I used for my test:
# Input data for 2nd stage training
# input_2nd_stage=$root_intermediate/all_sept2017
# ali_dir=$exp/tri4_ali
input_2nd_stage=$root_intermediate/all_jun2018
ali_dir=$exp/tri5_ali_train_des18_cleaned_sp
# Can't run make_pause_annotated.sh with this ali_dir unless I remove all the extra alignments from
# sp and data in okt2017 data set.
# Note! I should rather have a step where I find alignments for the segmented data.

source $CONDAPATH/activate thenv || error 11 ${error_array[11]};

if [ $stage -le -1 ]; then

  # # NOTE! Now I've changed such that data ready for punctuation preprocessing
  # # is created in prep_althingi_data.sh. So update!
  # echo "Clean and preprocess the training data"
  # utils/slurm.pl $datadir/log/prep_punct_data.log \
  #   punctuator/local/prep_punct_data.sh \
  #   --id $id --ignore-commas $ignore_commas \
  #   $cleaned $datadir $datadir_2nd_stage || exit 1;

  if [ $update_datasets = true ]; then
    # The following does not work if we are starting from scratch
    # It works if we are updating an existing punctuation training set and
    # have already cleaned everything for punctuation
    # It is also only for one stage training
    utils/slurm.pl $datadir/log/prep_and_update_punct_data.log \
      punctuator/local/prep_and_update_punct_data.sh \
	--ignore-commas $ignore_commas || exit 1;

  else
    # The following will use data as it is prepared by the clean_new_speech.sh
    utils/slurm.pl $datadir/log/prep_punct_data.log \
      punctuator/local/prep_punct_data2.sh \
      --id $id --ignore-commas $ignore_commas \
      text_PunctuationTraining.txt $datadir || exit 1;
  fi
  
  if [ $two_stage = true ]; then
    # Scripts called by this one have not been reviewed. I have not used the
    # 2nd stage data so far exept in a few tests.
    utils/slurm.pl --mem 8G --time 2-00 $datadir/log/prep_punct_data_2nd_stage.log \
      punctuator/local/prep_punct_data_2nd_stage.sh \
      --id $id --ignore-commas $ignore_commas \
      $input_2nd_stage $ali_dir $datadir_2nd_stage || exit 1;
  fi
  
fi

if [ $stage -le 1 ]; then

  if ! $continue_with_previous; then
    rm -r punctuator/processed_data &>/dev/null
  fi
  
  echo "Convert data"
  if [ $two_stage = true -a -e $datadir_2nd_stage/althingi.train.txt ]; then
    utils/slurm.pl --mem 12G --time 0-12:00 $datadir/log/data${id}${suffix}_w2nd_stage.log \
      python punctuator/data.py ${datadir} ${datadir_2nd_stage} || error 1 "punct: data.py w/2nd stage failed"
    #sbatch --get-user-env --mem 12G --time 0-12:00 --job-name=data_2nd_stage --output=$datadir/log/data${id}${suffix}_w2nd_stage.log --wrap="srun python punctuator/data.py ${datadir} ${datadir_2nd_stage}"
  else
    utils/slurm.pl --mem 12G --time 0-12:00 $datadir/log/data${id}${suffix}.log \
      python punctuator/data.py ${datadir} || error 1 "punct: data.py failed"
    #sbatch --get-user-env --mem 12G --time 0-12:00 --job-name=data_stage1 --output=$datadir/log/data${id}$suffix.log --wrap="srun python punctuator/data.py ${datadir}"
  fi
fi

if [ $stage -le 2 ]; then
 
  echo "Train the model using first stage data"
  utils/slurm.pl --gpu 1 --mem 12G --time 0-10:00 $modeldir/log/main_first_stage${id}$suffix.log \
    python punctuator/main.py $modeldir althingi${id}${suffix} 256 0.02 || error 1 "punct: main.py failed"
  #sbatch --get-user-env --job-name=main_first_stage --output=$modeldir/log/main_first_stage${id}$suffix.log --gres=gpu:1 --mem=12G --time=0-10:00 --wrap="srun python punctuator/main.py $modeldir althingi${id}${suffix} 256 0.02"

  if [ $two_stage = true -a -e $datadir_2nd_stage/althingi.train.txt ]; then
    echo "Train the 2nd stage"
    utils/slurm.pl --gpu 1 --mem 12G --time 0-10:00 $modeldir/log/main_2nd_stage${id}$suffix.log \
      python punctuator/main2.py $modeldir althingi${id}${suffix} 256 0.02 $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl || error 1 "punct: main2.py failed"
    #sbatch --job-name=main_2nd_stage --output=$datadir/log/main_2nd_stage${id}$suffix.log --gres=gpu:1 --mem=12G --time=0-10:00 --wrap="srun python punctuator/main2.py $modeldir althingi${id}${suffix} 256 0.02 $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl"
  fi
fi

if [ $stage -le 3 ]; then
  echo "Punctuate the dev and test sets using the 1st stage model"
  for dataset in dev test; do
    (
      utils/slurm.pl --mem 4G $modeldir/log/punctuator_1st_stage_$dataset.log \
        THEANO_FLAGS='device=cpu' python punctuator/punctuator_filein.py $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir}/althingi.${dataset}.txt ${datadir}/${dataset}_punctuated_stage1${id}${suffix}.txt  || error 1 "punct: punctuator_filein.py failed";
      ) &
    #sbatch --get-user-env --job-name=punctuator --mem=4G --wrap="THEANO_FLAGS='device=cpu' srun python punctuator/punctuator_filein.py $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir}/althingi.${d}.txt ${datadir}/${d}_punctuated_stage1${id}${suffix}.txt"
  done
  wait
  
  if [ $two_stage = true -a -e $datadir_2nd_stage/althingi.train.txt ]; then
    echo "Punctuate the dev and test sets using the 2nd stage model"
    for dataset in dev test; do
      (
	utils/slurm.pl --mem 4G $modeldir/log/punctuator_2nd_stage_${dataset}.log \
          THEANO_FLAGS='device=cpu' python punctuator/punctuator_filein.py $modeldir/Model_stage2_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir}/althingi.${dataset}.txt ${datadir}/${dataset}_punctuated_stage2${id}${suffix}.txt 1  || error 1 "punct: punctuator_filein.py failed on 2nd stage model";
      ) &
    done
    wait
    #sbatch --get-user-env --job-name=punctuator_2nd_stage --mem=4G --wrap="THEANO_FLAGS='device=cpu' srun python punctuator/punctuator_filein.py $modeldir/Model_stage2_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir_2nd_stage}/althingi.${dataset}.txt ${datadir_2nd_stage}/${dataset}_punctuated_stage1${id}${suffix}.txt 1"
  fi
fi

if [ $stage -le 4 ]; then
  echo "Calculate the prediction errors"
  for f in dev test; do
    (
      python punctuator/error_calculator.py \
        ${datadir}/althingi.${f}.txt \
        ${datadir}/${f}_punctuated_stage1${id}$suffix.txt \
        > ${modeldir}/${f}_error_stage1${id}$suffix.txt \
      || error 12 ${error_array[12]};
    ) &
  done
  
  if [ $two_stage = true -a -e $datadir_2nd_stage/althingi.train.txt ]; then
    for f in dev test; do
      (
        python punctuator/error_calculator.py \
          ${datadir}/althingi.${f}.txt \
          ${datadir}/${f}_punctuated_stage2${id}$suffix.txt \
          > ${modeldir}/${f}_error_stage2${id}$suffix.txt \
	|| error 12 ${error_array[12]};
      ) &
    done
    
  fi
fi

if [[ $(hostname -f) == terra.hir.is ]]; then
  source $CONDAPATH/deactivate
else
  conda $CONDAPATH/deactivate
fi

exit 0;

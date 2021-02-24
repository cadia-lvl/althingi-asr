#!/bin/bash -e

set -o pipefail

# Prepare data for paragraph model training, train the model, compare with the test sets and calculate the errors. NOTE! Need updating!
# Run from the s5 dir

stage=0
continue_with_previous=false    # continue training an existing model

. ./path.sh
. ./utils/parse_options.sh
. ./local/utils.sh
. ./local/array.sh

#date
d=$(date +'%Y%m%d')

# The root dirs are defined in conf/path.conf (set in path.sh)
transcript_dir=$root_paragraph_transcripts
transcripts_archive=$transcript_dir/archive
currentdata=$(ls -td $root_paragraph_datadir/2* | head -n1)
modeldir=$root_paragraph_modeldir/${d}
datadir=$root_paragraph_datadir/${d}
mkdir -p $transcripts_archive $datadir/log $modeldir/log

source $CONDAPATH/activate thenv || error 11 ${error_array[11]};

if [ $stage -le 0 ]; then

  n_trans=$(ls $transcript_dir/ | wc -l)
  if [ $n_trans -gt 1 ]; then
    echo "Combine new transcripts with the current training set"
    cat $currentdata/althingi.train.txt $transcript_dir/*.* | egrep -v '^\s*$' > $datadir/althingi.train.txt
    mv -t $transcripts_archive $transcript_dir/*.*
    cp $currentdata/althingi.dev.txt $datadir/althingi.dev.txt
    cp $currentdata/althingi.test.txt $datadir/althingi.test.txt
  else
    echo "There are no new transcripts to add to the paragraph model"
    exit 0;
  fi
fi

# Check the number of paragraphs I have
#sed -r 's:EOP:\n:g' ${dir}/althingi.dev.txt | awk '{print NF}' | awk '{ sum += $1 } END { if (NR > 0) print sum / NR }'

if [ $stage -le 1 ]; then

  if ! $continue_with_previous; then
    rm -r paragraph/processed_data &>/dev/null
  fi

  echo "Process data" # I need to do this differently. Otherwise the insertion of paragraphs will be way to slow
  utils/slurm.pl --mem 12G $datadir/log/data.log \
    python paragraph/data.py ${datadir} || exit 1;
fi

if [ $stage -le 2 ]; then
  echo "Train the model"
  utils/slurm.pl --gpu 1 --mem 12G --time 0-10:00 $datadir/log/main.log \
    python paragraph/main.py $modeldir althingi_paragraph 256 0.02 || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "Insert paragraph tokens into the dev and test sets using the 1st stage model"
  for dataset in dev test; do
    (
      utils/slurm.pl --mem 8G --time 1-00:00 ${datadir}/log/${dataset}_paragraphed.log \
        cat ${datadir}/althingi.$dataset.txt \| THEANO_FLAGS='device=cpu' python paragraph/paragrapher.py $modeldir/Model_althingi_paragraph_h256_lr0.02.pcl ${datadir}/${dataset}_paragraphed.txt || exit 1;
    ) &
  done
  wait
  #sbatch --export=datadir=$datadir,modeldir=$modeldir paragraph/local/run_paragrapher.sh
fi

if [ $stage -le 4 ]; then
  echo "Calculate the prediction errors"

  for d in dev test; do
    (
      python paragraph/error_calculator.py \
        ${datadir}/althingi.$d.txt \
        ${datadir}/${d}_paragraphed.txt \
        > ${modeldir}/${d}_error.txt \
      || error 12 ${error_array[12]};
    ) &
  done
fi

if [[ $(hostname -f) == terra.hir.is ]]; then
  source $CONDAPATH/deactivate
else
  conda $CONDAPATH/deactivate
fi

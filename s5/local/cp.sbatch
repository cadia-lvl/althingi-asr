#! /bin/bash

# To run: sbatch local/cp.sbatch

. ./path.sh

d=$(date +'%Y%m%dT%H:%M:%S')
logdir=$root_logdir/cp_to_decodingASR
mkdir -p $logdir

srun -n1 --exclusive local/cp_to_decodingASR.sh &> $logdir/copy.$d.log

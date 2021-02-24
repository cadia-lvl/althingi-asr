#! /bin/bash
#
#SBATCH --get-user-env
#SBATCH --mem=25G

# To run: sbatch --export=stage=$stage local/new_speeches/run_LM_update.sbatch

. ./path.sh

d=$(date +'%Y%m%dT%H:%M:%S')
logdir=$root_logdir/update_LM_and_graph
mkdir -p $logdir

srun -n1 --exclusive local/new_speeches/update_LM_and_graph.sh --stage $stage &> $logdir/update.$d.log

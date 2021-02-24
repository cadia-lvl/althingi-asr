#! /bin/bash
#
#SBATCH --ntasks=4
#SBATCH --get-user-env

for d in dev test
do
  (
    srun sh -c "cat ${datadir}/althingi.$d.txt | THEANO_FLAGS='device=cpu' python punctuator/punctuator.py $modeldir/Model_althingi${id}${suffix}_h256_lr0.02.pcl ${datadir}/${d}_punctuated_stage1${id}${suffix}_new.txt &>${datadir}/log/${d}_punctuated_stage1${id}${suffix}.log" || exit 1;
    ) &
done

exit 0;


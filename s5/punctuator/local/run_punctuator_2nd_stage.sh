#! /bin/bash
#
#SBATCH --ntasks=8
#SBATCH --get-user-env

for d in dev test
do
  srun sh -c "cat ${datadir}/althingi.$d.txt | THEANO_FLAGS='device=cpu' python punctuator/punctuator.py $modeldir/Model_stage2_althingi_${id}${suffix}_h256_lr0.02.pcl ${datadir}/${d}_punctuated_stage1_${id}${suffix}.txt 1 &>${datadir}/log/${d}_punctuated_stage2_${id}${suffix}.log" &
done
wait

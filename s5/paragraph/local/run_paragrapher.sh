#! /bin/bash
#
#SBATCH --ntasks=8
#SBATCH --get-user-env

for d in dev test
do
  srun --nodelist=terra sh -c "cat ${datadir}/althingi.$d.txt | THEANO_FLAGS='device=cpu' python paragraph/paragrapher.py $modeldir/Model_althingi_paragraph_h256_lr0.02.pcl ${datadir}/${d}_paragraphed.txt &>${datadir}/log/${d}_paragraphed.log" &
done

exit 0;

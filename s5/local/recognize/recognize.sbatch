#! /bin/bash
#
#SBATCH --get-user-env

# Declare the variables
# To run: sbatch --export=audio=$audio,outdir=$outdir,trim=$trim,rnnlm=$rnnlm local/recognize/recognize.sbatch

speechname=$(basename "$audio")
speechname="${speechname%.*}" # remove the extension
mkdir -p $outdir/log

srun -n1 --exclusive local/recognize/recognize.sh --trim $trim --rnnlm $rnnlm $audio $outdir &> $outdir/log/$speechname.log


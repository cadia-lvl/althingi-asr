#!/bin/bash
#
#SBATCH --job-name=main_first_stage
#SBATCH --output=main_first_stage.log
#SBATCH --gres=gpu:1
#SBATCH --mem=12G
#SBATCH --time=0-10:00
#SBATCH --nodelist=terra

# import variables with: sbatch --export=id=$id,suffix=$suffix run_main.sh

srun python main.py althingi_${id}$suffix 256 0.02

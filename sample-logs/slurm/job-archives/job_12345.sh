#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err
#SBATCH --time=01:00:00
#SBATCH --partition=compute
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=user@example.com

# Load required modules
module load gcc/9.3.0
module load openmpi/4.1.0

# Set working directory
cd $SLURM_SUBMIT_DIR

# Print job information
echo "Job started at: $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on nodes: $SLURM_JOB_NODELIST"
echo "Number of tasks: $SLURM_NTASKS"
echo "CPUs per task: $SLURM_CPUS_PER_TASK"

# Run the main computation
echo "Starting parallel computation..."
mpirun -np $SLURM_NTASKS ./my_parallel_app input.dat

# Check exit status
if [ $? -eq 0 ]; then
    echo "Job completed successfully"
else
    echo "Job failed with error code $?"
    exit 1
fi

echo "Job finished at: $(date)"

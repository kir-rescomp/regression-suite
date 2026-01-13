#!/bin/bash
# hpc_regression_test.sh
# Run before and after GPFS upgrade

set -e

module purge
module load IOR/4.0.0-gompi-2023a jq/1.8.1-GCCcore-12.3.0 jq/1.8.1-GCCcore-12.3.0

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TESTDIR="/gpfs/$USER/regression_test_${TIMESTAMP}"
RESULTS_DIR="$HOME/regression_results"
RESULTS_FILE="${RESULTS_DIR}/results_${TIMESTAMP}.json"

# Test parameters
IOR_NODES=$SLURM_NNODES             # Adjust to your cluster
IOR_TASKS_PER_NODE=4
MDTEST_TASKS=8
FILESIZE="16g"           # Per process for single-client
FILESIZE_MULTI="4g"      # Per process for multi-client
BLOCKSIZE="1m"

mkdir -p $TESTDIR $RESULTS_DIR
cd $TESTDIR

# Start JSON output
cat > $RESULTS_FILE << EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "test_directory": "$TESTDIR",
  "tests": {
EOF

echo "=========================================="
echo "HPC Regression Test Suite"
echo "Timestamp: $TIMESTAMP"
echo "Results: $RESULTS_FILE"
echo "=========================================="

# Helper function to add JSON entry
add_result() {
    local test_name=$1
    local value=$2
    local unit=$3
    echo "    \"$test_name\": {\"value\": $value, \"unit\": \"$unit\"}," >> $RESULTS_FILE
}

#===========================================
# GPFS I/O TESTS
#===========================================

echo -e "\n[1/7] Single-client sequential write..."
OUTPUT=$(srun -n 1 ior -w -o ${TESTDIR}/ior_single -t $BLOCKSIZE -b $FILESIZE -F 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
echo "  Write: $WRITE_BW MB/s"
add_result "gpfs_single_write" $WRITE_BW "MB/s"


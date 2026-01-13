#!/bin/bash -e
# hpc_regression_test.sh
# Run before and after GPFS upgrade

#SBATCH --job-name        regression-test
#SBATCH --nodes           4
#SBATCH --mem             16G
#SBATCH --ntasks-per-node 4
#SBATCH --output          slog/%j.out
#SBATCH --time            00:30:00

module purge
module load IOR/4.0.0-gompi-2023a jq/1.8.1-GCCcore-12.3.0 OSU-Micro-Benchmarks/7.5.2-gompi-2023a

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TESTDIR="..somepath/RESULTS/regression_test_${TIMESTAMP}"
RESULTS_DIR="....somepath/RESULTS"
RESULTS_FILE="${RESULTS_DIR}/results_${TIMESTAMP}.json"

# Test parameters
IOR_NODES=$SLURM_NNODES
IOR_TASKS_PER_NODE=4
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
  "nodes": $IOR_NODES,
  "test_directory": "$TESTDIR",
  "tests": {
EOF

echo "=========================================="
echo "HPC Regression Test Suite"
echo "Timestamp: $TIMESTAMP"
echo "Nodes: $IOR_NODES"
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

echo -e "\n[1/6] Single-client sequential I/O..."
OUTPUT=$(srun -n 1 ior -w -r -o ${TESTDIR}/ior_single -t $BLOCKSIZE -b $FILESIZE -F 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
READ_BW=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Write: $WRITE_BW MB/s"
echo "  Read: $READ_BW MB/s"
add_result "gpfs_single_write" $WRITE_BW "MB/s"
add_result "gpfs_single_read" $READ_BW "MB/s"
rm -f ${TESTDIR}/ior_single.*

echo -e "\n[2/6] Multi-client parallel I/O (file-per-process)..."
TOTAL_TASKS=$((IOR_NODES * IOR_TASKS_PER_NODE))
OUTPUT=$(srun -n $TOTAL_TASKS ior -w -r -o ${TESTDIR}/ior_multi -t $BLOCKSIZE -b $FILESIZE_MULTI -F 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
READ_BW=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Write ($TOTAL_TASKS tasks): $WRITE_BW MB/s"
echo "  Read ($TOTAL_TASKS tasks): $READ_BW MB/s"
add_result "gpfs_multi_write" $WRITE_BW "MB/s"
add_result "gpfs_multi_read" $READ_BW "MB/s"
rm -f ${TESTDIR}/ior_multi.*

echo -e "\n[3/6] Shared file I/O (tests GPFS locking)..."
OUTPUT=$(srun -n $TOTAL_TASKS ior -w -r -o ${TESTDIR}/ior_shared -t $BLOCKSIZE -b 1g 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
READ_BW=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Shared write: $WRITE_BW MB/s"
echo "  Shared read: $READ_BW MB/s"
add_result "gpfs_shared_write" $WRITE_BW "MB/s"
add_result "gpfs_shared_read" $READ_BW "MB/s"
rm -f ${TESTDIR}/ior_shared

echo -e "\n[4/6] Small block I/O (64KB blocks)..."
OUTPUT=$(srun -n $((TOTAL_TASKS/2)) ior -w -r -o ${TESTDIR}/ior_small -t 64k -b 1g -F 2>&1)
SMALL_WRITE=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
SMALL_READ=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Small write: $SMALL_WRITE MB/s"
echo "  Small read: $SMALL_READ MB/s"
add_result "gpfs_small_write" $SMALL_WRITE "MB/s"
add_result "gpfs_small_read" $SMALL_READ "MB/s"
rm -f ${TESTDIR}/ior_small.*

#===========================================
# NETWORK TESTS
#===========================================

echo -e "\n[5/6] Network bandwidth test..."
OUTPUT=$(srun -N 2 -n 2 --ntasks-per-node=1 osu_bw 2>&1 | tail -1)
NET_BW=$(echo "$OUTPUT" | awk '{print $2}')
echo "  Network bandwidth: $NET_BW MB/s"
add_result "network_bandwidth" $NET_BW "MB/s"

echo -e "\n[6/6] Network latency test..."
OUTPUT=$(srun -N 2 -n 2 --ntasks-per-node=1 osu_latency 2>&1 | grep "^8 " || echo "8 0")
NET_LAT=$(echo "$OUTPUT" | awk '{print $2}')
echo "  Latency (8 bytes): $NET_LAT μs"
add_result "network_latency" $NET_LAT "microseconds"

#===========================================
# Finalize JSON
#===========================================

# Remove trailing comma from last entry
sed -i '$ s/,$//' $RESULTS_FILE

cat >> $RESULTS_FILE << EOF
  }
}
EOF

# Cleanup
cd $HOME
rm -rf $TESTDIR

echo -e "\n=========================================="
echo "Test complete!"
echo "Results saved to: $RESULTS_FILE"
echo "=========================================="

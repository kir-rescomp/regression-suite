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

echo "[1/7] Single-client sequential read..."
OUTPUT=$(srun -n 1 ior -r -o ${TESTDIR}/ior_single -t $BLOCKSIZE -b $FILESIZE -F 2>&1)
READ_BW=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Read: $READ_BW MB/s"
add_result "gpfs_single_read" $READ_BW "MB/s"
rm -f ${TESTDIR}/ior_single.*

echo -e "\n[2/7] Multi-client parallel write (file-per-process)..."
TOTAL_TASKS=$((IOR_NODES * IOR_TASKS_PER_NODE))
OUTPUT=$(srun -n $TOTAL_TASKS ior -w -o ${TESTDIR}/ior_multi -t $BLOCKSIZE -b $FILESIZE_MULTI -F 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
echo "  Write ($TOTAL_TASKS tasks): $WRITE_BW MB/s"
add_result "gpfs_multi_write" $WRITE_BW "MB/s"

echo "[2/7] Multi-client parallel read (file-per-process)..."
OUTPUT=$(srun -n $TOTAL_TASKS ior -r -o ${TESTDIR}/ior_multi -t $BLOCKSIZE -b $FILESIZE_MULTI -F 2>&1)
READ_BW=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Read ($TOTAL_TASKS tasks): $READ_BW MB/s"
add_result "gpfs_multi_read" $READ_BW "MB/s"
rm -f ${TESTDIR}/ior_multi.*

echo -e "\n[3/7] Shared file write (tests GPFS locking)..."
OUTPUT=$(srun -n $TOTAL_TASKS ior -w -o ${TESTDIR}/ior_shared -t $BLOCKSIZE -b 1g 2>&1)
WRITE_BW=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
echo "  Shared write: $WRITE_BW MB/s"
add_result "gpfs_shared_write" $WRITE_BW "MB/s"
rm -f ${TESTDIR}/ior_shared

echo -e "\n[4/7] Small block I/O (64KB blocks)..."
OUTPUT=$(srun -n $((TOTAL_TASKS/2)) ior -w -r -o ${TESTDIR}/ior_small -t 64k -b 1g -F 2>&1)
SMALL_WRITE=$(echo "$OUTPUT" | grep "write" | awk '{print $3}')
SMALL_READ=$(echo "$OUTPUT" | grep "read" | awk '{print $3}')
echo "  Small write: $SMALL_WRITE MB/s"
echo "  Small read: $SMALL_READ MB/s"
add_result "gpfs_small_write" $SMALL_WRITE "MB/s"
add_result "gpfs_small_read" $SMALL_READ "MB/s"
rm -f ${TESTDIR}/ior_small.*

echo -e "\n[5/7] Metadata operations (mdtest)..."
OUTPUT=$(srun -n $MDTEST_TASKS mdtest -n 10000 -d ${TESTDIR}/mdtest -F 2>&1)
CREATE_OPS=$(echo "$OUTPUT" | grep "File creation" | awk '{print $3}')
STAT_OPS=$(echo "$OUTPUT" | grep "File stat" | awk '{print $3}')
REMOVE_OPS=$(echo "$OUTPUT" | grep "File removal" | awk '{print $3}')
echo "  Create: $CREATE_OPS ops/sec"
echo "  Stat: $STAT_OPS ops/sec"
echo "  Remove: $REMOVE_OPS ops/sec"
add_result "gpfs_md_create" $CREATE_OPS "ops/sec"
add_result "gpfs_md_stat" $STAT_OPS "ops/sec"
add_result "gpfs_md_remove" $REMOVE_OPS "ops/sec"

#===========================================
# NETWORK TESTS
#===========================================

echo -e "\n[6/7] Network bandwidth test..."
# Using MPI bandwidth test (works on any interconnect)
OUTPUT=$(srun -n 2 --map-by node osu_bw 2>&1 | tail -1)
NET_BW=$(echo "$OUTPUT" | awk '{print $2}')
echo "  Network bandwidth: $NET_BW MB/s"
add_result "network_bandwidth" $NET_BW "MB/s"

echo -e "\n[7/7] Network latency test..."
OUTPUT=$(srun -n 2 --map-by node osu_latency 2>&1 | grep "^8 " || echo "8 0")
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

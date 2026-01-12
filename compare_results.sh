#!/bin/bash
# compare_results.sh
# Compare pre and post upgrade results

if [ $# -ne 2 ]; then
    echo "Usage: $0 <before_results.json> <after_results.json>"
    exit 1
fi

BEFORE=$1
AFTER=$2

echo "=========================================="
echo "GPFS Upgrade Regression Analysis"
echo "=========================================="
echo "Before: $(jq -r '.date' $BEFORE)"
echo "After:  $(jq -r '.date' $AFTER)"
echo ""

# Function to compare values and calculate percentage difference
compare_metric() {
    local name=$1
    local unit=$2
    local higher_better=$3  # 1 if higher is better, 0 if lower is better
    
    local before=$(jq -r ".tests[\"$name\"].value" $BEFORE)
    local after=$(jq -r ".tests[\"$name\"].value" $AFTER)
    
    if [ "$before" = "null" ] || [ "$after" = "null" ]; then
        echo "  $name: MISSING DATA"
        return
    fi
    
    local diff=$(echo "scale=2; $after - $before" | bc)
    local pct=$(echo "scale=2; ($after - $before) / $before * 100" | bc)
    
    # Determine status
    local status="✓"
    local color=""
    if [ "$higher_better" -eq 1 ]; then
        if (( $(echo "$pct < -10" | bc -l) )); then
            status="✗ REGRESSION"
            color="\033[0;31m"  # Red
        elif (( $(echo "$pct < -5" | bc -l) )); then
            status="⚠ WARNING"
            color="\033[0;33m"  # Yellow
        elif (( $(echo "$pct > 5" | bc -l) )); then
            status="✓ IMPROVED"
            color="\033[0;32m"  # Green
        fi
    else
        # Lower is better (latency)
        if (( $(echo "$pct > 10" | bc -l) )); then
            status="✗ REGRESSION"
            color="\033[0;31m"
        elif (( $(echo "$pct > 5" | bc -l) )); then
            status="⚠ WARNING"
            color="\033[0;33m"
        elif (( $(echo "$pct < -5" | bc -l) )); then
            status="✓ IMPROVED"
            color="\033[0;32m"
        fi
    fi
    
    printf "${color}%-40s: %10.2f → %10.2f %-12s (%+.1f%%) %s\033[0m\n" \
        "$name" "$before" "$after" "$unit" "$pct" "$status"
}

echo "GPFS Performance:"
echo "----------------------------------------"
compare_metric "gpfs_single_write" "MB/s" 1
compare_metric "gpfs_single_read" "MB/s" 1
compare_metric "gpfs_multi_write" "MB/s" 1
compare_metric "gpfs_multi_read" "MB/s" 1
compare_metric "gpfs_shared_write" "MB/s" 1
compare_metric "gpfs_small_write" "MB/s" 1
compare_metric "gpfs_small_read" "MB/s" 1

echo ""
echo "GPFS Metadata Performance:"
echo "----------------------------------------"
compare_metric "gpfs_md_create" "ops/sec" 1
compare_metric "gpfs_md_stat" "ops/sec" 1
compare_metric "gpfs_md_remove" "ops/sec" 1

echo ""
echo "Network Performance:"
echo "----------------------------------------"
compare_metric "network_bandwidth" "MB/s" 1
compare_metric "network_latency" "μs" 0

echo ""
echo "=========================================="
echo "Summary:"
echo "----------------------------------------"

# Count regressions
REGRESSIONS=$(
    for metric in gpfs_single_write gpfs_single_read gpfs_multi_write gpfs_multi_read \
                  gpfs_shared_write gpfs_small_write gpfs_small_read \
                  gpfs_md_create gpfs_md_stat gpfs_md_remove network_bandwidth; do
        before=$(jq -r ".tests[\"$metric\"].value" $BEFORE)
        after=$(jq -r ".tests[\"$metric\"].value" $AFTER)
        if [ "$before" != "null" ] && [ "$after" != "null" ]; then
            pct=$(echo "scale=2; ($after - $before) / $before * 100" | bc)
            if (( $(echo "$pct < -10" | bc -l) )); then
                echo "1"
            fi
        fi
    done | wc -l
)

if [ "$REGRESSIONS" -eq 0 ]; then
    echo "✓ No significant regressions detected"
    echo "  All metrics within acceptable range (>-10%)"
else
    echo "✗ $REGRESSIONS metric(s) show significant regression (>10% decrease)"
    echo "  Review failed metrics above"
fi

echo "=========================================="

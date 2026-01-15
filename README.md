<p align="center">
  <img src="./assets/images/regression_suite_logo.png" alt="regression-logo" width="300"/>
</p>


## Compare resutls

Example:

```bash
./compare_results.sh \
    ~/regression_results/results_20250113_*.json \
    ~/regression_results/results_20250120_*.json
```

## Extend the runtime of the tests

### Option 1  - Double/Triple the data

This can be done by increasing `FILESIZE` and `FILESIZE_MULTI` attributes

### Option 2  - Add more iterations

IOR Supports running multiple iterations to get more stable averages 

```bash
srun -n 1 ior -w -r -i 3 -o ${TESTDIR}/ior_single -t $BLOCKSIZE -b $FILESIZE -F
#                   ^^^
#                   Run 3 times and average
```

#!/bin/bash

./atx-batch-launcher.sh \
  --csv-file "sample-repos.csv" \
  --mode "parallel" \
  --max-jobs 8 \
  --output-dir "./batch_results" \
  --clone-dir "./batch_repos"

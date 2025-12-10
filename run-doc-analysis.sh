#!/bin/bash

./atx-batch-launcher.sh \
  --csv-file "repos.csv" \
  --mode "parallel" \
  --max-jobs 8 \
  --output-dir "./batch_results_doc" \
  --clone-dir "./batch_repos_doc"

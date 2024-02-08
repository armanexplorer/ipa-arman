#!/bin/bash

set -e

function download_data(){
    # download experiment logs
    # gsutil -m cp -rn gs://ipa-results-1/results.zip ~/ipa-private/data
    # unzip ~/ipa-private/data/results.zip
    # mv results ~/ipa-private/data
    # rm ~/ipa-private/data/results.zip

    # create buckets
    mc mb minio/huggingface
    mc mb minio/torchhub

    mkdir ~/temp-model-dir

    # download ml models from google storage
    # -r for directory, -n for prevent overwriting, and -m for multiprocessing
    gsutil -m cp -rn 'gs://ipa-models/myshareddir/torchhub' ~/temp-model-dir
    gsutil -m cp -rn 'gs://ipa-models/myshareddir/huggingface' ~/temp-model-dir

    # copy models to minio
    mc cp -r ~/temp-model-dir/huggingface/* minio/huggingface
    mc cp -r ~/temp-model-dir/torchhub/* minio/torchhub

    rm -r ~/temp-model-dir

    # download lstm trained model
    # gsutil -m cp -r gs://ipa-models/lstm ~/ipa-private/data
}

download_data

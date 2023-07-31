# Abstract
**Abstract** [IPA: Inference Pipeline Adaptation to Achieve High Accuracy and Cost-Efficiency](/paper/paper.pdf)

Efficiently optimizing multi-model inference pipelines for fast, accurate, and cost-effective inference is a crucial challenge in ML production systems, given their tight end-to-end latency requirements. To simplify the exploration of the vast and intricate trade-off space of accuracy and cost in inference pipelines, providers frequently opt to consider one of them. However, the challenge lies in reconciling accuracy and cost trade-offs.
To address this challenge and propose a solution to efficiently manage model variants in inference pipelines. Model variants are different versions of pre-trained models for the same Deep Learning task with variations in resource requirements, latency, and accuracy. We present IPA, an online deep-learning Inference Pipeline Adaptation system that efficiently leverages model variants for each deep learning task. IPA dynamically configures batch size, replication, and model variants to optimize accuracy, minimize costs, and meet user-defined latency SLAs using Integer Programming. It supports multi-objective settings for achieving different trade-offs between accuracy and cost objectives while remaining adaptable to varying workloads and dynamic traffic patterns. Extensive experiments on a Kubernetes implementation with five real-world inference pipelines demonstrate that IPA improves normalized accuracy by up to 35% with a minimal cost increase of less than 5%.

# Project Setup Steps
1. Go to the [infrastructure](/infrastructure/README.md) for the guide to set up the K8S cluster and related depandancies, the complete installtion takes ~30 minutes.

2. The log of the experiments presented in the paper are avialable in the directory [data/results/final](data/results/final) to draw the figures in the paper go to [experiments/runner/notebooks](experiments/runner/notebooks) to draw each figure presented in the paper. Each figure is organized in a different Jupyter notebook e.g. to draw the figure 8 of the paper pipeline figure [experiments/runner/notebooks/paper-fig8-e2e-video.ipynb](experiments/runner/notebooks/paper-fig8-e2e-video.ipynb)

3. If you want to check main paper e2e experiments (figure 8-12) do the following steps:
    1. IPA use config yaml files for running experiments, the config files used in the paper are stored in the `data/configs/final` folder.
    2. To Run a specific experiment move to the [experiments/runner](experiments/runner) directory and run `python runner_script.py --config-name <name of one of the config files in data/configs/final>`
    3. In the chosen config file change the metaseries and series number
    4. Go back to the step two and draw the figure

#!/bin/bash

# colors
INFO='\e[34m'
ERROR='\e[31m'
RESET='\e[0m'

set -e

install_packages() {
    # if [ -z "$1" ];
    # then
    #     echo "You must provide public IP: ./build.sh PUBLIC_IP"
    #     exit 0; 
    # fi

    hack_dir="$HOME/ipa/infrastructure/hack"
    zsh_script="${hack_dir}/zsh.sh"
    repos_script="${hack_dir}/repos.sh"
    kubernetes_script="${hack_dir}/kubernetes.sh"
    utilities_script="${hack_dir}/utilities.sh"
    storage_script="${hack_dir}/storage.sh"
    gurobi_script="${hack_dir}/gurobi.sh"
    download_data="${hack_dir}/download_data.sh"
    jupyters="${hack_dir}/jupyters.sh"

    # prevent from deattaching from shell
    # sh -c "$zsh_script" "" --unattended
    # echo -e "${INFO}zsh.sh completed!${RESET}"
    
    source "$repos_script"
    echo -e "${INFO}repos.sh completed!${RESET}"
    
    bash "$kubernetes_script"
    echo -e "${INFO}kubernetes.sh completed${RESET}"
    
    bash "$utilities_script"
    echo -e "${INFO}utilities.sh completed${RESET}"
    
    bash "$storage_script" "$1"
    echo -e "${INFO}storage.sh completed${RESET}"
    
    # bash "$gurobi_script"
    # echo "gurobi.sh completed"
    
    bash "$download_data"
    echo -e "${INFO}download_data.sh completed${RESET}"
    
    # bash "$jupyters"
    # echo "jupyters.sh completed"


    echo -e "${INFO}----------- Installation of all packages and dependencies completed! --------${RESET}"
}

# Call the function with the public IP as argument
install_packages "$1"

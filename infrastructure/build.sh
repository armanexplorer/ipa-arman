#!/bin/bash

# colors
INFO='\e[34m'
ERROR='\e[31m'
RESET='\e[0m'

set -e

if [ "$(lsb_release -rs)" = "20.04" ] && [ "$(lsb_release -is)" = "Ubuntu" ]; then
    echo "--------------------- Perfect! This is Ubuntu 20.04 ✅️ ---------------------"
else
    echo "⚠️ WARNING: We strongly recommend using Ubuntu20.04 for this script!\nSome features may not work correctly becaues the host OS is $(lsb_release -is)$(lsb_release -rs)"
fi

install_packages() {
  hack_dir="$HOME/ipa/infrastructure/hack"
  zsh_script="${hack_dir}/zsh.sh"
  repos_script="${hack_dir}/repos.sh"
  kubernetes_script="${hack_dir}/kubernetes.sh"
  utilities_script="${hack_dir}/utilities.sh"
  storage_script="${hack_dir}/storage.sh"
  gurobi_script="${hack_dir}/gurobi.sh"
  download_data="${hack_dir}/download_data.sh"
  jupyters="${hack_dir}/jupyters.sh"

  echo -e "${INFO}----------- Installation of all packages and dependencies --------${RESET}"

  echo -e "***** ${INFO}repos.sh${RESET} *****"
  source "$repos_script"
  echo -e "***** ${INFO}repos.sh completed!${RESET} *****"

  echo -e "***** ${INFO}kubernetes.sh${RESET} *****"
  source "$kubernetes_script"
  echo -e "***** ${INFO}kubernetes.sh completed!${RESET} *****"

  echo -e "***** ${INFO}utilities.sh${RESET} *****"
  source "$utilities_script"
  echo -e "***** ${INFO}utilities.sh completed!${RESET} *****"

  echo -e "***** ${INFO}storage.sh${RESET} *****"
  source "$storage_script" "$1"
  echo -e "***** ${INFO}storage.sh completed!${RESET} *****"

  echo -e "***** ${INFO}download_data.sh${RESET} *****"
  source "$download_data"
  echo -e "***** ${INFO}download_data.sh completed!${RESET} *****"

  echo -e "${INFO}----------- Installation of all packages and dependencies completed! --------${RESET}"
}

# Call the function with the public IP as argument
install_packages "$1"

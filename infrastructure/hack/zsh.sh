#!/bin/bash

set -e

install_zsh() {
    sudo apt update && sudo apt install -y zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions)/' ~/.zshrc
    sudo chsh -s "$(which zsh)" $USER
    exec zsh
}

customize_zsh() {
    # customize zsh
    cp $ZSH/themes/$ZSH_THEME.zsh-theme $ZSH_CUSTOM/themes/
    sed -i.bak 's/^PROMPT=.*/PROMPT="%{$fg_bold[green]%}[%*] %(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} ) %{$fg[cyan]%}%~%{$reset_color%}"/' $ZSH_CUSTOM/themes/$ZSH_THEME.zsh-theme
    exec zsh
}

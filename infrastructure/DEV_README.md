# install zsh
```bash
source ~/ipa/infrastructure/hack/zsh.sh
install_zsh

source ~/ipa/infrastructure/hack/zsh.sh
customize_zsh
```

# install main inferastructure
```bash
~/ipa/infrastructure/build.sh
```

# NOTE
The `Processing triggers for man-db` takes long times in the `man-db` versions under the `2.10`. In this case, you could make the auto re-build cache off by the following command:
```bash
sudo mv /var/lib/man-db/auto-update /var/lib/man-db/auto-update.bak
```
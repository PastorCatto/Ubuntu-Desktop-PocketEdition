#!/bin/bash
# Mobuntu RC15 — setup-ui.sh
# Runs inside chroot. Env: UI_NAME, UI_DM, UBUNTU_RELEASE, BUILD_COLOR
set -e
export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing UI: $UI_NAME (DM: $UI_DM)"

case "$UI_NAME" in
phosh)
    apt-get install -y phosh greetd
    apt-get install -y squeekboard 2>/dev/null || \
        apt-get install -y phosh-osk-stub 2>/dev/null || \
        echo ">>> WARNING: No OSK package available"
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"/usr/bin/phosh\"\nuser = \"greeter\"\n" \
        > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
ubuntu-desktop-minimal)
    apt-get install -y ubuntu-desktop-minimal
    systemctl enable gdm3
    mkdir -p /etc/dconf/db/local.d
    cat > /etc/dconf/db/local.d/01-mobuntu-theme << DCONF
[org/gnome/desktop/interface]
accent-color='${BUILD_COLOR}'

[org/gnome/nautilus/desktop]
volumes-visible=false
DCONF
    dconf update 2>/dev/null || true
    ;;
unity)
    apt-get install -y ubuntu-unity-desktop
    systemctl enable lightdm
    ;;
plasma-desktop)
    apt-get install -y kde-plasma-desktop
    systemctl enable sddm
    ;;
plasma-mobile)
    apt-get install -y plasma-mobile maliit-keyboard
    systemctl enable sddm
    ;;
lomiri)
    apt-get install -y lomiri squeekboard greetd
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"lomiri\"\nuser = \"greeter\"\n" \
        > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
*)
    echo ">>> Unknown UI '$UI_NAME', falling back to phosh"
    apt-get install -y phosh greetd
    apt-get install -y squeekboard 2>/dev/null || \
        apt-get install -y phosh-osk-stub 2>/dev/null || true
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"/usr/bin/phosh\"\nuser = \"greeter\"\n" \
        > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
esac

# Disable all DMs except the chosen one
for dm in gdm3 lightdm sddm greetd; do
    [ "$dm" != "$UI_DM" ] && systemctl disable "$dm" 2>/dev/null || true
done

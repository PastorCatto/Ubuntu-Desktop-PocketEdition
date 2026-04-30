#!/bin/sh

USERNAME="mobuntu"
PASSWORD="mobuntu1234"

adduser --gecos "${USERNAME}" --disabled-password --shell /bin/bash "${USERNAME}"
adduser "${USERNAME}" sudo

usermod -aG sudo,render,dialout,root,adm,cdrom,floppy,audio,dip,video,plugdev "${USERNAME}"

echo "${USERNAME}:1234" | chpasswd

echo "mobuntu" | tee /etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 mobuntu" | tee /etc/hosts

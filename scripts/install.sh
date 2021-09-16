#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

echo "Running as $USER"

# banner
echo -e "  ____      _                 ____  _  __"
echo -e " / ___|   _| |__   ___ _ __  | ___|| |/ /"
echo -e "| |  | | | | '_ \ / _ \ '__| |___ \| ' /"
echo -e "| |__| |_| | |_) |  __/ |     ___) | . \ "
echo -e " \____\__, |_.__/ \___|_|    |____/|_|\_\ "
echo -e "      |___/"
echo -e " __  __ _     _   _"
echo -e "|  \/  (_)___| |_| |__   ___  _ __ _ __"
echo -e "| |\/| | / __| __| '_ \ / _ \| '__| '_ \ "
echo -e "| |  | | \__ \ |_| |_) | (_) | |  | | | |"
echo -e "|_|  |_|_|___/\__|_.__/ \___/|_|  |_| |_|"
echo -e ""
echo "Running as $USER"

#git submodule update --init --recursive

mv ./mistborn-terraform-install /opt/mistborn

cd /opt/mistborn
# Check updates
echo "Checking updates"
### REPLACE IN PROD ####
#source ./scripts/subinstallers/check_updates.sh

# MISTBORN_DEFAULT_PASSWORD
source ./scripts/subinstallers/passwd.sh

# initial load update package list during check_updates.sh

# install figlet
sudo -E apt-get install -y figlet

# get os and distro
source ./scripts/subinstallers/platform.sh

# iptables
echo "Setting up firewall (iptables)"
if [ -f "/etc/iptables/rules.v4" ]; then
    echo "Caution: iptables rules exist."
    echo "Clearing existing iptables rules..."
    sudo rm -rf /etc/iptables/rules.v4
    sudo iptables -F
    sudo iptables -t nat -F
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo rm -rf /etc/iptables/rules.v6 || true
    sudo ip6tables -F || true
    sudo ip6tables -t nat -F || true
    sudo ip6tables -P INPUT ACCEPT || true
    sudo ip6tables -P FORWARD ACCEPT || true
fi

echo "Setting iptables rules..."
source ./scripts/subinstallers/iptables.sh

# SSH Server
sudo -E apt-get install -y openssh-server
#sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
#sudo sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
#sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
#sudo sed -i 's/PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo sed -i 's/#Port.*/Port 22/' /etc/ssh/sshd_config
SSH_PRT=$(echo $SSH_CLIENT | awk '{print $3}')
sudo sed -i "s/Port.*/Port $SSH_PRT/" /etc/ssh/sshd_config
sudo systemctl enable ssh
sudo systemctl restart ssh

# Additional tools fail2ban
sudo -E apt-get install -y dnsutils fail2ban

# Install kernel headers
sudo -E apt install -y linux-headers-$(uname -r)

# Wireugard
source ./scripts/subinstallers/wireguard.sh

# Docker
source ./scripts/subinstallers/docker.sh
sudo systemctl enable docker
sudo systemctl start docker

# Unattended upgrades
sudo -E apt-get install -y unattended-upgrades

# Cockpit
if [[ "$MISTBORN_INSTALL_COCKPIT" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    # install cockpit
    source ./scripts/subinstallers/cockpit.sh

    # set variable (that will be available in environment)
    MISTBORN_INSTALL_COCKPIT=Y
fi


figlet "Mistborn: Installing mistborn-cli"
sudo pip3 install -e ./modules/mistborn-cli

# Mistborn
# final setup vars

#IPV4_PUBLIC=$(ip -o -4 route show default | egrep -o 'dev [^ ]*' | awk '{print $2}' | xargs ip -4 addr show | grep 'inet ' | awk '{print $2}' | grep -o "^[0-9.]*"  | tr -cd '\11\12\15\40-\176' | head -1) # tail -1 to get last
IPV4_PUBLIC="10.2.3.1"


# generate production .env file
#if [ ! -d ./.envs/.production ]; then
./scripts/subinstallers/gen_prod_env.sh "$MISTBORN_DEFAULT_PASSWORD"
#fi

# unattended upgrades
sudo cp ./scripts/conf/20auto-upgrades /etc/apt/apt.conf.d/
sudo cp ./scripts/conf/50unattended-upgrades /etc/apt/apt.conf.d/

sudo systemctl stop unattended-upgrades
sudo systemctl daemon-reload
sudo systemctl restart unattended-upgrades

# setup Mistborn services

#if [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "raspbian" ]; then
#    # remove systemd-resolved lines
#    sudo sed -i '/.*systemd-resolved/d' /etc/systemd/system/Mistborn-base.service
#fi

sudo cp ./scripts/services/Mistborn-setup.service /etc/systemd/system/

# setup local volumes for pihole
sudo mkdir -p ../mistborn_volumes/
sudo chown -R root:root ../mistborn_volumes/
sudo mkdir -p ../mistborn_volumes/base/pihole/etc-pihole
sudo mkdir -p ../mistborn_volumes/base/pihole/etc-dnsmasqd
sudo mkdir -p ../mistborn_volumes/extra

# Traefik final setup (cockpit)
#cp ./compose/production/traefik/traefikv2.toml.template ./compose/production/traefik/traefik.toml

# setup tls certs
source ./scripts/subinstallers/openssl.sh
#sudo rm -rf ../mistborn_volumes/base/tls
#sudo mv ./tls ../mistborn_volumes/base/

# enable and run setup to generate .env
sudo systemctl enable Mistborn-setup.service
sudo systemctl start Mistborn-setup.service

# Download docker images while DNS is operable
sudo docker-compose -f base.yml pull || true
sudo docker-compose -f base.yml build

## disable systemd-resolved stub listener (creates symbolic link to /etc/resolv.conf)
if [ -f /etc/systemd/resolved.conf ]; then
    sudo sed -i 's/#DNSStubListener.*/DNSStubListener=no/' /etc/systemd/resolved.conf
    sudo sed -i 's/DNSStubListener.*/DNSStubListener=no/' /etc/systemd/resolved.conf
fi

## delete symlink if exists
if [ -L /etc/resolv.conf ]; then
    sudo rm /etc/resolv.conf
fi

## disable other DNS services
sudo systemctl stop systemd-resolved 2>/dev/null || true
sudo systemctl disable systemd-resolved 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# hostname in /etc/hosts
sudo grep -qF "$(hostname)" /etc/hosts && echo "$(hostname) already in /etc/hosts" || echo "127.0.1.1 $(hostname) $(hostname)" | sudo tee -a /etc/hosts

# resolve all *.mistborn domains
echo "address=/.mistborn/10.2.3.1" | sudo tee ../mistborn_volumes/base/pihole/etc-dnsmasqd/02-lan.conf

# ResolvConf (OpenResolv installed with Wireguard)
#sudo sed -i "s/#name_servers.*/name_servers=$IPV4_PUBLIC/" /etc/resolvconf.conf
sudo sed -i "s/#name_servers.*/name_servers=10.2.3.1/" /etc/resolvconf.conf
sudo sed -i "s/name_servers.*/name_servers=10.2.3.1/" /etc/resolvconf.conf
#sudo sed -i "s/#name_servers.*/name_servers=127.0.0.1/" /etc/resolvconf.conf
sudo resolvconf -u 1>/dev/null 2>&1

echo "backup up original volumes folder"
sudo mkdir -p ../mistborn_backup
sudo chmod 700 ../mistborn_backup
sudo tar -czf ../mistborn_backup/mistborn_volumes_backup.tar.gz ../mistborn_volumes 1>/dev/null 2>&1

# clean docker
echo "cleaning old docker volumes"
sudo systemctl stop Mistborn-base || true
sudo docker-compose -f /opt/mistborn/base.yml kill
sudo docker volume rm -f mistborn_production_postgres_data 2>/dev/null || true
sudo docker volume rm -f mistborn_production_postgres_data_backups 2>/dev/null || true
sudo docker volume rm -f mistborn_production_traefik 2>/dev/null || true
sudo docker volume prune -f 2>/dev/null || true

# clean Wireguard
echo "cleaning old wireguard services"
sudo ./scripts/env/wg_clean.sh

# start base service
sudo systemctl enable Mistborn-base.service
sudo systemctl start Mistborn-base.service
popd

figlet "Mistborn Installed"
echo "Watch Mistborn start: sudo journalctl -xfu Mistborn-base"
echo "Retrieve Wireguard default config for admin: sudo mistborn-cli getconf"

#!/bin/bash

#### ENV file

VAR_FILE=/opt/mistborn/.env

# load env variables

source /opt/mistborn/scripts/subinstallers/platform.sh

# setup env file
echo "" | sudo tee ${VAR_FILE}
sudo chown ubuntu:ubuntu ${VAR_FILE}
sudo chmod 600 ${VAR_FILE}

# MISTBORN_DNS_BIND_IP

MISTBORN_DNS_BIND_IP="10.2.3.1"
#if [ "$DISTRO" == "ubuntu" ] && [ "$VERSION_ID" == "20.04" ]; then
#    MISTBORN_DNS_BIND_IP="10.2.3.1"
#fi

echo "MISTBORN_DNS_BIND_IP=${MISTBORN_DNS_BIND_IP}" | sudo tee -a ${VAR_FILE}

# MISTBORN_BIND_IP

echo "MISTBORN_BIND_IP=10.2.3.1" | sudo tee -a ${VAR_FILE}

# MISTBORN_TAG
echo "MISTBORN_TAG=master | sudo tee -a ${VAR_FILE}

#### SERVICE files

# copy current service files to systemd (overwriting as needed)
sudo cp /opt/mistborn/scripts/services/Mistborn* /etc/systemd/system/

# set script user and owner
sudo find /etc/systemd/system/ -type f -name 'Mistborn*' | xargs sudo sed -i "s/User=root/User=ubuntu/"
#sudo find /etc/systemd/system/ -type f -name 'Mistborn*' | xargs sudo sed -i "s/ root:root / ubuntu:ubuntu /"

# reload in case the iface is not immediately set
sudo systemctl daemon-reload

#### install and base services
iface=$(ip -o -4 route show to default | egrep -o 'dev [^ ]*' | awk 'NR==1{print $2}' | tr -d '[:space:]')
## cannot be empty
while [[ -z "$iface" ]]; do
    sleep 2
    iface=$(ip -o -4 route show to default | egrep -o 'dev [^ ]*' | awk 'NR==1{print $2}' | tr -d '[:space:]')
done

# default interface
sudo find /etc/systemd/system/ -type f -name 'Mistborn*' | xargs sudo sed -i "s/DIFACE/$iface/"

echo "DIFACE=${iface}" | sudo tee -a ${VAR_FILE}

sudo systemctl daemon-reload

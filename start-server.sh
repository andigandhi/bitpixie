#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

function echo-info {
    echo -e "\e[34;1m[+]\e[0m \e[34mInfo: $1\e[0m" >&2
}

function echo-warning {
    echo -e "\e[31;1m[!] Warning: $1\e[0m" >&2
}

function printInfo {
  echo -e "\e[34;1mUsage:\e[0m"
  echo -e "\e[34;1m- Start PXE server: \e[0m \e[34m$0 pxe <interface>\e[0m"
  echo -e "\e[34;1m- Start SMB server: \e[0m \e[34m$0 smb <interface>\e[0m"
}


# Function to start the PXE and DHCP server
function start-pxe-server {
  interface=$1

  if [[ "$interface" = "" ]]; then
    echo-warning "No interface specified!"
    printInfo
    exit
  fi

  # Add IP address to interface
  sudo ip a add 10.13.37.100/24 dev $interface
  echo-info "Interface $interface has IP address 10.13.37.100/24"

  stop-servers

  # Start dnsmasq
  echo-info "Starting dnsmasq..."
  sudo dnsmasq --no-daemon --interface=$interface --dhcp-range=10.13.37.100,10.13.37.111,255.255.255.0,1h --dhcp-boot=bootmgfw.efi --enable-tftp --tftp-root=$SCRIPTPATH/PXE-Server
  echo-info "Stopping dnsmasq..."
}

# Function to start the SMBserver
function start-smb-server {
  interface=$1

  if [[ "$interface" = "" ]]; then
    echo-warning "No interface specified!"
    printInfo
    exit
  fi

  # Add IP address to interface
  sudo ip a add 10.13.37.100/24 dev $interface
  echo-info "Interface $interface has IP address 10.13.37.100/24"

  # Start dnsmasq
  echo-info "Starting smbserver.py..."
  sudo $(which smbserver.py) -smb2support smb "$SCRIPTPATH/PXE-Server/Boot"
  echo-info "Stopping smbserver.py..."
}

# Function to stop the servers
function stop-servers {
  echo-info "Killing all dnsmasq processes..."
  sudo killall dnsmasq
}


if [[ "$1" = "smb" ]]; then
  start-smb-server $2
  exit
elif [[ "$1" = "pxe" ]]; then
  start-pxe-server $2
  exit
else
  printInfo
  exit
fi

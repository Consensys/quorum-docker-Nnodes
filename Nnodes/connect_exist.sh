#!/bin/bash

function validateIP()
{
    local ip=$1
    local stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]; stat=$?
    fi
    return $stat
}

read -e -p "Enter external IP address: " host_ip

validateIP $host_ip

if [[ $? -ne 0 ]];then
  echo "Invalid IP Address ($host_ip)"
  exit 1
fi

mkdir outside
cp qdata_1/genesis.json outside/
cd outside


#!/bin/bash

# Use master nodes config
source ../.current_config

[ "$use_host_net" != "true" ] && echo "Must use host network in docker" && exit 1

master_rpc_start_port=$((rpc_start_port))
master_node_start_port=$((node_start_port))
master_raft_start_port=$((raft_start_port))
master_constellation_start_port=$((constellation_start_port))

#### Configuration options #############################################

# Port prefix
#port_range=62000

#rpc_start_port=$((port_range+100))
#node_start_port=$((port_range+200))
#raft_start_port=$((port_range+300))
#constellation_start_port=$((port_range+400))

# Old version
rpc_start_port=23100
node_start_port=24100
raft_start_port=25100
ws_start_port=26100
constellation_start_port=27100


# Master node IP
master_ip="172.16.2.169"

# VIP Subnet
subnet="192.168.61.0/24"

# Total nodes to deploy
outside_nodes=4

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=e1

node_name_prefix=test
auto_start_containers=false

########################################################################

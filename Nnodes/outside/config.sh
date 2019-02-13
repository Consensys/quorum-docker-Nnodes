#!/bin/bash

source ../.current_config
master_node_start_port=$node_start_port

#### Configuration options #############################################

# Port prefix
rpc_start_port=33000
node_start_port=36000
raft_start_port=39000

# Master node IP
master_ip="192.168.66.82"

# VIP Subnet
subnet="172.15.0.0/16"

# Total nodes to deploy
outside_nodes=3

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=e1

node_name_prefix=test
auto_start_containers=false

########################################################################

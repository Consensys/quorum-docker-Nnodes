#!/bin/bash

# Use master nodes config
source ../.current_config

master_rpc_start_port=$((port_range+100))
master_node_start_port=$((port_range+200))
master_raft_start_port=$((port_range+300))
master_constellation_start_port=$((port_range+400))

#### Configuration options #############################################

# Port prefix
port_range=62000

rpc_start_port=$((port_range+100))
node_start_port=$((port_range+200))
raft_start_port=$((port_range+300))
constellation_start_port=$((port_range+400))

# Use docker host network for RLP connection.
use_host_net=true

# Master node IP
master_ip="192.168.66.82"

# VIP Subnet
subnet="172.15.0.0/16"

# Total nodes to deploy
outside_nodes=3

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=e2

node_name_prefix=test
auto_start_containers=false

########################################################################

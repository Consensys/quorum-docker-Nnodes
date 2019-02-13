#!/bin/bash

#### Configuration options #############################################

# Port prefix
rpc_start_port=23000
node_start_port=26000
raft_start_port=29000

# VIP Subnet
subnet="172.14.0.0/16"

# Total nodes to deploy
total_nodes=5

# Signer nodes for Clique and IBFT
signer_nodes=4

# Consensus engine ex. raft, clique, istanbul
consensus=clique

# Block period for Clique and IBFT
block_period=0

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=n1

# Send some ether for pre-defined accounts
alloc_ether=true

node_name_prefix=master
auto_start_containers=false

########################################################################

[[ "$total_nodes" -lt "$signer_nodes" ]] && total_nodes=$signer_nodes
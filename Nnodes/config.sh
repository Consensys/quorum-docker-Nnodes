#!/bin/bash

#### Configuration options #############################################

# Port prefix
port_range=61000

#rpc_start_port=$((port_range+100))
#node_start_port=$((port_range+200))
#raft_start_port=$((port_range+300))
#constellation_start_port=$((port_range+400))

# Old version
rpc_start_port=23000
node_start_port=24000
raft_start_port=25000
ws_start_port=26000
constellation_start_port=27000

# Default port number
raft_port=50400
constellation_port=9000
rlp_port=30303
rpc_port=8545
ws_port=8546

#Disable constellation node
use_constellation=false

# VIP Subnet
subnet="172.14.0.0/16"

# Use docker host network for RLP connection.
use_host_net=true


# Interface IP for RLP listening when using docker host network
interface_ip="172.16.2.169"

# Total nodes to deploy
total_nodes=4

# Signer nodes for Clique and IBFT
signer_nodes=4

# Consensus engine ex. raft, clique, istanbul
consensus=raft

# Block period for Clique and IBFT
block_period=0

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=n1

# Send some ether for pre-defined accounts
alloc_ether=true

node_name_prefix=master
auto_start_containers=true

########################################################################

[[ "$total_nodes" -lt "$signer_nodes" ]] && total_nodes=$signer_nodes

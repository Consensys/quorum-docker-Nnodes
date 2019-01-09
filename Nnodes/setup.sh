#!/bin/bash

#
# Create all the necessary scripts, keys, configurations etc. to run
# a cluster of N Quorum nodes with Raft consensus.
#
# The nodes will be in Docker containers. List the IP addresses that
# they will run at below (arbitrary addresses are fine).
#
# Run the cluster with "docker-compose up -d"
#
# Run a console on Node N with "geth attach qdata_N/dd/geth.ipc"
# (assumes Geth is installed on the host.)
#
# Geth and Constellation logfiles for Node N will be in qdata_N/logs/
#

# TODO: check file access permissions, especially for keys.

#### Color Control Codes ###############################################

COLOR_RESET='\e[0m'
COLOR_GREEN='\e[1;32m';
COLOR_RED='\e[1;31m';
COLOR_YELLOW='\e[1;33m';
COLOR_BLUE='\e[1;36m';
COLOR_WHITE='\e[1;37m';

#### Configuration options #############################################

# One Docker container will be configured for each IP address in $ips

# Port prefix
rpc_start_port=22000
node_start_port=25000
raft_start_port=28000

# VIP Subnet
subnet="172.13.0.0/16"

# Total nodes to deploy
total_nodes=5

# Signer nodes for Clique and IBFT
signer_nodes=7

# Consensus engine ex. raft, clique, istanbul
consensus=raft

# Block period for Clique and IBFT
block_period=1

# Docker image name
image=quorum

# Service name for docker-compose.yml
service=n1

# Send some ether for pre-defined accounts
alloc_ether=true

########################################################################

ip_prefix="`echo ${subnet} | cut -d / -f 1 | cut -d . -f 1-3`."

ips=()
signer_ips=()

n=0

[[ ! "$1" = "" ]] && consensus=$1

if [ "${consensus}" = "clique" ]; then
    echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_BLUE}Quorum${COLOR_WHITE} with ${COLOR_YELLOW}Clique${COLOR_WHITE} consensus engine${COLOR_RESET}"
elif [ "${consensus}" = "istanbul" ]; then
    echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_BLUE}Quorum${COLOR_WHITE} with ${COLOR_GREEN}Istanbul BFT${COLOR_WHITE} consensus engine${COLOR_RESET}"
elif [ "${consensus}" = "raft" ]; then
    echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_BLUE}Quorum${COLOR_WHITE} with ${COLOR_RED}Raft${COLOR_WHITE} consensus engine${COLOR_RESET}"
else
    echo -e "${COLOR_WHITE}Consensus engine not found: ${COLOR_RED}${consensus}${COLOR_WHITE}${COLOR_RESET}"
fi

if [[ $total_nodes < 2 ]]
then
    echo "ERROR: There must be more than one node."
    exit 1
fi

if [[ ! "${consensus}" = "raft" &&  $signer_nodes < 4 ]]
then
    echo "ERROR: There must be more than four signer nodes in IBFT and Clique consensus ."
    exit 1
fi

[[ $total_nodes < $signer_nodes ]] && total_nodes=$signer_nodes

if [ -e docker-compose.yml ]; then
    echo -e "${COLOR_WHITE}[*] Performing cleanup. ${COLOR_RESET}"
    ./cleanup.sh
fi

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################

# Force cleanup on next setup
touch docker-compose.yml

i=0

#Fill IP list
for i in $(seq 2 $((total_nodes+1))); do
    ips+=("$ip_prefix$i") 
    if [[ ! "${consensus}" = "raft" && "$n" -ge "$((total_nodes-signer_nodes))" ]]; then
        signer_ips+=("$ip_prefix$i")
    fi
done

printf "${COLOR_WHITE}[1] Configuring for ${COLOR_RED}'$total_nodes'${COLOR_WHITE} nodes"
if [ ! "${consensus}" = "raft" ]; then
    printf " with ${COLOR_YELLOW}'${#signer_ips[@]}'${COLOR_WHITE} signer nodes"
fi

echo -e ".${COLOR_RESET}"

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    mkdir -p $qd/{logs,keys}
    mkdir -p $qd/dd/geth

    let n++
done


#### Make static-nodes.json and store keys #############################

nodekeys=""

echo -e "${COLOR_WHITE}[2] Creating Enodes and static-nodes.json.${COLOR_RESET}"

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    sep=`[[ $n < $total_nodes ]] && echo ","`

    # Generate the node's Enode and key
    nkey=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -genkey /qdata/dd/nodekey -writeaddress; cat /qdata/dd/nodekey"`

    # IBFT use nodekey to authorize nodes.
    if [ "$consensus" = "istanbul" ]; then
        nodekeys="${nodekeys}${nkey}${sep}"
    fi

    enode=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -nodekeyhex ${nkey} -writeaddress"`

    # Add the enode to static-nodes.json
    echo '  "enode://'$enode'@'$ip':30303?raftport=50400"'$sep >> static-nodes.json
    echo -e "  - ${COLOR_GREEN}Node #${n}${COLOR_RESET} with nodekey: ${COLOR_YELLOW}${enode:0:8}...${enode:120:8}${COLOR_RESET} configured. (IP: ${COLOR_BLUE}${ip}${COLOR_RESET})"

    let n++
done

echo "]" >> static-nodes.json

#### Create accounts, keys and genesis.json file #######################

echo -e "${COLOR_WHITE}[3] Creating Ether accounts and genesis.json.${COLOR_RESET}"

# extraData parameter for IBFT
istanbul_extra=""

cat > genesis.json <<EOF
{
  "alloc": {
EOF

# Create extraData from nodekeys
if [ "$consensus" = "istanbul" ]; then
    genesis=`docker run $image sh -c "istanbul reinit --nodekey ${nodekeys} --quorum"`
    istanbul_extra=`echo $genesis | grep -Po '"extraData": "0x[0-9a-f]+",' | cut -d \" -f 4`
    validators=($(echo $genesis | grep -Po '"[0-9a-f]{40}":' | cut -c 2-41))
    for addr in ${validators[*]}; do
        cat >> genesis.json <<EOF
    "$addr": {
      "balance": "0x446c3b15f9926687d2c40534fdb564000000000000"
    },
EOF
    done
fi

n=1

signers=""
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate an Ether account for the node
    touch $qd/passwords.txt
    account=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new 2>/dev/null | cut -c 11-50`
    printf "  - Account ${COLOR_YELLOW}0x${account}${COLOR_RESET} created on ${COLOR_GREEN}Node #${n}${COLOR_RESET}."

    sep=`[[ $n < $total_nodes ]] && echo ","`

    if [[ " ${signer_ips[@]} " =~ " $ip " ]]; then
        if [ "${consensus}" = "clique" ]; then
            signers="${account}${signers}"
        fi
	printf " ${COLOR_RED}(Signer)${COLOR_RESET}"
    fi

    printf "\n"    

    # Add the account to the genesis block so it has some Ether at start-up
    if [ "$alloc_ether" = "true" ]; then
        cat >> genesis.json <<EOF
    "${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF
    fi

    let n++
done

cat >> genesis.json <<EOF
  },
  "coinbase": "0x0000000000000000000000000000000000000000",
  "difficulty": "0x1",
  "gasLimit": "0xE0000000",
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x`printf "%x" $(date +%s)`",
EOF

cat >> genesis.json <<EOF
  "config":{
    "chainId": 10,
    "eip150Block": 1,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "eip155Block": 1,
    "eip158Block": 1,
    "byzantiumBlock": 1,
    "isQuorum": true,
EOF

if [ "${consensus}" = "clique" ]; then
    cat >> genesis.json <<EOF
    "clique": {
      "period": ${block_period},
      "epoch": 30000
    }
  },
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000${signers}0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "mixhash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
EOF
elif [ "${consensus}" = "istanbul" ]; then
    cat >> genesis.json <<EOF
    "istanbul": {
      "epoch": 30000,
      "policy": 0
    }
  },
  "gasUsed": "0x0",
  "number": "0x0",
  "extraData": "${istanbul_extra}",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365"
}
EOF
else # Raft
    cat >> genesis.json <<EOF
  },
  "extraData": "0x",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578"
}
EOF
fi

#### Make node list for tm.conf ########################################

nodelist=
n=1
for ip in ${ips[*]}
do
    sep=`[[ $ip != ${ips[0]} ]] && echo ","`
    nodelist=${nodelist}${sep}'"http://'${ip}':9000/"'
    let n++
done


#### Complete each node's configuration ################################

echo -e "${COLOR_WHITE}[4] Creating Quorum keys and finishing configuration.${COLOR_RESET}"

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    cat templates/tm.conf \
        | sed s/_NODEIP_/${ips[$((n-1))]}/g \
        | sed s%_NODELIST_%$nodelist%g \
              > $qd/tm.conf

    cp genesis.json $qd/genesis.json
    cp static-nodes.json $qd/dd/static-nodes.json

    # Generate Quorum-related keys (used by Constellation)
    docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node --generatekeys=/qdata/keys/tm < /dev/null > /dev/null
    echo -e "  - ${COLOR_GREEN}Node #$n${COLOR_RESET} public key: ${COLOR_YELLOW}`cat $qd/keys/tm.pub`${COLOR_RESET}"

    cp templates/start-node.sh $qd/start-node.sh

    #Do fullsync and mining on clique signer
    chmod 755 $qd/start-node.sh
    if [ "${consensus}" = "clique" ]; then

        sed -i 's/--raft/--syncmode full/g' $qd/start-node.sh

	if [[ " ${signer_ips[@]} " =~ " $ip " ]]; then
            sed -i 's/full/full --mine/g' $qd/start-node.sh    
        fi

    elif [ "${consensus}" = "istanbul" ]; then

        #Block period must > 1 in IBFT
        [[ $block_period < 1 ]] && block_period=1

	sed -i "s/--raft/--istanbul.blockperiod ${block_period} --syncmode full/g" $qd/start-node.sh

	if [[ " ${signer_ips[@]} " =~ " $ip " ]]; then
            sed -i 's/full/full --mine --minerthreads 1 /g' $qd/start-node.sh
        fi
    fi

    let n++
done
rm -rf genesis.json static-nodes.json


#### Create the docker-compose file ####################################

cat > docker-compose.yml <<EOF
version: '2'
services:
EOF

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    cat >> docker-compose.yml <<EOF
  ${consensus}_${service}_$n:
    image: $image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_${consensus}_${service}_net:
        ipv4_address: '$ip'
    ports:
      - $((n+rpc_start_port)):8545
      - $((n+node_start_port)):9000
      - $((n+raft_start_port)):50400
    user: '$uid:$gid'
EOF

    let n++
done

cat >> docker-compose.yml <<EOF

networks:
  quorum_${consensus}_${service}_net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: $subnet
EOF

# Start Cluster
echo -e "${COLOR_WHITE}[5] Starting Quorum cluster.${COLOR_RESET}"
docker-compose up -d 2>/dev/null

echo -e "${COLOR_WHITE}[-] Finished.${COLOR_RESET}"


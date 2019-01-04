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

rpc_start_port=22000
node_start_port=25000
raft_start_port=28000

subnet="172.13.0.0/16"

ips=("172.13.0.2" "172.13.0.3" "172.13.0.4" "172.13.0.12" "172.13.0.13" "172.13.0.14" "172.13.0.15")
signer_ips=("172.13.0.12" "172.13.0.13" "172.13.0.14" "172.13.0.15")

clique=false

if [ "$1" = "clique" ]; then
    clique=true
    echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_BLUE}Quorum${COLOR_WHITE} with ${COLOR_YELLOW}Clique${COLOR_WHITE} consensus engine${COLOR_RESET}"
else
    echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_BLUE}Quorum${COLOR_WHITE} with ${COLOR_RED}Raft${COLOR_WHITE} consensus engine${COLOR_RESET}"
fi

# Docker image name
image=quorum

########################################################################


nnodes=${#ips[@]}

if [[ $nnodes < 2 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi

if [ -e docker-compose.yml ]; then
    echo -e "${COLOR_WHITE}[*] Performing cleanup. ${COLOR_RESET}"
    ./cleanup.sh
fi

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################

touch docker-compose.yml

printf "${COLOR_WHITE}[1] Configuring for ${COLOR_RED}'$nnodes'${COLOR_WHITE} nodes"
if [ "${clique}" = "true" ]; then
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

echo -e "${COLOR_WHITE}[2] Creating Enodes and static-nodes.json.${COLOR_RESET}"

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate the node's Enode and key
    enode=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -genkey /qdata/dd/nodekey -writeaddress; cat /qdata/dd/nodekey"`
    enode=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -nodekeyhex $enode -writeaddress"`

    # Add the enode to static-nodes.json
    sep=`[[ $n < $nnodes ]] && echo ","`
    echo '  "enode://'$enode'@'$ip':30303?raftport=50400"'$sep >> static-nodes.json
    echo -e "  - ${COLOR_GREEN}Node #${n}${COLOR_RESET} with nodekey: ${COLOR_YELLOW}${enode:0:8}...${enode:120:8}${COLOR_RESET} configured."

    let n++
done
echo "]" >> static-nodes.json


#### Create accounts, keys and genesis.json file #######################

echo -e "${COLOR_WHITE}[3] Creating Ether accounts and genesis.json.${COLOR_RESET}"

cat > genesis.json <<EOF
{
  "alloc": {
EOF

n=1

signers=""

for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate an Ether account for the node
    touch $qd/passwords.txt
    account=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new 2>/dev/null | cut -c 11-50`
    printf "  - Account ${COLOR_YELLOW}0x${account}${COLOR_RESET} created on ${COLOR_GREEN}Node #${n}${COLOR_RESET}."
    
    if [ "${clique}" = "true" ] && [[ " ${signer_ips[@]} " =~ " $ip " ]]; then
        signers="${account}${signers}"
	printf " ${COLOR_RED}(Signer)${COLOR_RESET}"
    fi
    printf "\n"
    
    # Add the account to the genesis block so it has some Ether at start-up
    sep=`[[ $n < $nnodes ]] && echo ","`
    cat >> genesis.json <<EOF
    "${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF

    let n++
done

cat >> genesis.json <<EOF
  },
  "coinbase": "0x0000000000000000000000000000000000000000",
EOF
cat >> genesis.json <<EOF
  "config": {
      "chainId": 1337,
      "eip150Block": 1,
      "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "eip155Block": 0,
      "eip158Block": 1,
      "byzantiumBlock": 1,
      "constantinopleBlock": 1,
EOF
if [ "${clique}" = "true" ]; then
    cat >> genesis.json <<EOF
      "clique": {
        "period": 0,
        "epoch": 30000
      },
EOF
fi
cat >> genesis.json <<EOF
      "isQuorum": true
  },
  "difficulty": "0x0",
  "gasLimit": "0x2FEFD800",
EOF
if [ "${clique}" = "true" ]; then
    cat >> genesis.json <<EOF
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000${signers}0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "mixhash": "0x0000000000000000000000000000000000000000000000000000000000000000",
EOF
else
cat >> genesis.json <<EOF
  "extraData": "0x",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
EOF
fi
cat >> genesis.json <<EOF
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00"
}
EOF


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
    chmod 755 $qd/start-node.sh
    if [ "${clique}" = "true" ]; then
        sed -i 's/--raft/--syncmode full/g' $qd/start-node.sh
        if [[ " ${signer_ips[@]} " =~ " $ip " ]]; then
            sed -i 's/full/full --mine/g' $qd/start-node.sh    
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
  cnode_$n:
    image: $image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_clique_net:
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
  quorum_clique_net:
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


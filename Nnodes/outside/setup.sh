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

source config.sh

########################################################################

base_dir=${node_name_prefix}_${service}

ip_prefix="`echo ${subnet} | cut -d / -f 1 | cut -d . -f 1-3`."

ips=()
signer_ips=()

n=0

echo -e "${COLOR_WHITE}[*] Deploy ${COLOR_YELLOW}Outside${COLOR_WHITE} ${COLOR_BLUE}Quorum${COLOR_WHITE} Nodes ${COLOR_RESET}"

if [[ "$outside_nodes" -lt "1" ]]
then
    echo "ERROR: There must be least one node."
    exit 1
fi

if [ -e $base_dir ]; then
    echo -e "${COLOR_WHITE}[*] Performing cleanup. ${COLOR_RESET}"
    ./cleanup.sh
fi

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################

i=0
n=0

# Fill IP list
for i in $(seq 2 $((outside_nodes+1))); do
    ips+=("$ip_prefix$i") 
done

printf "${COLOR_WHITE}[1] Configuring for ${COLOR_RED}'$outside_nodes'${COLOR_WHITE} nodes"

echo -e ".${COLOR_RESET}"

n=1
for ip in ${ips[*]}
do
    qd=$base_dir/qdata_$n
    mkdir -p $qd/{logs,keys}
    mkdir -p $qd/dd/geth

    let n++
done


#### Make static-nodes.json and store keys #############################

nodekeys=""

echo -e "${COLOR_WHITE}[2] Creating Enodes.${COLOR_RESET}"

bootnode="'"

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=$base_dir/qdata_$n
    sep=","

    # Generate the node's Enode and key
    nkey=`docker run --rm -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -genkey /qdata/dd/nodekey -writeaddress; cat /qdata/dd/nodekey"`

    enode=`docker run --rm -u $uid:$gid -v $pwd/$qd:/qdata $image sh -c "/usr/local/bin/bootnode -nodekeyhex ${nkey} -writeaddress"`

    # Add the enode to static-nodes.json
    echo '  "enode://'$enode'@'$ip':30303?raftport=50400",' >> static-nodes.json

    bootnode="${bootnode}enode:\\/\\/${enode}@${ip}:30303$sep"

    echo -e "  - ${COLOR_GREEN}Node #${n}${COLOR_RESET} with nodekey: ${COLOR_YELLOW}${enode:0:8}...${enode:120:8}${COLOR_RESET} configured. (IP: ${COLOR_BLUE}${ip}${COLOR_RESET})"

    let n++
done

n=1
for enode in ${master_enodes[*]}; do

    sep=`[[ $n < $total_nodes ]] && echo ","`
    echo '  "enode://'${master_enodes[$((n-1))]}'@'${master_ip}':'$((n+master_node_start_port))'"'$sep >> static-nodes.json
    bootnode="${bootnode}enode:\\/\\/${master_enodes[$((n-1))]}@${master_ip}:$((n+master_node_start_port))$sep"
    let n++
done

bootnode="${bootnode}'"

echo "]" >> static-nodes.json

#### Create accounts, keys #############################################

echo -e "${COLOR_WHITE}[3] Creating Ether accounts.${COLOR_RESET}"

n=1

for ip in ${ips[*]}
do
    qd=$base_dir/qdata_$n

    # Generate an Ether account for the node
    touch $qd/passwords.txt
    account=`docker run --rm -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new 2>/dev/null | cut -c 11-50`
    printf "  - Account ${COLOR_YELLOW}0x${account}${COLOR_RESET} created on ${COLOR_GREEN}Node #${n}${COLOR_RESET}."

    sep=`[[ $n < $outside_nodes ]] && echo ","`

    printf "\n"

    let n++
done

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
    qd=$base_dir/qdata_$n

    cat ../templates/tm.conf \
        | sed s/_NODEIP_/${ips[$((n-1))]}/g \
        | sed s%_NODELIST_%$nodelist%g \
              > $qd/tm.conf

    cp ../genesis.json $qd/genesis.json
    cp static-nodes.json $qd/dd/static-nodes.json

    # Generate Quorum-related keys (used by Constellation)
    docker run --rm -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node --generatekeys=/qdata/keys/tm < /dev/null > /dev/null
    echo -e "  - ${COLOR_GREEN}Node #$n${COLOR_RESET} public key: ${COLOR_YELLOW}`cat $qd/keys/tm.pub`${COLOR_RESET}"

    cp ../templates/start-node.sh $qd/start-node.sh

    #Do fullsync and mining on clique signer
    chmod 755 $qd/start-node.sh
    if [ "${consensus}" = "clique" ]; then
        sed -i 's/--raft/--syncmode full/g' $qd/start-node.sh
    fi
    
    sed -i "s/{bootnode}/--bootnodes ${bootnode}/g" $qd/start-node.sh

    sed -i "s/{node_name}/Geth-${node_name_prefix}-$n/g" $qd/start-node.sh
 
    let n++
done
rm -rf genesis.json static-nodes.json


#### Create the docker-compose file ####################################

cat > $base_dir/docker-compose.yml <<EOF
version: '2'
services:
EOF

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    cat >> $base_dir/docker-compose.yml <<EOF
  ${consensus}_${service}_$n:
    image: $image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_${consensus}_${service}_net:
        ipv4_address: '$ip'
    ports:
      - $((n+rpc_start_port)):8545
      - $((n+node_start_port)):30303
      - $((n+raft_start_port)):50400
    user: '$uid:$gid'
EOF

    let n++
done

cat >> $base_dir/docker-compose.yml <<EOF

networks:
  quorum_${consensus}_${service}_net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: $subnet
EOF

cp ../cmd.sh $base_dir/cmd.sh
cp ../cleanup.sh $base_dir/

echo "service=$service" >> $base_dir/.current_config
echo "consensus=$consensus" >> $base_dir/.current_config
echo "total_nodes=$outside_nodes" >> $base_dir/.current_config


echo -e "${COLOR_WHITE}[-] Finished.${COLOR_RESET}"
echo -e "${COLOR_WHITE}[-] Please upload $base_dir directory to destination. ${COLOR_RESET}"
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
# Dependency: Geth, Bootnode and Constellation currently need to be installed
# on the host. TODO - fix this.
#
# Geth and Constellation logfiles for Node N will be in qdata_N/logs/
#

# TODO: check file access permissions


#### Configuration options #############################################

# These (currently) need to be in the subnet 172.13.0.0/16 since it is
# hardcoded into the docker-compose file. Change it below if you like.
ips=("172.13.0.2" "172.13.0.3" "172.13.0.4")


########################################################################

if [[ ${#ips[@]} < 2 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi
   
./cleanup.sh


#### Create directories for each node's configuration ##################

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    mkdir -p $qd/logs
    mkdir -p $qd/dd/{keystore,geth}
    mkdir $qd/keys
    let n++
done


#### Make static-nodes.json and store keys #############################

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    # TODO generate this enode and key using the Docker container
    enode=`/usr/local/bin/bootnode -genkey $qd/dd/nodekey -writeaddress`
    sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
    echo '  "enode://'$enode'@'$ip':30303?discport=0"'$sep >> static-nodes.json
    let n++
done
echo "]" >> static-nodes.json


#### Create accounts, keys and genesis.json file #######################

cat > genesis.json <<EOF
{
  "alloc": {
EOF

touch password.txt
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    # Generate account and save key
    # TODO generate the account using the Docker container
    account=`/usr/local/bin/geth --datadir=. --password ./password.txt account new | cut -c 11-50`
    # Ether account key for accounts in the Genesis block
    mv keystore/UTC*${account} $qd/dd/keystore

    # Add to genesis block
    sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
    cat >> genesis.json <<EOF
    "${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF

    let n++
done
rm -rf keystore
rm -f password.txt

cat >> genesis.json <<EOF
  },
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config": {
    "homesteadBlock": 0
  },
  "difficulty": "0x0",
  "extraData": "0x",
  "gasLimit": "0x2FEFD800",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
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

    # Quorum-related keys (used by Constellation)
    # TODO - generate these using the docker container
    /usr/local/bin/constellation-enclave-keygen $qd/keys/tm $qd/keys/tma < /dev/null > /dev/null
    echo 'Node '$n' public key: '`cat $qd/keys/tm.pub`

    # Embed the user's host machine permissions in the start script
    # So that the nodes run under the right UID/GID
    cat templates/start-node.sh \
        | sed s/_UID_/`id -u`/g \
        | sed s/_GID_/`id -g`/g \
        > $qd/start-node.sh
    chmod 755 $qd/start-node.sh

    touch $qd/passwords.txt

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
  node_$n:
    image: quorum
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_net:
        ipv4_address: '$ip'
    ports:
      - $((n+22000)):8545
EOF

    let n++
done

cat >> docker-compose.yml <<EOF

networks:
  quorum_net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: 172.13.0.0/16
EOF


#### Create pre-populated contracts ####################################

# Private contract - insert Node 2 as the recipient
cat templates/contract_pri.js \
    | sed s:_NODEKEY_:`cat qdata_2/keys/tm.pub`:g \
          > contract_pri.js

# Public contract - no change required
cp templates/contract_pub.js ./

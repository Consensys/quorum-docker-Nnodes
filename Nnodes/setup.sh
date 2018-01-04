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


#### Configuration options #############################################

# One Docker container will be configured for each IP address in $ips
subnet="172.13.0.0/16"
ips=("172.13.0.2" "172.13.0.3" "172.13.0.4")

# Docker image name
image=quorum

########################################################################

nnodes=${#ips[@]}

if [[ $nnodes < 2 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi

./cleanup.sh

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################

echo '[1] Configuring for '$nnodes' nodes.'

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    mkdir -p $qd/{logs,keys}
    mkdir -p $qd/dd/geth

    let n++
done


#### Make static-nodes.json and store keys #############################

echo '[2] Creating Enodes and static-nodes.json.'

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate the node's Enode and key
    docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/bootnode -genkey /qdata/dd/nodekey
    enode=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/bootnode --nodekey /qdata/dd/nodekey -writeaddress`
    # Add the enode to static-nodes.json
    sep=`[[ $n < $nnodes ]] && echo ","`
    echo '  "enode://'$enode'@'$ip':30303?discport=0&raftport=50400"'$sep >> static-nodes.json

    let n++
done
echo "]" >> static-nodes.json


#### Create accounts, keys and genesis.json file #######################

echo '[3] Creating Ether accounts and genesis.json.'

cat > genesis.json <<EOF
{
  "alloc": {
EOF

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate an Ether account for the node
    touch $qd/passwords.txt
    account=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new | cut -c 11-50`

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

echo '[4] Creating Quorum keys and finishing configuration.'

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
    docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node --generatekeys=qdata/keys/tm < /dev/null > /dev/null
    echo 'Node '$n' public key: '`cat $qd/keys/tm.pub`

    cp templates/start-node.sh $qd/start-node.sh
    chmod 755 $qd/start-node.sh

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
    image: $image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_net:
        ipv4_address: '$ip'
    ports:
      - $((n+22000)):8545
    user: '$uid:$gid'
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
      - subnet: $subnet
EOF

#### Create pre-populated contracts ####################################
echo '[5] Compiling example contracts'
# Private contract - insert Node 2 as the recipient
cp templates/contract_pri.sol ./
docker run -u $uid:$gid --rm -v $pwd/:/data/ $image solc -o /data/contract_pri --bin --abi /data/contract_pri.sol < /dev/null > /dev/null
abi=$(<$pwd/contract_pri/simplestorage.abi)
binary=$(<$pwd/contract_pri/simplestorage.bin)
nodekey=$(<qdata_2/keys/tm.pub)
rm -rf contract_pri/ contract_pri.sol
cat > contract_pri.js <<EOF
//
// Create a contract private with the nodes with addresses in toKey
//

var toKeys=["$nodekey"];

a = eth.accounts[0]
web3.eth.defaultAccount = a;


var SimpleContract = eth.contract($abi);

var contract = SimpleContract.new(42, {
        from: web3.eth.accounts[0],
        data:'0x$binary',
        gas: 1000000
    },
function(e, contract) {
	if (e) {
		console.log("err creating contract", e);
	} else {
		if (!contract.address) {
			console.log("Contract transaction send: TransactionHash: " + contract.transactionHash + " waiting to be mined...");
		} else {
			console.log("Contract mined! Address: " + contract.address);
			console.log(contract);
		}
	}
});
EOF


# Public contract - no change required
cp templates/contract_pub.sol ./
docker run -u $uid:$gid --rm -v $pwd/:/data/ $image solc -o /data/contract_pub --bin --abi /data/contract_pub.sol < /dev/null > /dev/null
abi=$(<$pwd/contract_pub/simplestorage.abi)
binary=$(<$pwd/contract_pub/simplestorage.bin)
rm -rf contract_pub/ contract_pub.sol
cat > contract_pub.js <<EOF
//
// Create a public contract
//
a = eth.accounts[0]
web3.eth.defaultAccount = a;

var SimpleContract = eth.contract($abi);

var contract = SimpleContract.new(42, {
        from: web3.eth.accounts[0],
        data:'0x$binary',
        gas: 1000000
    },
function(e, contract) {
	if (e) {
		console.log("err creating contract", e);
	} else {
		if (!contract.address) {
			console.log("Contract transaction send: TransactionHash: " + contract.transactionHash + " waiting to be mined...");
		} else {
			console.log("Contract mined! Address: " + contract.address);
			console.log(contract);
		}
	}
});
EOF




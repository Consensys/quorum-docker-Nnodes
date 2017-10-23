#!/bin/bash

#
# This is used at Container start up to run the constellation and geth nodes
#

set -u
set -e

### Permissions (for sanely sharing the mapped volume with the host user)
# For convenience, create a user whose uid/gid matches the user on the host
# This is hacky - is there a better way?
groupadd -g _GID_ quorum
useradd -u _UID_ -g _GID_ quorum
chown quorum:quorum /qdata

### Configuration Options
TMCONF=/qdata/tm.conf

#GETH_ARGS="--datadir /qdata/dd --raft --rpc --rpcaddr 0.0.0.0 --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum --unlock 0 --password /qdata/passwords.txt"
GETH_ARGS="--datadir /qdata/dd --raft --rpc --rpcaddr 0.0.0.0 --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum --nodiscover --unlock 0 --password /qdata/passwords.txt"

### Run script
cat > /run.sh << EOT
#!/bin/bash
set -u
set -e

cd /tmp

if [ ! -d /qdata/dd/geth/chaindata ]; then
  echo "[*] Mining Genesis block"
  /usr/local/bin/geth --datadir /qdata/dd init /qdata/genesis.json
fi

echo "[*] Starting Constellation node"
nohup /usr/local/bin/constellation-node $TMCONF 2>> /qdata/logs/constellation.log &

sleep 2

echo "[*] Starting node"
PRIVATE_CONFIG=$TMCONF nohup /usr/local/bin/geth $GETH_ARGS 2>>/qdata/logs/geth.log
EOT

### Run it
chmod 755 /run.sh
sudo -u quorum /run.sh

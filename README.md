# quorum-docker-Nnodes

## Modified by me
  * Add support for Quorum 2.2.4.
  * Add support for Clique consensus engine.
  * Add support for Istanbul BFT consensus engine.

## Intro

Run a bunch of Quorum nodes, each in a separate Docker container.

This is simply a learning exercise for configuring Quorum networks. Probably best not used in a production environment.

In progress:

  * Add multi-nodes deployment.
  * Further work on Docker image size.
  * Tidy the whole thing up.

See the *README* in the *Nnodes* directory for details of the set up process.

## Building

In the top level directory:

    docker build -t quorum .
    
The first time will take a while, but after some caching it gets much quicker for any minor updates.

I've got the size of the final image down to ~~391MB~~ 308MB from over 890MB. It's likely possible to improve much further on that.  Alpine Linux is a candidate minimal base image, but there are challenges with the Haskell dependencies; there's an [example here](https://github.com/jpmorganchase/constellation/blob/master/build-linux-static.dockerfile).

## Running

Change to the *Nnodes/* directory. Edit the `ips` variable in *config.sh* to list two or more IP addresses on the Docker network that will host nodes:

    # change to Nnodes
    cd Nnodes
    
    vi config.sh
    
    # Total nodes to deploy
    total_nodes=5

    # Signer nodes for Clique and IBFT
    signer_nodes=7
    
    # Use docker host network for RLP connection.
    use_host_net=false
    
    # auto start
    auto_start_containers=true
    
The IP addresses are needed for Constellation to work. Now run,

    ./setup.sh [raft]
    ./setup.sh clique    # For Clique
    ./setup.sh istanbul  # For IBFT
    
This will set up as many Quorum nodes as IP addresses you supplied, each in a separate container, on a Docker network, all hopefully talking to each other.

    Nnodes> docker ps
    CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                     NAMES
    83ad1de7eea6        quorum              "/qdata/start-node.sh"   55 seconds ago      Up 53 seconds       0.0.0.0:22002->8545/tcp   nnodes_node_2_1
    14b903ca465c        quorum              "/qdata/start-node.sh"   55 seconds ago      Up 54 seconds       0.0.0.0:22003->8545/tcp   nnodes_node_3_1
    d60bcf0b8a4f        quorum              "/qdata/start-node.sh"   55 seconds ago      Up 54 seconds       0.0.0.0:22001->8545/tcp   nnodes_node_1_1

## Stopping

    docker-compose down
  
## Playing

### Accessing the Geth console

To enter Geth console, use:

    ./cmd.sh console 1

Or you have Geth installed on the host machine you can do the following from the *Nnodes* directory to attach to Node 1's console.

    geth attach qdata_1/dd/geth.ipc

### View Geth logs

To show Geth log:

    ./cmd.sh log 1

To show all Geth node logs:

    ./cmd.sh logs

### Making transactions

We will demo the following, from Node 1's console.

1. Create a public contract (visible to all nodes)

2. Create a private contract with Node 2

3. Send a private transaction to update the contract state with node 2.

This is based on using the provided example *setup.sh* file as-is (three nodes).

#### Node 1 geth console

    > var abi = [{"constant":true,"inputs":[],"name":"storedData","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"x","type":"uint256"}],"name":"set","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"get","outputs":[{"name":"retVal","type":"uint256"}],"payable":false,"type":"function"},{"inputs":[{"name":"initVal","type":"uint256"}],"type":"constructor"}];
    undefined

    > loadScript("contract_pub.js")
    Contract transaction send: TransactionHash: 0x0e7ff9b609c0ba3a11de9cd4f51389c29dceacbac2f91e294346df86792d8d8f waiting to be mined...
    true
    Contract mined! Address: 0x1932c48b2bf8102ba33b4a6b545c32236e342f34
    [object Object]

    > var public = eth.contract(abi).at("0x1932c48b2bf8102ba33b4a6b545c32236e342f34")
    undefined
    > public.get()
    42

    > loadScript("contract_pri.js")
    Contract transaction send: TransactionHash: 0xa9b969f90c1144a49b4ab4abb5e2bfebae02ab122cdc22ca9bc564a740e40bcd waiting to be mined...
    true
    Contract mined! Address: 0x1349f3e1b8d71effb47b840594ff27da7e603d17
    [object Object]

    > var private = eth.contract(abi).at("0x1349f3e1b8d71effb47b840594ff27da7e603d17")
    undefined
    > private.get()
    42
    > private.set(65535, {privateFor: ["QfeDAys9MPDs2XHExtc84jKGHxZg/aj52DTh0vtA3Xc="]})
    "0x0dc9c0b85b4c4e5f1e3ba2014b5f628f5153bc2588741a69626eb5a40d2b30d6"
    > private.get()
    65535

#### Node 2 geth console

    > var abi = [{"constant":true,"inputs":[],"name":"storedData","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"x","type":"uint256"}],"name":"set","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"get","outputs":[{"name":"retVal","type":"uint256"}],"payable":false,"type":"function"},{"inputs":[{"name":"initVal","type":"uint256"}],"type":"constructor"}];
    undefined
    > var public = eth.contract(abi).at("0x1932c48b2bf8102ba33b4a6b545c32236e342f34")
    undefined
    > var private = eth.contract(abi).at("0x1349f3e1b8d71effb47b840594ff27da7e603d17")
    undefined
    > public.get()
    42
    > private.get()
    65535

#### Node 3 geth console

    > var abi = [{"constant":true,"inputs":[],"name":"storedData","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"x","type":"uint256"}],"name":"set","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"get","outputs":[{"name":"retVal","type":"uint256"}],"payable":false,"type":"function"},{"inputs":[{"name":"initVal","type":"uint256"}],"type":"constructor"}];
    undefined
    > var public = eth.contract(abi).at("0x1932c48b2bf8102ba33b4a6b545c32236e342f34")
    undefined
    > var private = eth.contract(abi).at("0x1349f3e1b8d71effb47b840594ff27da7e603d17")
    undefined
    > public.get()
    42
    > private.get()
    0

So, Node 2 is able to see both contracts and the private transaction. Node 3 can see only the public contract and its state.

## Notes

The RPC port for each container is mapped to *localhost* starting from port 22001. So, to see the peers connected to Node 2, you can do either of the following and get the same result. Change it in *setup.sh* if you don't like it.

    curl -X POST --data '{"jsonrpc":"2.0","method":"admin_peers","id":1}' 172.13.0.3:8545
    curl -X POST --data '{"jsonrpc":"2.0","method":"admin_peers","id":1}' localhost:22002

You can see the log files for the nodes in *qdata_N/logs/geth.log* and *qdata_N/logs/constellation.log*.  This is useful when things go wrong!

This example uses only the Raft consensus mechanism.


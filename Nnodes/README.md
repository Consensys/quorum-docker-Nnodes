# Exposition of *setup.sh*

The *setup.sh* script creates a basic Quorum network with Raft consensus. There's a whole bunch of things it needs to do in order to achieve this, some specific to Quorum, some common to private Ethereum chains in general.

This is what we set up for each node.

 * Enode and *nodekey* file to uniquely identify each node on the network.
   * *static-nodes.json* file that lists the Enodes of nodes that can participate in the Raft consensus.
 * Ether account and *keystore* directory for each node.
   * The account gets written into the *genesis.json* file that each node runs once to bootstrap the blockchain.
 * The *tm.conf* file that tells Quorum where all the node's keys are and where all the other nodes are.
 * Public/private Keypairs for Quorum private transactions.
 * A script for starting the Geth and Constellation processes in each container, *start-node.sh*.
 * A folder, *logs/*, for Geth and Constellation to write their log files to.

In addition we create some utility scripts on the host.

  * A *docker-compose.yml* file that can be used with docker-compose to create the network of containers.
  * Two sample contract creation scripts:
    * *contract_pub.js* - creates a public contract, visible to all.
    * *contract_pri.js* - creates a private contract between the sender and Node 2.


Refer to the *setup.sh* file itself for the full code.

## Configuration options

Options are simple and self-explanatory. The *docker-compose.yml* file will create a Docker network for the nodes as per the `subnet` variable here. If you want to run more nodes, then add addresses for them to the `ips` list.

    #### Configuration options #############################################

    # One Docker container will be configured for each IP address in $ips
    subnet="172.13.0.0/16"
    ips=("172.13.0.2" "172.13.0.3" "172.13.0.4")

    # Docker image name
    image=quorum

The docker image is used during set-up to run Geth, Bootnode and Constellation to generate various things. These executables don't need to be installed on the host machine.

## House-keeping

The sample private transaction we will create later is designed to be sent from Node 1 to Node 2, so we demand that there be at least two nodes configured.

    if [[ ${#ips[@]} < 2 ]]
    then
        echo "ERROR: There must be more than one node IP address."
    exit 1
    fi

Delete any old configuration.

    ./cleanup.sh

We will need to run processes within the Docker containers with the same account parameters as the user on the Docker host. This is to avoid problems with the mapped disk volumes that are shared between the host and the containers. So we collect the info here for later use.

    uid=`id -u`
    gid=`id -g`
    pwd=`pwd`

## Directory structure

The final goal at the end of set-up is for each node to have its own directory tree that looks like this:

    /qdata/
    ├── dd/
    │   ├── geth/
    │   ├── keystore/
    │   │   └── UTC--2017-10-21T12-49-26.422099203Z--aad5479aff498c9258b21b59dd7546262aa2cfc7
    │   ├── nodekey
    │   └── static-nodes.json
    ├── keys/
    │   ├── tm.key
    │   └── tm.pub
    ├── logs/
    ├── genesis.json
    ├── passwords.txt
    ├── start-node.sh
    └── tm.conf

On the Docker host, we create a *qdata_N/* directory for each node, with this structure. When we start up the network, this will be mapped by the *docker-compose.yml* file to each container's internal */qdata/* directory.

    #### Create directories for each node's configuration ##################

    n=1
    for ip in ${ips[*]}
    do
        qd=qdata_$n
        mkdir -p $qd/{logs,keys}
        mkdir -p $qd/dd/geth

        let n++
    done

## Create Enode information and *static-nodes.json*

Each node is assigned an Enode, which is the public key corresponding to a private *nodekey*. This Enode is what identifies the node on the Ethereum network. Membership of our private network is defined by the Enodes listed in the *static-nodes.json* file. These are the nodes that can participate in the Raft consensus.

We use Geth's *bootnode* utility to generate the Enode and the private key. By jumping through some hoops to get the file permissions right we can use the version of *bootnode* already present in the Docker image.

    #### Make static-nodes.json and store keys #############################

    echo "[" > static-nodes.json
    n=1
    for ip in ${ips[*]}
    do
        qd=qdata_$n

        # Generate the node's Enode and key
        enode=`docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/bootnode -genkey /qdata/dd/nodekey -writeaddress`

        # Add the enode to static-nodes.json
        sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
        echo '  "enode://'$enode'@'$ip':30303?discport=0"'$sep >> static-nodes.json

        let n++
    done
    echo "]" >> static-nodes.json

## Create Ethereum accounts and *genesis.json* file

To allow nodes to send transactions they will need some Ether. This is required in Quorum, even though gas is zero cost. For simplicity we create an account and private key for each node, and we create the genesis block such that each of the accounts is pre-cherged with a billion Ether (10^27 Wei).

The Geth executable in the Docker image is used to create the accounts. An empty *passwords.txt* file is created which is used when unlocking the (passwordless) Ether account for each node when starting Geth in *start-node.sh*.

    #### Create accounts, keys and genesis.json file #######################

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
        sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
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

The account created for each node will be available as `eth.accounts[0]` in the node's console.

## List node IP addresses for the Quorum transaction manager, *tm.conf*

The Quorum transaction manager currently needs to know the IP addresses of peers it may need to send private transactions to. We list them out here. Each node will have the same list - it ignores its own IP address. The transaction manager process is hosted on port 9000.

    #### Make node list for tm.conf ########################################

    nodelist=
    n=1
    for ip in ${ips[*]}
    do
        sep=`[[ $ip != ${ips[0]} ]] && echo ","`
        nodelist=${nodelist}${sep}'"http://'${ip}':9000/"'
        let n++
    done

## Further configuration

    #### Complete each node's configuration ################################

    n=1
    for ip in ${ips[*]}
    do
        qd=qdata_$n

*tm.conf* is the transaction manager configuration file for each node. We use a pre-populated template for this, inserting the IP address of the node and the list of peer nodes created above.

        cat templates/tm.conf \
            | sed s/_NODEIP_/${ips[$((n-1))]}/g \
            | sed s%_NODELIST_%$nodelist%g \
                  > $qd/tm.conf

We copy into each node's directory the *genesis.json* and *static-nodes.json* files that were created earlier.

        cp genesis.json $qd/genesis.json
        cp static-nodes.json $qd/dd/static-nodes.json

Quorum's Constellation needs public/private keypairs to operate. The *tm.pub* key is the address to which "privateFor" transactions should be sent for a node. Quorum provides a utility for generating these keys, and again we use the instance in the Docker image.

        # Generate Quorum-related keys (used by Constellation)
        docker run -u $uid:$gid -v $pwd/$qd:/qdata $image /usr/local/bin/constellation-node --generatekeys=/qdata/keys/tm < /dev/null > /dev/null
        echo 'Node '$n' public key: '`cat $qd/keys/tm.pub`

        cp templates/start-node.sh $qd/start-node.sh
        chmod 755 $qd/start-node.sh

        let n++
    done
    rm -rf genesis.json static-nodes.json

## Create *docker-compose.yml*

#### Create the docker-compose file ####################################

This is the first file that is not written to the node-specific directories. This will be used by *docker-compose* to start and stop the containers and network. Each node/container has an entry.

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

## Create pre-populated contracts

For convenience, we provide a couple of scripts that create contracts, one public, one private. The private contract needs to know Node 2's key since that is the node we will share the contract with, so we copy in the key we generated earlier. Templates for the contracts are in the *templates/* directory.

    #### Create pre-populated contracts ####################################

    # Private contract - insert Node 2 as the recipient
    cat templates/contract_pri.js \
        | sed s:_NODEKEY_:`cat qdata_2/keys/tm.pub`:g \
              > contract_pri.js

    # Public contract - no change required
    cp templates/contract_pub.js ./

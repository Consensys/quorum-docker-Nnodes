# Quorum Multi-Cluster Setup
  * Raft support
  * Clique support (*experimental)

## Getting Started

1. Change master cluster network to `HOST` and set the `master nodes IP`
```bash=
vi config.sh

# Use docker host network for RLP connection.
use_host_net=true

# Interface IP for RLP listening when using docker host network
interface_ip="172.16.2.169"

# create master nodes.
./setup.sh
```

2. Create a cluster
```bash=
cd outside

./setup.sh
Usage: ./setup.sh [ext_node_ip] [node_name] [service_name]

./setup.sh 192.168.26.112 test e1
[R] Raft Leader is 2ffa9baf...28fa34c7.
[R] RPC at http://172.16.2.169:23002/
[*] Generate Outside Quorum Nodes for test_e1.
[1] Configuring for '4' nodes.
[2] Creating Enodes.
  - Node #1 with nodekey: 6d81f39a...71b22271 configured with Raft ID 5.
  - Node #2 with nodekey: 79249409...9d76813d configured with Raft ID 6.
  - Node #3 with nodekey: c82cc372...d66d8213 configured with Raft ID 7.
  - Node #4 with nodekey: 035663a1...d95a7286 configured with Raft ID 8.
[3] Creating Ether accounts.
  - Account 0xcd17213144bc4615bf6c5bfd043a601dc2c5365f created on Node #1.
  - Account 0x0fb3df4332728c97f3ca7c04db6e6dab08f9c3ea created on Node #2.
  - Account 0xdfdd444f36fdf14ffa6290ad0295425e0ed04676 created on Node #3.
  - Account 0x94301d0ef2ca1af5c5b55bca0be69f41beb7da90 created on Node #4.
[4] Creating Quorum keys and finishing configuration.
[-] Finished.
[-] Please upload test_e1 directory to destination.
```

3. Upload a new cluster to other node
```bash=
scp -r test_e1 192.168.26.112:~/

ssh 192.168.26.112

# go to cluster dir
cd test_e2

# build Quorum image
docker build -t quorum image/

# start
docker-compose up -d
```

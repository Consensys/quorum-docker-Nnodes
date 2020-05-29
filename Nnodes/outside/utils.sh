#!/bin/bash

source ../.current_config

req_net_listening="{\"jsonrpc\": \"2.0\", \"id\": 10,\"method\":\"net_listening\",\"params\":[]}"
req_raft_add_peer="{\"jsonrpc\": \"2.0\", \"id\": 10,\"method\":\"raft_addPeer\",\"params\":[\""
req_raft_leader="{\"jsonrpc\": \"2.0\", \"id\": 10,\"method\":\"raft_leader\",\"params\":[]}"
req_raft_cluster="{\"jsonrpc\": \"2.0\", \"id\": 10,\"method\":\"raft_cluster\",\"params\":[]}"

master_nodes=()
# Fill IP list
for i in $(seq 1 $((total_nodes))); do
    master_nodes+=("http://$interface_ip:$((i+rpc_start_port))/")
done

leader=0

get() {
    result=`curl -X POST -H "Content-Type: application/json" -d "$1" $2 2>/dev/null | jq -r ".result" 2>/dev/null`
    
    if [ "$?" != "0" ]; then
        return 1
    fi
    echo $result
    return 0
}

test_master_nodes(){
    for node in ${master_nodes[*]}; do
        result=`get "${req_net_listening}" $node`
        [ "$result" != "true" ] && return 1
    done
    return 0 
}

raft_get_leader_enode(){
    echo `get "${req_raft_leader}" ${master_nodes[0]}`
    return $?
}

raft_get_leader_rpc(){
    cluster=`get "${req_raft_cluster}" ${master_nodes[0]}`
    leader_enode=`raft_get_leader_enode`
    leader_p2p_port=`echo $cluster | jq ".[] | select(.nodeId==\"$leader_enode\") | .p2pPort"`
    echo 'http://'$interface_ip':'$((rpc_start_port+leader_p2p_port-node_start_port))'/'
}

raft_add_peer(){
    req=$req_raft_add_peer
    req+=$1
    req+="\"]}"
    echo `get "${req}" $2`
}

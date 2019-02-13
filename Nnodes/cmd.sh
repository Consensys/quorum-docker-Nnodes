#!/bin/bash

source ./.current_config

command=$1
node=$2

if [[ "$command" = "console" ]]; then 
    container_id=`docker ps --format "{{.ID}}:{{.Names}}" | grep ${consensus}_${service}_$node | cut -d : -f 1`
    if [[ "$container_id" = "" ]]; then
        echo "No such container."
        exit 1
    fi
    docker exec -it $container_id bash -c "export SHELL=/bin/bash && geth attach /qdata/dd/geth.ipc"
    exit 0

elif [[ "$command" = "log" ]]; then

    if [[ "$node" = "" ]]; then
        echo "No such container."
        exit 1
    fi

    cat qdata_$node/logs/geth.log

elif [[ "$command" = "logs" ]]; then
    
    lines=$((`tput lines`/$total_nodes-2))

    tail_cmd="tail -F -n $lines "
    for i in $(seq 1 $total_nodes); do
        tail_cmd="$tail_cmd qdata_$i/logs/geth.log "
    done
    eval $tail_cmd

fi

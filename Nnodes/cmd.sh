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

    tail -F qdata_$node/logs/geth.log

elif [[ "$command" = "logs" ]]; then
    
    lines=$((`tput lines`/$total_nodes))
    tmux_cmd="tmux new-session \; "
    for i in $(seq 2 $total_nodes); do
        tmux_cmd="$tmux_cmd split-window -v -l $lines \; select-pane -t 0 \; "
    done
    for i in $(seq 1 $total_nodes); do

        tmux_cmd="$tmux_cmd send-keys -t $((i-1)) 'bash -c \"trap pkill tmux:\\ server SIGINT; ./cmd.sh log $i || true; pkill tmux:\\ server\"' C-j \; "
    done

    eval $tmux_cmd

fi

#!/bin/bash

if [[ -e config.sh ]]; then
    source config.sh
    rm -rf $node_name_prefix-$service 2>/dev/null
fi

echo "  - Removing old data."
rm -rf qdata_[0-9] qdata_[0-9][0-9]
rm -f docker-compose.yml
rm -f contract_pri.js contract_pub.js
rm .current_config 2>/dev/null
rm genesis.json 2>/dev/null

# Shouldn't be needed, but just in case:
rm -f static-nodes.json genesis.json

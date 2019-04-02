#!/bin/bash

echo "  - Removing containers."
docker-compose --log-level ERROR down 2>/dev/null

echo "  - Removing old data."
rm -rf qdata_[0-9] qdata_[0-9][0-9]
rm -f contract_pri.js contract_pub.js
rm .current_config 2>/dev/null
rm genesis.json 2>/dev/null

# Shouldn't be needed, but just in case:
rm -f static-nodes.json genesis.json

rm -f docker-compose.yml

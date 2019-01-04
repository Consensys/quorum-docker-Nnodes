#!/bin/bash

echo "  - Removing containers."
docker-compose --log-level ERROR down 2>/dev/null

echo "  - Removing old data."
rm -rf qdata_[0-9] qdata_[0-9][0-9]
rm -f docker-compose.yml
rm -f contract_pri.js contract_pub.js

# Shouldn't be needed, but just in case:
rm -f static-nodes.json genesis.json

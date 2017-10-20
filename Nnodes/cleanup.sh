#!/bin/bash

rm -rf qdata_[0-9] qdata_[0-9][0-9]
rm -f docker-compose.yml
rm -f contract_pri.js contract_pub.js

# Shouldn't be needed, but just in case:
rm -f static-nodes.json genesis.json

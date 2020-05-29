#!/bin/bash

echo "  - Removing containers."
docker-compose --log-level ERROR down 2>/dev/null

echo "  - Removing old data."
rm -rf qdata_[0-9]/dd/geth qdata_[0-9][0-9]/dd/geth

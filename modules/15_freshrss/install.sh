#!/bin/bash
set -e

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Prepping FreshRSS storage directories..."
source environment/staging.env

# Ensure directories exist
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/freshrss/data"
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/freshrss/extensions"

# Set open permissions so the internal webserver user (www-data) can write to the data volumes
sudo chown -R 1000:1000 "${CONFIG_BASE_DIR:-/fastpool}/freshrss"

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Launching FreshRSS Container..."
cd modules/15_freshrss/compose
docker compose down
docker compose up -d

echo "[SUCCESS] FreshRSS is up and listening on port 8449!"

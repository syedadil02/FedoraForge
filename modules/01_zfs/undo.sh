#!/usr/bin/env bash
# modules/01_zfs/undo.sh
set -euo pipefail

# Safely destroy pools if they were partially created in the failed transaction
# This clears out the virtual disks so the staging loop can try again cleanly
if zpool list -H -o name | grep -q "^fastpool$"; then
    echo "[-] Tearing down uncommitted 'fastpool' datasets..."
    zpool destroy -f fastpool
fi

if zpool list -H -o name | grep -q "^datapool$"; then
    echo "[-] Tearing down uncommitted 'datapool' datasets..."
    zpool destroy -f datapool
fi

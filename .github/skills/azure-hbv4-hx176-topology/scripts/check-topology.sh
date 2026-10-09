#!/bin/bash
# Caller must confirm a covered full-size HBv4/HX VM before running.
# Usage: bash check-topology.sh [--sku <confirmed-vm-size>]
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/../../../scripts/check-topology.sh" hbv4-hx "$@"

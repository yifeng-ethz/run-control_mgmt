#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
runctl_mgmt_host UVM scaffold

Planned flow:
  1. build the UVM package and top under tb/uvm
  2. run randomized synclink / upload / MM log sweeps
  3. collect coverage for commands, backpressure, and recovery

No randomized harness is wired yet.
EOF


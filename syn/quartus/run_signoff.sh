#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_name="runctl_mgmt_host_syn"
revision="runctl_mgmt_host_syn"

cd "${script_dir}"
quartus_sh --flow compile "${project_name}" -c "${revision}"
"${script_dir}/report_resources.sh" "${revision}"

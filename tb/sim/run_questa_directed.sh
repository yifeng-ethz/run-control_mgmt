#!/usr/bin/env bash
set -euo pipefail

QUESTA_HOME="${QUESTA_HOME:-/data1/intelFPGA_pro/23.1/questa_fse}"
VLIB="${QUESTA_HOME}/bin/vlib"
VMAP="${QUESTA_HOME}/bin/vmap"
VCOM="${QUESTA_HOME}/bin/vcom"
VSIM="${QUESTA_HOME}/bin/vsim"

QUESTA_LICENSE="${QUESTA_HOME}/LR-287689_License.dat"
ETH_LIC_SERVER="8161@lic-mentor.ethz.ch"
if [[ -f "${QUESTA_LICENSE}" ]]; then
  export LM_LICENSE_FILE="${QUESTA_LICENSE}:${ETH_LIC_SERVER}"
else
  export LM_LICENSE_FILE="${ETH_LIC_SERVER}"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ip_dir="$(cd "${script_dir}/../.." && pwd)"
work_dir="${TB_WORK_DIR:-${script_dir}/work_directed}"
work_lib="work_runctl_mgmt_host_directed"
tb_top="tb_runctl_mgmt_host_directed"
log_file="${work_dir}/vsim.log"

intel_vhdl_libs="${QUESTA_HOME}/intel/vhdl"
intel_verilog_libs="${QUESTA_HOME}/intel/verilog"

if [[ ! -x "${VSIM}" ]]; then
  echo "ERROR: vsim not found under ${QUESTA_HOME}" >&2
  exit 2
fi

rm -rf -- "${work_dir}"
mkdir -p -- "${work_dir}"
cd -- "${work_dir}"

"${VLIB}" "${work_lib}"
"${VMAP}" "${work_lib}" "${work_lib}"
"${VMAP}" lpm "${intel_vhdl_libs}/220model"
"${VMAP}" altera "${intel_vhdl_libs}/altera"
"${VMAP}" altera_mf "${intel_vhdl_libs}/altera_mf"
"${VMAP}" altera_ver "${intel_verilog_libs}/altera"
"${VMAP}" altera_mf_ver "${intel_verilog_libs}/altera_mf"
"${VMAP}" altera_lnsim_ver "${intel_verilog_libs}/altera_lnsim"
"${VMAP}" lpm_ver "${intel_verilog_libs}/220model"
"${VMAP}" 220model_ver "${intel_verilog_libs}/220model"
"${VMAP}" twentynm_ver "${intel_verilog_libs}/twentynm"
"${VMAP}" sgate_ver "${intel_verilog_libs}/sgate"

"${VCOM}" -work "${work_lib}" -2008 "${script_dir}/logging_fifo_sim.vhd"
"${VCOM}" -work "${work_lib}" -2008 "${ip_dir}/runctl_mgmt_host.vhd"
"${VCOM}" -work "${work_lib}" -2008 "${script_dir}/tb_runctl_mgmt_host_directed.vhd"

"${VSIM}" -c -quiet "${work_lib}.${tb_top}" -do "run -all; quit -f" | tee "${log_file}"

if rg -n "\\*\\* Fatal:|\\*\\* Error:|^Fatal:" "${log_file}" >/dev/null; then
  echo "FAIL: ${tb_top}" >&2
  exit 1
fi
if ! rg -q "RUNCTL_MGMT_HOST_DIRECTED_PASS" "${log_file}"; then
  echo "FAIL: ${tb_top} (pass token missing)" >&2
  exit 1
fi

echo "PASS: ${tb_top}"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="${script_dir}/work_lint"
quartus_dir="${script_dir}/quartus_proj"
project_name="runctl_mgmt_host_lint"
revision="runctl_mgmt_host_lint"

source "${script_dir}/../../scripts/questa_one_env.sh"
INTEL_LIBS="${QUESTA_INTEL_VHDL_LIBS}"

rm -rf "${work_dir}"
rm -f "${script_dir}/layer1_source.log" "${script_dir}/layer2_elab.log" \
      "${script_dir}/layer3a_syn.rpt" "${script_dir}/layer3b_fit.rpt" \
      "${script_dir}/layer3c_sta_cdc.rpt" \
      "${script_dir}/layer3_design_assistant.rpt" "${script_dir}/summary.md"

mkdir -p "${work_dir}"
pushd "${work_dir}" >/dev/null
"${VLIB}" work >/dev/null
cp "${QSIM_INI}" modelsim.ini
chmod u+w modelsim.ini
"${VMAP}" -modelsimini modelsim.ini work work >/dev/null
"${VMAP}" -modelsimini modelsim.ini altera_mf "${INTEL_LIBS}/altera_mf" >/dev/null
{
  "${VCOM}" -modelsimini modelsim.ini -2008 -work work ../../altera_ip/logging_fifo.vhd
  "${VLOG}" -modelsimini modelsim.ini -sv -lint -pedanticerrors -work work \
    ../../rtl/runctl_mgmt_host.sv ../runctl_mgmt_host_lint_top.sv
} 2>&1 | tee "${script_dir}/layer1_source.log"
{
  "${VOPT}" -modelsimini modelsim.ini -work work -L altera_mf \
    runctl_mgmt_host_lint_top -o runctl_mgmt_host_lint_top_opt
} 2>&1 | tee "${script_dir}/layer2_elab.log"
popd >/dev/null

pushd "${quartus_dir}" >/dev/null
quartus_map "${project_name}" -c "${revision}" 2>&1 | tee "${script_dir}/layer3a_syn.rpt"
quartus_fit "${project_name}" -c "${revision}" 2>&1 | tee "${script_dir}/layer3b_fit.rpt"
quartus_sta "${project_name}" -c "${revision}" 2>&1 | tee "${script_dir}/layer3c_sta_cdc.rpt"
quartus_sta -t cdc_report.tcl 2>&1 | tee -a "${script_dir}/layer3c_sta_cdc.rpt"
quartus_drc "${project_name}" -c "${revision}" 2>&1 | tee "${script_dir}/layer3_design_assistant.rpt"
popd >/dev/null

python3 - "${script_dir}" <<'PY'
import datetime
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])

def counts(path: pathlib.Path) -> tuple[int, int]:
    text = path.read_text(errors="ignore") if path.exists() else ""
    quartus_summary = re.findall(
        r"(?im)^[ \t]*(?:Info:\s*)?.*?was successful\.\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?\b",
        text,
    )
    if quartus_summary:
        return (
            sum(int(err) for err, _ in quartus_summary),
            sum(int(warn) for _, warn in quartus_summary),
        )

    questa_summary = re.findall(
        r"(?im)^[ \t]*Errors:\s*(\d+),\s*Warnings:\s*(\d+)\b",
        text,
    )
    if questa_summary:
        return (
            sum(int(err) for err, _ in questa_summary),
            sum(int(warn) for _, warn in questa_summary),
        )

    err = len(re.findall(r"(?im)^[ \t]*(?:\*\*\s*)?Error\s*[:(]", text))
    warn = len(
        re.findall(
            r"(?im)^[ \t]*(?:\*\*\s*)?(?:Critical\s+Warning|Warning)\s*[:(]",
            text,
        )
    )
    return err, warn

entries = [
    ("Layer 1 source", "layer1_source.log"),
    ("Layer 2 elab", "layer2_elab.log"),
    ("Layer 3a syn DA", "layer3a_syn.rpt"),
    ("Layer 3b fit DA", "layer3b_fit.rpt"),
    ("Layer 3c sta CDC", "layer3c_sta_cdc.rpt"),
    ("Layer 3d design assistant", "layer3_design_assistant.rpt"),
]

lines = [
    "# rtl-lint summary: runctl_mgmt_host",
    "",
    f"_generated {datetime.datetime.now(datetime.timezone.utc).astimezone().isoformat(timespec='seconds')}_",
    "",
]
for title, rel in entries:
    err, warn = counts(root / rel)
    lines.extend([
        f"## {title}",
        f"- log: `lint/{rel}`",
        f"- errors: {err}",
        f"- warnings: {warn}",
        "",
    ])

(root / "summary.md").write_text("\n".join(lines))
PY

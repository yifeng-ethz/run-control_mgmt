################################################################################
# runctl_mgmt_host_hw.tcl
#
# Platform Designer (Qsys) component definition for the Run-Control Management
# Host Mu3e IP Core (SystemVerilog rewrite, version 26.3.0).
#
# This IP receives run-control commands on <synclink> (9-bit 8b/1k byte stream
# in the lvdspll_clk domain), decodes and fans them out on <runctl>, acks
# RUN_PREPARE / END_RUN on <upload>, and exposes a full CSR window on <csr>
# (Avalon-MM slave, word-addressed, mm_clk domain) with Mu3e identity header,
# 21 functional registers, and a 1024-deep x 32b log read-back port.
#
# Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
# Packaged: 2026-05-05
################################################################################

package require -exact qsys 16.1

################################################################################
# Version constants (Mu3e IP packaging convention)
################################################################################
# VERSION string format: YY.MINOR.PATCH.MMDD
set VERSION_MAJOR_DEFAULT_CONST 26        ;# 2-digit year
set VERSION_MINOR_DEFAULT_CONST 3         ;# feature revision
set VERSION_PATCH_DEFAULT_CONST 0         ;# bug-fix revision
set BUILD_DEFAULT_CONST         0505      ;# MMDD packaging date (May 5)
set VERSION_DATE_DEFAULT_CONST  20260505  ;# YYYYMMDD
set VERSION_GIT_DEFAULT_CONST   0xF3E2222 ;# `git rev-parse --short HEAD`
set INSTANCE_ID_DEFAULT_CONST   0
set IP_UID_DEFAULT_CONST        0x52434D48 ;# ASCII "RCMH"

set VERSION_STRING  "${VERSION_MAJOR_DEFAULT_CONST}.${VERSION_MINOR_DEFAULT_CONST}.${VERSION_PATCH_DEFAULT_CONST}.${BUILD_DEFAULT_CONST}"

################################################################################
# Module properties
################################################################################
set_module_property NAME                           runctl_mgmt_host
set_module_property DISPLAY_NAME                   "Run-Control Management Host"
set_module_property VERSION                        $VERSION_STRING
set_module_property DESCRIPTION                    "Run-Control Management Host Mu3e IP Core"
set_module_property GROUP                          "Mu3e Control Plane/Modules"
set_module_property AUTHOR                         "Yifeng Wang"
set_module_property ICON_PATH                      ../firmware_builds/misc/logo/mu3e_logo.png
set_module_property INTERNAL                       false
set_module_property OPAQUE_ADDRESS_MAP             true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE   true
set_module_property EDITABLE                       true
set_module_property REPORT_TO_TALKBACK             false
set_module_property ALLOW_GREYBOX_GENERATION       false
set_module_property REPORT_HIERARCHY               false
set_module_property ELABORATION_CALLBACK           elaborate
set_module_property VALIDATION_CALLBACK            validate

################################################################################
# File sets
################################################################################
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL runctl_mgmt_host
add_fileset_file runctl_mgmt_host.sv SYSTEM_VERILOG PATH rtl/runctl_mgmt_host.sv TOP_LEVEL_FILE
add_fileset_file logging_fifo.vhd    VHDL            PATH altera_ip/logging_fifo.vhd
add_fileset_file runctl_mgmt_host.sdc SDC             PATH runctl_mgmt_host.sdc

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL runctl_mgmt_host
add_fileset_file runctl_mgmt_host.sv SYSTEM_VERILOG PATH rtl/runctl_mgmt_host.sv
add_fileset_file logging_fifo.vhd    VHDL            PATH altera_ip/logging_fifo.vhd

################################################################################
# Helper: add_html_text
################################################################################
proc add_html_text {group_name item_name html_text} {
    add_display_item $group_name $item_name TEXT ""
    set_display_item_property $item_name DISPLAY_HINT html
    set_display_item_property $item_name TEXT $html_text
}

################################################################################
# Parameters - configuration
################################################################################
add_parameter RUN_START_ACK_SYMBOL STD_LOGIC_VECTOR 0xFE
set_parameter_property RUN_START_ACK_SYMBOL DISPLAY_NAME "Run Start Ack Symbol"
set_parameter_property RUN_START_ACK_SYMBOL WIDTH 8
set_parameter_property RUN_START_ACK_SYMBOL HDL_PARAMETER true
set_parameter_property RUN_START_ACK_SYMBOL DISPLAY_HINT hexadecimal
set_parameter_property RUN_START_ACK_SYMBOL ALLOWED_RANGES {"0xFE:K30.7" "0xFD:K29.7"}
set_parameter_property RUN_START_ACK_SYMBOL DESCRIPTION \
    "Byte inserted in the upload ack packet for the CMD_RUN_PREPARE acknowledgement. Default K30.7 (0xFE)."

add_parameter RUN_END_ACK_SYMBOL STD_LOGIC_VECTOR 0xFD
set_parameter_property RUN_END_ACK_SYMBOL DISPLAY_NAME "Run End Ack Symbol"
set_parameter_property RUN_END_ACK_SYMBOL WIDTH 8
set_parameter_property RUN_END_ACK_SYMBOL HDL_PARAMETER true
set_parameter_property RUN_END_ACK_SYMBOL DISPLAY_HINT hexadecimal
set_parameter_property RUN_END_ACK_SYMBOL ALLOWED_RANGES {"0xFE:K30.7" "0xFD:K29.7"}
set_parameter_property RUN_END_ACK_SYMBOL DESCRIPTION \
    "Byte inserted in the upload ack packet for the CMD_END_RUN acknowledgement. Default K29.7 (0xFD)."

add_parameter DEBUG NATURAL 1
set_parameter_property DEBUG DISPLAY_NAME "Debug Level"
set_parameter_property DEBUG HDL_PARAMETER true
set_parameter_property DEBUG ALLOWED_RANGES {0 1 2}
set_parameter_property DEBUG DESCRIPTION \
    "Debug instrumentation level. 0 = off, 1 = synthesizable, 2 = simulation-only."

add_parameter EXT_HARD_RESET_PULSE_CYCLES NATURAL 16384
set_parameter_property EXT_HARD_RESET_PULSE_CYCLES DISPLAY_NAME "External Hard Reset Pulse Cycles"
set_parameter_property EXT_HARD_RESET_PULSE_CYCLES HDL_PARAMETER true
set_parameter_property EXT_HARD_RESET_PULSE_CYCLES ALLOWED_RANGES 1:65535
set_parameter_property EXT_HARD_RESET_PULSE_CYCLES DESCRIPTION \
    "Number of lvdspll_clk cycles for the exported ext_hard_reset pulse after CMD_RESET. The local dp/ct hard resets still follow RESET/STOP_RESET state."

################################################################################
# Parameters - identity header (Mu3e standard)
################################################################################
add_parameter IP_UID STD_LOGIC_VECTOR $IP_UID_DEFAULT_CONST
set_parameter_property IP_UID DISPLAY_NAME "IP UID"
set_parameter_property IP_UID WIDTH 32
set_parameter_property IP_UID HDL_PARAMETER true
set_parameter_property IP_UID DISPLAY_HINT hexadecimal
set_parameter_property IP_UID DESCRIPTION \
    "4-character ASCII identifier of this IP core. Default 0x52434D48 = 'RCMH' (Run-Control Management Host). Integration-overridable."

add_parameter VERSION_MAJOR NATURAL $VERSION_MAJOR_DEFAULT_CONST
set_parameter_property VERSION_MAJOR DISPLAY_NAME "Version Major (YY)"
set_parameter_property VERSION_MAJOR HDL_PARAMETER true
set_parameter_property VERSION_MAJOR ALLOWED_RANGES 0:255
set_parameter_property VERSION_MAJOR ENABLED false
set_parameter_property VERSION_MAJOR DESCRIPTION \
    "Major version = 2-digit year. Packaged as $VERSION_MAJOR_DEFAULT_CONST ($VERSION_DATE_DEFAULT_CONST)."

add_parameter VERSION_MINOR NATURAL $VERSION_MINOR_DEFAULT_CONST
set_parameter_property VERSION_MINOR DISPLAY_NAME "Version Minor"
set_parameter_property VERSION_MINOR HDL_PARAMETER true
set_parameter_property VERSION_MINOR ALLOWED_RANGES 0:255
set_parameter_property VERSION_MINOR ENABLED false
set_parameter_property VERSION_MINOR DESCRIPTION \
    "Minor version within the year. Packaged as $VERSION_MINOR_DEFAULT_CONST."

add_parameter VERSION_PATCH NATURAL $VERSION_PATCH_DEFAULT_CONST
set_parameter_property VERSION_PATCH DISPLAY_NAME "Version Patch"
set_parameter_property VERSION_PATCH HDL_PARAMETER true
set_parameter_property VERSION_PATCH ALLOWED_RANGES 0:15
set_parameter_property VERSION_PATCH ENABLED false
set_parameter_property VERSION_PATCH DESCRIPTION \
    "Bug-fix revision (0..15). Packaged as $VERSION_PATCH_DEFAULT_CONST."

add_parameter BUILD NATURAL $BUILD_DEFAULT_CONST
set_parameter_property BUILD DISPLAY_NAME "Build (MMDD)"
set_parameter_property BUILD HDL_PARAMETER true
set_parameter_property BUILD ALLOWED_RANGES 0:4095
set_parameter_property BUILD ENABLED false
set_parameter_property BUILD DESCRIPTION \
    "4-digit MMDD build stamp. Packaged as $BUILD_DEFAULT_CONST."

add_parameter VERSION_DATE STD_LOGIC_VECTOR $VERSION_DATE_DEFAULT_CONST
set_parameter_property VERSION_DATE DISPLAY_NAME "Version Date (YYYYMMDD)"
set_parameter_property VERSION_DATE WIDTH 32
set_parameter_property VERSION_DATE HDL_PARAMETER true
set_parameter_property VERSION_DATE DISPLAY_HINT hexadecimal
set_parameter_property VERSION_DATE ENABLED false
set_parameter_property VERSION_DATE DESCRIPTION \
    "Full YYYYMMDD packaging date, exposed through the META page 1 register."

add_parameter GIT_STAMP_OVERRIDE BOOLEAN false
set_parameter_property GIT_STAMP_OVERRIDE DISPLAY_NAME "Override Git Stamp"
set_parameter_property GIT_STAMP_OVERRIDE HDL_PARAMETER false
set_parameter_property GIT_STAMP_OVERRIDE DESCRIPTION \
    "When enabled, allows manual entry of the git stamp. When disabled, the value is auto-populated from the last git commit hash at packaging time."

add_parameter VERSION_GIT STD_LOGIC_VECTOR $VERSION_GIT_DEFAULT_CONST
set_parameter_property VERSION_GIT DISPLAY_NAME "Version Git Stamp"
set_parameter_property VERSION_GIT WIDTH 32
set_parameter_property VERSION_GIT HDL_PARAMETER true
set_parameter_property VERSION_GIT DISPLAY_HINT hexadecimal
set_parameter_property VERSION_GIT ENABLED false
set_parameter_property VERSION_GIT DESCRIPTION \
    "Truncated 32-bit git short hash of the packaging commit. Default auto-populated from `git rev-parse --short HEAD`."

add_parameter INSTANCE_ID STD_LOGIC_VECTOR $INSTANCE_ID_DEFAULT_CONST
set_parameter_property INSTANCE_ID DISPLAY_NAME "Instance ID"
set_parameter_property INSTANCE_ID WIDTH 32
set_parameter_property INSTANCE_ID HDL_PARAMETER true
set_parameter_property INSTANCE_ID DISPLAY_HINT hexadecimal
set_parameter_property INSTANCE_ID DESCRIPTION \
    "Per-integration instance identifier, readable through META page 3."

################################################################################
# GUI Tabs (Mu3e 4-tab standard)
################################################################################
set TAB_CONFIGURATION "Configuration"
set TAB_IDENTITY      "Identity"
set TAB_INTERFACES    "Interfaces"
set TAB_REGMAP        "Register Map"

add_display_item "" $TAB_CONFIGURATION GROUP tab
add_display_item "" $TAB_IDENTITY      GROUP tab
add_display_item "" $TAB_INTERFACES    GROUP tab
add_display_item "" $TAB_REGMAP        GROUP tab

################################################################################
# Tab 1 — Configuration
################################################################################
add_display_item $TAB_CONFIGURATION "Overview"   GROUP
add_display_item $TAB_CONFIGURATION "Protocol"   GROUP
add_display_item $TAB_CONFIGURATION "Debug"      GROUP

add_html_text "Overview" overview_html {<html>
<b>Run-Control Management Host</b> is the on-FPGA receiver and dispatcher for
the Mu3e central run-control box.<br/><br/>
<ul>
<li>Parses 9-bit 8b/1k command bytes on <b>synclink</b> in the lvdspll_clk domain.</li>
<li>Decodes and fans out the run-control state on <b>runctl</b> (9-bit readyless AVST source).</li>
<li>Generates <b>upload</b> ack packets for <tt>CMD_RUN_PREPARE</tt> (K30.7 + run number) and <tt>CMD_END_RUN</tt> (K29.7).</li>
<li>Drives <b>dp_hard_reset</b> / <b>ct_hard_reset</b> on <tt>CMD_RESET</tt> / <tt>CMD_STOP_RESET</tt> and emits a bounded <b>ext_hard_reset</b> pulse on <tt>CMD_RESET</tt>. The local dp/ct conduits remain gated by the CONTROL CSR mask bits.</li>
<li>Exposes a 21-word CSR window on <b>csr</b> (5-bit word address, Avalon-MM slave) with identity header, live status, snapshots, saturating counters, atomic 48-bit GTS snapshot, and LOG_POP sub-word readback.</li>
<li>Hosts a <tt>dcfifo_mixed_widths</tt> 128b x 32b dual-clock FIFO for run-command logging (256 x 128b write, 1024 x 32b read).</li>
</ul>
<br/>
<b>Clocking:</b> dual-clock. <tt>mm_clk</tt> is arbitrary (100-200 MHz typical); <tt>lvdspll_clk</tt> is 125 MHz from the LVDS PLL (data-path clock).
All cross-domain paths are CDC-safe: toggle-handshake for mm&rarr;lvds local_cmd injection, gray-code for the 48-bit GTS snapshot and the 32-bit saturating counters, toggle-handshake for lvds&rarr;mm status-snapshot updates, and 2FF synchronizers for single-bit status bits.
</html>}

add_html_text "Protocol" protocol_html {<html>
<b>Run command protocol</b> (see Mu3e-Note-0046 &ldquo;Run Start and Reset Protocol&rdquo;).<br/><br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Code</th><th>Name</th><th>Payload</th><th>Effect</th></tr>
<tr><td>0x10</td><td>RUN_PREPARE</td><td>32b run number, least-significant byte first on synclink</td><td>Fanout + upload ack K30.7 with run number in data[31:8]</td></tr>
<tr><td>0x11</td><td>RUN_SYNC</td><td>-</td><td>Fanout only</td></tr>
<tr><td>0x12</td><td>START_RUN</td><td>-</td><td>Fanout only</td></tr>
<tr><td>0x13</td><td>END_RUN</td><td>-</td><td>Fanout + upload ack K29.7</td></tr>
<tr><td>0x14</td><td>ABORT_RUN</td><td>-</td><td>Fanout only</td></tr>
<tr><td>0x30</td><td>RESET</td><td>16b assert mask</td><td>Pulse exported ext_hard_reset and assert local dp/ct_hard_reset (local conduits masked by CONTROL)</td></tr>
<tr><td>0x31</td><td>STOP_RESET</td><td>16b release mask</td><td>Cancel any active ext_hard_reset pulse and release local dp/ct_hard_reset (local conduits masked by CONTROL)</td></tr>
<tr><td>0x32</td><td>ENABLE</td><td>-</td><td>Fanout only</td></tr>
<tr><td>0x33</td><td>DISABLE</td><td>-</td><td>Fanout only</td></tr>
<tr><td>0x40</td><td>ADDRESS</td><td>16b FPGA addr</td><td>Latches FPGA_ADDRESS CSR; <b>no</b> runctl fanout</td></tr>
</table>
<br/>
Unknown command bytes are silently dropped (no fanout, no log, no counter increment). Commands can be injected from the mm side via <tt>LOCAL_CMD</tt>; the recv FSM gives local_cmd priority over synclink when both arrive in the same cycle.
</html>}

add_display_item "Protocol" RUN_START_ACK_SYMBOL PARAMETER
add_display_item "Protocol" RUN_END_ACK_SYMBOL   PARAMETER
add_display_item "Protocol" EXT_HARD_RESET_PULSE_CYCLES PARAMETER

add_display_item "Debug" DEBUG PARAMETER
add_html_text "Debug" debug_html {<html>
Debug instrumentation level. <b>0</b> disables all debug logic, <b>1</b> (default) enables synthesizable debug probes, <b>2</b> enables simulation-only checks that are not synthesizable.
</html>}

################################################################################
# Tab 2 — Identity
################################################################################
add_display_item $TAB_IDENTITY "Delivered Profile" GROUP
add_display_item $TAB_IDENTITY "Versioning"        GROUP

add_html_text "Delivered Profile" delivered_html "<html>
This catalog entry packages the Run-Control Management Host at revision
<b>${VERSION_STRING}</b>, date <b>${VERSION_DATE_DEFAULT_CONST}</b>, git stamp
<tt>[format {0x%X} $VERSION_GIT_DEFAULT_CONST]</tt>.<br/><br/>
<ul>
<li>SystemVerilog rewrite replacing <tt>legacy/runctl_mgmt_host_v24.vhd</tt>.</li>
<li>21-word CSR block (5-bit word address) including Mu3e identity header (UID + META page mux).</li>
<li>Atomic 48-bit GTS snapshot, saturating RX_CMD / RX_ERR / log_drop counters.</li>
<li>LOCAL_CMD injection path with toggle-handshake CDC and waitrequest-stall on busy.</li>
<li>CONTROL-masked dp/ct_hard_reset outputs plus bounded exported ext_hard_reset pulse for other subsystems.</li>
</ul>
<br/>
Runtime visibility: the first CSR word (UID = 'RCMH') plus the META mux
(VERSION / DATE / GIT / INSTANCE_ID) lets software identify this IP instance
without hierarchical introspection.
</html>"

add_display_item "Versioning" IP_UID             PARAMETER
add_display_item "Versioning" VERSION_MAJOR      PARAMETER
add_display_item "Versioning" VERSION_MINOR      PARAMETER
add_display_item "Versioning" VERSION_PATCH      PARAMETER
add_display_item "Versioning" BUILD              PARAMETER
add_display_item "Versioning" VERSION_DATE       PARAMETER
add_display_item "Versioning" GIT_STAMP_OVERRIDE PARAMETER
add_display_item "Versioning" VERSION_GIT        PARAMETER
add_display_item "Versioning" INSTANCE_ID        PARAMETER

add_html_text "Versioning" versioning_html "<html>
<b>Version string format:</b> <tt>YY.MINOR.PATCH.MMDD</tt><br/>
<b>Packaged version:</b> <tt>${VERSION_STRING}</tt> (Year 20${VERSION_MAJOR_DEFAULT_CONST}, build ${BUILD_DEFAULT_CONST}).<br/>
<b>META page mux</b> — write the page selector to <tt>META\[1:0\]</tt>, then read
<tt>META</tt> to get the selected word:
<table border='1' cellpadding='3' width='100%'>
<tr><th>Page</th><th>Content</th><th>Width</th></tr>
<tr><td>0</td><td>VERSION = {MAJOR\[31:24\], MINOR\[23:16\], PATCH\[15:12\], BUILD\[11:0\]}</td><td>32b</td></tr>
<tr><td>1</td><td>DATE = YYYYMMDD packed</td><td>32b</td></tr>
<tr><td>2</td><td>GIT = truncated git short hash</td><td>32b</td></tr>
<tr><td>3</td><td>INSTANCE_ID</td><td>32b</td></tr>
</table>
<br/>
The version parameters are non-editable by design (the packaging TCL is the
single source of truth). <tt>GIT_STAMP_OVERRIDE</tt> allows manual override of
the git stamp; when disabled, the default <tt>[format {0x%X} $VERSION_GIT_DEFAULT_CONST]</tt>
is used. <tt>INSTANCE_ID</tt> is freely settable per-integration.
</html>"

################################################################################
# Tab 3 — Interfaces
################################################################################
add_display_item $TAB_INTERFACES "Clock / Reset"  GROUP
add_display_item $TAB_INTERFACES "Data Path"      GROUP
add_display_item $TAB_INTERFACES "Control Path"   GROUP
add_display_item $TAB_INTERFACES "Hard Resets"    GROUP

add_html_text "Clock / Reset" clocks_html {<html>
<b>mm_clk / mm_reset</b> &mdash; Avalon-MM CSR slave clock/reset. Arbitrary frequency (typ. 100-200 MHz); asynchronous to lvdspll_clk. Reset is synchronous (synchronousEdges=BOTH).<br/><br/>
<b>lvdspll_clk / lvdspll_reset</b> &mdash; 125 MHz data-path clock from the LVDS PLL. All receive, decode, fanout, upload, hard-reset and log-write logic runs in this domain.<br/><br/>
<b>lvdspll_reset</b> should <b>not</b> be connected to <b>dp_hard_reset</b>, <b>ct_hard_reset</b>, or <b>ext_hard_reset</b> to avoid deadlock; it should be driven by the JTAG master, the LVDS PLL arst, and/or a push-button.
</html>}

add_html_text "Data Path" datapath_html {<html>
<b>synclink</b> &mdash; 9-bit AVST sink (data + error) carrying the 8b/1k byte stream from the central run-control box. No ready/valid (passive stream; every lvdspll_clk cycle is a byte).<br/>
<b>upload</b> &mdash; 36-bit AVST source (sop/eop) emitting RC ack packets. Bits <tt>[35:32]</tt> are the k-flag field, <tt>[7:0]</tt> is the ack symbol, <tt>[31:8]</tt> is the 24-bit run number (RUN_PREPARE only).<br/>
<b>runctl</b> &mdash; 9-bit AVST source emitting one-hot decoded run-control states to all on-FPGA agents. The stream is readyless: <tt>valid</tt> marks a one-cycle broadcast beat and downstream agents cannot backpressure it.
<br/><br/>
</html>}

add_html_text "Data Path" synclink_fmt_html {<html>
<b>synclink</b> &mdash; 9-bit Avalon-ST sink<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bits</th><th>Field</th><th>Description</th></tr>
<tr><td>data[8]</td><td>k-flag</td><td>1 = control symbol, 0 = data byte (command or payload)</td></tr>
<tr><td>data[7:0]</td><td>byte</td><td>Command byte (in RECV_IDLE) or payload byte (in RECV_RX_PAYLOAD). RUN_PREPARE run-number payload follows the SWB reset-link order: byte 0 = run_number[7:0], byte 3 = run_number[31:24].</td></tr>
<tr><td>error[2]</td><td>loss_sync</td><td>Link not trained - recv FSM ignores data</td></tr>
<tr><td>error[1]</td><td>parity</td><td>Parity error - drops current command, RX_ERR_COUNT++</td></tr>
<tr><td>error[0]</td><td>decode</td><td>8b/1k decode error - drops current command, RX_ERR_COUNT++</td></tr>
</table></html>}

add_html_text "Data Path" upload_fmt_html {<html>
<b>upload</b> &mdash; 36-bit Avalon-ST source (sop=eop=1, single-beat packets)<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bits</th><th>Field</th><th>Description</th></tr>
<tr><td>data[35:32]</td><td>k-flag</td><td>Always 4'b0001 for ack packets</td></tr>
<tr><td>data[31:8]</td><td>run_number[23:0]</td><td>RUN_PREPARE only; 0 for END_RUN</td></tr>
<tr><td>data[7:0]</td><td>ack_symbol</td><td>RUN_START_ACK_SYMBOL (K30.7=0xFE) for RUN_PREPARE; RUN_END_ACK_SYMBOL (K29.7=0xFD) for END_RUN</td></tr>
</table></html>}

add_html_text "Data Path" runctl_fmt_html {<html>
<b>runctl</b> &mdash; 9-bit readyless Avalon-ST source (one-hot state fanout)<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>State</th><th>Source command</th></tr>
<tr><td>data[0]</td><td>IDLE</td><td>CMD_ABORT_RUN, CMD_STOP_RESET, CMD_ENABLE, unknown</td></tr>
<tr><td>data[1]</td><td>RUN_PREPARE</td><td>CMD_RUN_PREPARE (0x10)</td></tr>
<tr><td>data[2]</td><td>RUN_SYNC</td><td>CMD_RUN_SYNC (0x11)</td></tr>
<tr><td>data[3]</td><td>START_RUN</td><td>CMD_START_RUN (0x12)</td></tr>
<tr><td>data[4]</td><td>END_RUN</td><td>CMD_END_RUN (0x13)</td></tr>
<tr><td>data[7]</td><td>RESET</td><td>CMD_RESET (0x30)</td></tr>
<tr><td>data[8]</td><td>OUT_OF_DAQ</td><td>CMD_DISABLE (0x33)</td></tr>
</table>
Note: <tt>CMD_ADDRESS (0x40)</tt> does <b>not</b> fan out on runctl; only latches the FPGA_ADDRESS CSR.
</html>}

add_html_text "Control Path" csr_intf_html {<html>
<b>csr</b> &mdash; Avalon-MM slave, 5-bit word address (32 words), 32-bit data, mm_clk domain.<br/><br/>
<ul>
<li>1-cycle read latency with <tt>waitrequest</tt> acknowledgement.</li>
<li>Writes to RO words complete in 1 cycle with no side effects (CSR is tolerant of stale software).</li>
<li>LOCAL_CMD writes stall via <tt>waitrequest</tt> when <tt>local_cmd_busy=1</tt> (toggle-handshake CDC in flight).</li>
<li>CONTROL soft_reset and log_flush W1P bits hold <tt>waitrequest</tt> until the FIFO drain completes.</li>
</ul>
See the <b>Register Map</b> tab for the full word/field breakdown.
</html>}

add_html_text "Hard Resets" hardreset_html {<html>
<b>dp_hard_reset</b> / <b>ct_hard_reset</b> / <b>ext_hard_reset</b> &mdash; 1-bit reset-source conduits in the lvdspll_clk domain, clocked on the <tt>pipe_r2h_done</tt> rising edge when <tt>CMD_RESET</tt> or <tt>CMD_STOP_RESET</tt> is processed. <tt>ext_hard_reset</tt> is the exported subsystem reset pulse; it asserts for <tt>EXT_HARD_RESET_PULSE_CYCLES</tt> lvdspll_clk cycles on RESET and auto-releases so the LVDS/upload response path is not held until STOP_RESET. STOP_RESET cancels any active ext pulse. The local conduits remain gated by the CONTROL CSR mask bits and retain state until STOP_RESET: <tt>rst_mask_dp=1</tt> suppresses <tt>dp_hard_reset</tt> toggles, <tt>rst_mask_ct=1</tt> suppresses <tt>ct_hard_reset</tt> toggles. Ideal for integration into the wider Quartus reset graph.
</html>}

################################################################################
# Tab 4 — Register Map
################################################################################
add_display_item $TAB_REGMAP "CSR Window" GROUP

add_html_text "CSR Window" csr_window_html {<html>
<b>CSR window</b> &mdash; 21 functional words at 5-bit word addresses (0x00..0x14). Word 0x00 is the identity UID; words 0x01..0x14 are functional CSRs.<br/><br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Addr</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0x00</td><td>UID</td><td>RO</td><td>32-bit ASCII &lsquo;RCMH&rsquo; = 0x52434D48</td></tr>
<tr><td>0x01</td><td>META</td><td>RW/RO</td><td>Write [1:0] = page selector; read returns page content (VERSION / DATE / GIT / INSTANCE_ID)</td></tr>
<tr><td>0x02</td><td>CONTROL</td><td>RW</td><td>soft_reset, log_flush, rst_mask_dp, rst_mask_ct</td></tr>
<tr><td>0x03</td><td>STATUS</td><td>RO</td><td>recv_idle, host_idle, dp_hr, ct_hr, state encodings, local_cmd_busy, log_fifo_empty</td></tr>
<tr><td>0x04</td><td>LAST_CMD</td><td>RO</td><td>[7:0] last command byte, [31:16] last FPGA address</td></tr>
<tr><td>0x05</td><td>SCRATCH</td><td>RW</td><td>32-bit general-purpose scratch</td></tr>
<tr><td>0x06</td><td>RUN_NUMBER</td><td>RO</td><td>32-bit last run number from CMD_RUN_PREPARE</td></tr>
<tr><td>0x07</td><td>RESET_MASK</td><td>RO</td><td>[15:0] last assert mask, [31:16] last release mask</td></tr>
<tr><td>0x08</td><td>FPGA_ADDRESS</td><td>RO</td><td>[15:0] address, [31] sticky-valid</td></tr>
<tr><td>0x09</td><td>RECV_TS_L</td><td>RO</td><td>recv_ts[31:0] of the most recent command</td></tr>
<tr><td>0x0A</td><td>RECV_TS_H</td><td>RO</td><td>recv_ts[47:32]</td></tr>
<tr><td>0x0B</td><td>EXEC_TS_L</td><td>RO</td><td>exec_ts[31:0] of the most recent command</td></tr>
<tr><td>0x0C</td><td>EXEC_TS_H</td><td>RO</td><td>exec_ts[47:32]</td></tr>
<tr><td>0x0D</td><td>GTS_L</td><td>RO</td><td>Live gts[31:0]; read atomically latches gts[47:32] into GTS_H shadow</td></tr>
<tr><td>0x0E</td><td>GTS_H</td><td>RO</td><td>Latched gts[47:32] from the last GTS_L read</td></tr>
<tr><td>0x0F</td><td>RX_CMD_COUNT</td><td>RO</td><td>Saturating accepted-command counter</td></tr>
<tr><td>0x10</td><td>RX_ERR_COUNT</td><td>RO</td><td>Saturating synclink error counter (parity / decode / loss_sync)</td></tr>
<tr><td>0x11</td><td>LOG_STATUS</td><td>RO</td><td>[9:0] rdusedw, [16] rdempty, [17] rdfull</td></tr>
<tr><td>0x12</td><td>LOG_POP</td><td>RO</td><td>Reading auto-pops one 32-bit log sub-word; 0 when empty</td></tr>
<tr><td>0x13</td><td>LOCAL_CMD</td><td>RW</td><td>Write a 32-bit local command word; stalls via waitrequest while local_cmd_busy=1</td></tr>
<tr><td>0x14</td><td>ACK_SYMBOLS</td><td>RO</td><td>[7:0] RUN_START_ACK_SYMBOL, [15:8] RUN_END_ACK_SYMBOL</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "META Fields (0x01)" GROUP
add_html_text "META Fields (0x01)" meta_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>1:0</td><td>page_selector</td><td>RW</td><td>0</td><td>Page selector for the multiplexed identity word</td></tr>
<tr><td>31:2</td><td>reserved</td><td>RO</td><td>0</td><td>Write ignored; read as 0 on writes (reads return the selected page content)</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "CONTROL Fields (0x02)" GROUP
add_html_text "CONTROL Fields (0x02)" control_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>0</td><td>soft_reset</td><td>W1P</td><td>0</td><td>Pulse: CDC toggle to lvds resets recv/host/upload FSMs; waitrequest held until mm-side log drain completes</td></tr>
<tr><td>1</td><td>log_flush</td><td>W1P</td><td>0</td><td>Pulse: drains the mm-side log FIFO until rdempty=1</td></tr>
<tr><td>3:2</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
<tr><td>4</td><td>rst_mask_dp</td><td>RW</td><td>0</td><td>1 = suppress dp_hard_reset assertion on CMD_RESET / CMD_STOP_RESET</td></tr>
<tr><td>5</td><td>rst_mask_ct</td><td>RW</td><td>0</td><td>1 = suppress ct_hard_reset assertion on CMD_RESET / CMD_STOP_RESET</td></tr>
<tr><td>31:6</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "STATUS Fields (0x03)" GROUP
add_html_text "STATUS Fields (0x03)" status_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>0</td><td>recv_idle</td><td>RO</td><td>1</td><td>synclink_recv FSM in RECV_IDLE</td></tr>
<tr><td>1</td><td>host_idle</td><td>RO</td><td>1</td><td>runctl_host FSM in HOST_IDLE</td></tr>
<tr><td>3:2</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved</td></tr>
<tr><td>4</td><td>dp_hard_reset</td><td>RO</td><td>0</td><td>Live dp_hard_reset output (post-mask, 2FF-sync'd from lvds)</td></tr>
<tr><td>5</td><td>ct_hard_reset</td><td>RO</td><td>0</td><td>Live ct_hard_reset output</td></tr>
<tr><td>7:6</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved</td></tr>
<tr><td>15:8</td><td>recv_state_enc</td><td>RO</td><td>0</td><td>Encoded recv FSM state: 0=IDLE, 1=RX_PAYLOAD, 2=LOGGING, 3=LOG_ERROR, 4=CLEANUP</td></tr>
<tr><td>23:16</td><td>host_state_enc</td><td>RO</td><td>0</td><td>Encoded host FSM state: 0=IDLE, 1=POSTING, 2=CLEANUP</td></tr>
<tr><td>29:24</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved</td></tr>
<tr><td>30</td><td>local_cmd_busy</td><td>RO</td><td>0</td><td>LOCAL_CMD toggle handshake in flight (mm&rarr;lvds)</td></tr>
<tr><td>31</td><td>log_fifo_empty</td><td>RO</td><td>1</td><td>Log FIFO read side empty</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "LAST_CMD Fields (0x04)" GROUP
add_html_text "LAST_CMD Fields (0x04)" last_cmd_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>7:0</td><td>last_run_command</td><td>RO</td><td>0</td><td>Last latched command byte (any of 0x10..0x14 / 0x30..0x33 / 0x40)</td></tr>
<tr><td>15:8</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
<tr><td>31:16</td><td>last_fpga_address</td><td>RO</td><td>0</td><td>Last CMD_ADDRESS payload (mirror of FPGA_ADDRESS[15:0])</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "RESET_MASK Fields (0x07)" GROUP
add_html_text "RESET_MASK Fields (0x07)" reset_mask_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>15:0</td><td>last_assert_mask</td><td>RO</td><td>0</td><td>Payload of the most recent CMD_RESET (0x30)</td></tr>
<tr><td>31:16</td><td>last_release_mask</td><td>RO</td><td>0</td><td>Payload of the most recent CMD_STOP_RESET (0x31)</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "FPGA_ADDRESS Fields (0x08)" GROUP
add_html_text "FPGA_ADDRESS Fields (0x08)" fpga_addr_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>15:0</td><td>fpga_address</td><td>RO</td><td>0</td><td>Payload of the most recent CMD_ADDRESS (0x40)</td></tr>
<tr><td>30:16</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
<tr><td>31</td><td>valid_sticky</td><td>RO</td><td>0</td><td>Sticky: set on first CMD_ADDRESS, never cleared without reset</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "LOG_STATUS Fields (0x11)" GROUP
add_html_text "LOG_STATUS Fields (0x11)" log_status_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>9:0</td><td>rdusedw</td><td>RO</td><td>0</td><td>Read-side used-word count (1024 x 32b)</td></tr>
<tr><td>15:10</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
<tr><td>16</td><td>rdempty</td><td>RO</td><td>1</td><td>FIFO read side empty</td></tr>
<tr><td>17</td><td>rdfull</td><td>RO</td><td>0</td><td>FIFO read side full</td></tr>
<tr><td>31:18</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "ACK_SYMBOLS Fields (0x14)" GROUP
add_html_text "ACK_SYMBOLS Fields (0x14)" ack_symbols_fields_html {<html>
<table border="1" cellpadding="3" width="100%">
<tr><th>Bit</th><th>Name</th><th>Access</th><th>Reset</th><th>Description</th></tr>
<tr><td>7:0</td><td>run_start_ack_symbol</td><td>RO</td><td>0xFE</td><td>K30.7 (RUN_PREPARE ack)</td></tr>
<tr><td>15:8</td><td>run_end_ack_symbol</td><td>RO</td><td>0xFD</td><td>K29.7 (END_RUN ack)</td></tr>
<tr><td>31:16</td><td>reserved</td><td>RO</td><td>0</td><td>Reserved, read as zero</td></tr>
</table></html>}

add_display_item $TAB_REGMAP "Log Entry Layout" GROUP
add_html_text "Log Entry Layout" log_entry_html {<html>
Each accepted command writes one 128-bit entry to the log FIFO. Software pops the entry as four 32-bit sub-words via <tt>LOG_POP</tt>:<br/>
<table border="1" cellpadding="3" width="100%">
<tr><th>Sub-word</th><th>Bits</th><th>Content</th></tr>
<tr><td>0</td><td>31:0</td><td>recv_ts[47:16]</td></tr>
<tr><td>1</td><td>31:16</td><td>recv_ts[15:0]</td></tr>
<tr><td>1</td><td>15:8</td><td>reserved (0)</td></tr>
<tr><td>1</td><td>7:0</td><td>run_command[7:0]</td></tr>
<tr><td>2</td><td>31:0</td><td>payload32 (run_number / {0, assert_mask} / {0, release_mask} / {0, fpga_address} / 0)</td></tr>
<tr><td>3</td><td>31:0</td><td>exec_ts[31:0]</td></tr>
</table>
FIFO depth: 256 x 128b write-side, 1024 x 32b read-side (same total 32 kbit of M10K).
</html>}

################################################################################
# Interfaces — ports and clocks/resets
################################################################################
# synclink (AVST sink, lvdspll_clk)
add_interface synclink avalon_streaming end
set_interface_property synclink associatedClock   lvdspll_clock
set_interface_property synclink associatedReset   lvdspll_reset
set_interface_property synclink dataBitsPerSymbol 9
add_interface_port synclink asi_synclink_data  data  Input 9
add_interface_port synclink asi_synclink_error error Input 3

# upload (AVST source, lvdspll_clk, 36-bit with sop/eop)
add_interface upload avalon_streaming start
set_interface_property upload associatedClock   lvdspll_clock
set_interface_property upload associatedReset   lvdspll_reset
set_interface_property upload dataBitsPerSymbol 36
add_interface_port upload aso_upload_data          data           Output 36
add_interface_port upload aso_upload_valid         valid          Output 1
add_interface_port upload aso_upload_ready         ready          Input  1
add_interface_port upload aso_upload_startofpacket startofpacket  Output 1
add_interface_port upload aso_upload_endofpacket   endofpacket    Output 1

# runctl (AVST source, lvdspll_clk, 9-bit)
add_interface runctl avalon_streaming start
set_interface_property runctl associatedClock   lvdspll_clock
set_interface_property runctl associatedReset   lvdspll_reset
set_interface_property runctl dataBitsPerSymbol 9
add_interface_port runctl aso_runctl_data  data  Output 9
add_interface_port runctl aso_runctl_valid valid Output 1

# csr (AVMM slave, mm_clk, 5-bit word address, 32-bit data)
add_interface csr avalon end
set_interface_property csr addressUnits             WORDS
set_interface_property csr associatedClock          mm_clock
set_interface_property csr associatedReset          mm_reset
set_interface_property csr bitsPerSymbol            8
set_interface_property csr burstOnBurstBoundariesOnly false
set_interface_property csr burstcountUnits          WORDS
set_interface_property csr explicitAddressSpan      0
set_interface_property csr holdTime                 0
set_interface_property csr linewrapBursts           false
set_interface_property csr maximumPendingReadTransactions 0
set_interface_property csr maximumPendingWriteTransactions 0
set_interface_property csr readLatency              0
set_interface_property csr readWaitTime             1
set_interface_property csr setupTime                0
set_interface_property csr timingUnits              Cycles
set_interface_property csr writeWaitTime            0
add_interface_port csr avs_csr_address     address     Input  5
add_interface_port csr avs_csr_read        read        Input  1
add_interface_port csr avs_csr_readdata    readdata    Output 32
add_interface_port csr avs_csr_write       write       Input  1
add_interface_port csr avs_csr_writedata   writedata   Input  32
add_interface_port csr avs_csr_waitrequest waitrequest Output 1

# mm_clock / mm_reset
add_interface mm_clock clock end
set_interface_property mm_clock clockRate 0
add_interface_port mm_clock mm_clk clk Input 1

add_interface mm_reset reset end
set_interface_property mm_reset associatedClock   mm_clock
set_interface_property mm_reset synchronousEdges  BOTH
add_interface_port mm_reset mm_reset reset Input 1

# lvdspll_clock / lvdspll_reset
add_interface lvdspll_clock clock end
set_interface_property lvdspll_clock clockRate 125000000
add_interface_port lvdspll_clock lvdspll_clk clk Input 1

add_interface lvdspll_reset reset end
set_interface_property lvdspll_reset associatedClock   lvdspll_clock
set_interface_property lvdspll_reset synchronousEdges  BOTH
add_interface_port lvdspll_reset lvdspll_reset reset Input 1

# dp_hard_reset / ct_hard_reset / ext_hard_reset (reset source conduits)
add_interface dp_hard_reset reset start
set_interface_property dp_hard_reset associatedClock      lvdspll_clock
set_interface_property dp_hard_reset associatedResetSinks lvdspll_reset
set_interface_property dp_hard_reset synchronousEdges     NONE
add_interface_port dp_hard_reset dp_hard_reset reset Output 1

add_interface ct_hard_reset reset start
set_interface_property ct_hard_reset associatedClock      lvdspll_clock
set_interface_property ct_hard_reset associatedResetSinks lvdspll_reset
set_interface_property ct_hard_reset synchronousEdges     NONE
add_interface_port ct_hard_reset ct_hard_reset reset Output 1

add_interface ext_hard_reset reset start
set_interface_property ext_hard_reset associatedClock      lvdspll_clock
set_interface_property ext_hard_reset associatedResetSinks lvdspll_reset
set_interface_property ext_hard_reset synchronousEdges     NONE
add_interface_port ext_hard_reset ext_hard_reset reset Output 1

################################################################################
# Validation and elaboration callbacks
################################################################################
proc compute_derived_values {} {
    # No derived parameters in this IP (CSR width and log FIFO geometry are fixed).
}

proc validate {} {
    compute_derived_values
    set dbg [get_parameter_value DEBUG]
    if {$dbg < 0 || $dbg > 2} {
        send_message error "DEBUG level must be in {0,1,2}"
    }
    set rstart [get_parameter_value RUN_START_ACK_SYMBOL]
    set rend   [get_parameter_value RUN_END_ACK_SYMBOL]
    if {$rstart == $rend} {
        send_message warning "RUN_START_ACK_SYMBOL == RUN_END_ACK_SYMBOL; software cannot disambiguate the two ack classes."
    }
}

proc elaborate {} {
    compute_derived_values
    # Enable/disable the VERSION_GIT field based on the override toggle
    if {[get_parameter_value GIT_STAMP_OVERRIDE]} {
        set_parameter_property VERSION_GIT ENABLED true
    } else {
        set_parameter_property VERSION_GIT ENABLED false
    }
}

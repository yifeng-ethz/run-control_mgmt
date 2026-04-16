package require ::quartus::project
package require ::quartus::sta

project_open runctl_mgmt_host_lint -revision runctl_mgmt_host_lint
create_timing_netlist
read_sdc
update_timing_netlist

puts "CDC/clock-transfer review for runctl_mgmt_host_lint"
report_clock_transfers
project_close

include ../../scripts/questa_one.mk

IP_ROOT     := $(abspath ..)
TB_ROOT     := $(abspath .)
TB_SIM_DIR  := $(TB_ROOT)/sim
TB_UVM_DIR  := $(TB_ROOT)/uvm
WORK_DIR    := $(TB_ROOT)/work_runctl_uvm
GATE_WORK_DIR := $(TB_ROOT)/work_runctl_gate
LOG_DIR     := $(TB_ROOT)/logs
MODELSIM_INI := modelsim.ini
UVM_HOME    := $(QUESTA_UVM_HOME)
INTEL_LIBS  := $(QUESTA_INTEL_VHDL_LIBS)
UVM_SRC     := $(UVM_HOME)/src
QUARTUS_HOME ?= /data1/intelFPGA/18.1/quartus
GATE_SIM_DIR := $(IP_ROOT)/syn/quartus/gate_sim
GATE_NETLIST := $(GATE_SIM_DIR)/runctl_mgmt_host_syn.vo
DPI_CPP     ?= /usr/bin/gcc

TEST ?= runctl_mgmt_host_smoke_test
TB_TOP := tb_top

.PHONY: compile_uvm run_uvm_smoke run_uvm generate_gate_netlist compile_gate_uvm run_gate_uvm_smoke clean

compile_uvm: $(WORK_DIR)/.compiled

$(WORK_DIR)/.compiled: \
  $(IP_ROOT)/rtl/runctl_mgmt_host.sv \
  $(IP_ROOT)/altera_ip/logging_fifo.vhd \
  $(TB_SIM_DIR)/common/runctl_mgmt_pkg.sv \
  $(TB_SIM_DIR)/runctl_mgmt_host_dut_wrapper.sv \
  $(TB_UVM_DIR)/ifs/synclink_if.sv \
  $(TB_UVM_DIR)/ifs/runctl_if.sv \
  $(TB_UVM_DIR)/ifs/upload_if.sv \
  $(TB_UVM_DIR)/ifs/csr_if.sv \
  $(TB_UVM_DIR)/ifs/reset_if.sv \
  $(TB_UVM_DIR)/runctl_mgmt_env_pkg.sv \
  $(TB_UVM_DIR)/tb_top.sv
	@echo "=== Compiling runctl_mgmt_host UVM smoke bench ==="
	@rm -rf $(WORK_DIR)
	@mkdir -p $(WORK_DIR) $(LOG_DIR)
	@cd $(WORK_DIR) && $(VLIB) work
	@cp $(QSIM_INI) $(WORK_DIR)/$(MODELSIM_INI)
	@chmod u+w $(WORK_DIR)/$(MODELSIM_INI)
	@cd $(WORK_DIR) && $(VMAP) -modelsimini $(MODELSIM_INI) work work > /dev/null
	@cd $(WORK_DIR) && $(VMAP) -modelsimini $(MODELSIM_INI) altera_mf $(INTEL_LIBS)/altera_mf > /dev/null
	@cd $(WORK_DIR) && $(VCOM) -modelsimini $(MODELSIM_INI) -2008 -work work $(IP_ROOT)/altera_ip/logging_fifo.vhd
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(IP_ROOT)/rtl/runctl_mgmt_host.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_SIM_DIR)/common/runctl_mgmt_pkg.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_UVM_DIR)/ifs/synclink_if.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_UVM_DIR)/ifs/runctl_if.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_UVM_DIR)/ifs/upload_if.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_UVM_DIR)/ifs/csr_if.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_UVM_DIR)/ifs/reset_if.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work $(TB_SIM_DIR)/runctl_mgmt_host_dut_wrapper.sv
	@cd $(WORK_DIR) && $(VLOG) -modelsimini $(MODELSIM_INI) -sv -work work \
	  +incdir+$(UVM_SRC) +incdir+$(TB_SIM_DIR)/common +incdir+$(TB_UVM_DIR) +incdir+$(TB_UVM_DIR)/ifs \
	  $(UVM_SRC)/uvm_pkg.sv \
	  $(TB_UVM_DIR)/runctl_mgmt_env_pkg.sv \
	  $(TB_UVM_DIR)/tb_top.sv
	@touch $@

run_uvm_smoke: compile_uvm
	@echo "=== Running $(TEST) ==="
	@cd $(WORK_DIR) && $(VSIM) -modelsimini $(MODELSIM_INI) -c -work work -L altera_mf \
	  -dpicpppath $(DPI_CPP) -sv_lib $(QUESTA_UVM_DPI_LIB) \
	  -suppress 19 -suppress 3009 -suppress 3473 -voptargs=+acc \
	  +UVM_TESTNAME=$(TEST) \
	  $(TB_TOP) \
	  -do "quietly set NumericStdNoWarnings 1; quietly set StdArithNoWarnings 1; run -all; quit -f" \
	  | tee $(LOG_DIR)/$(TEST).log
	@if grep -qE '\*\* Fatal:|\*\* Error:' $(LOG_DIR)/$(TEST).log; then \
	  echo "FAIL: $(TEST)"; exit 1; \
	elif ! grep -q '\*\*\* TEST PASSED \*\*\*' $(LOG_DIR)/$(TEST).log; then \
	  echo "FAIL: $(TEST)"; exit 1; \
	else \
	  echo "PASS: $(TEST)"; \
	fi

run_uvm: run_uvm_smoke

$(GATE_NETLIST): $(IP_ROOT)/syn/quartus/output_files/runctl_mgmt_host_syn.fit.summary
	@echo "=== Exporting runctl_mgmt_host gate netlist ==="
	@cd $(IP_ROOT)/syn/quartus && quartus_eda runctl_mgmt_host_syn -c runctl_mgmt_host_syn \
	  --simulation --tool=modelsim --format=verilog --functional=off --output_directory=gate_sim

generate_gate_netlist: $(GATE_NETLIST)

compile_gate_uvm: $(GATE_WORK_DIR)/.compiled

$(GATE_WORK_DIR)/.compiled: \
  $(GATE_NETLIST) \
  $(TB_SIM_DIR)/common/runctl_mgmt_pkg.sv \
  $(TB_SIM_DIR)/runctl_mgmt_host_gate_dut_wrapper.sv \
  $(TB_UVM_DIR)/ifs/synclink_if.sv \
  $(TB_UVM_DIR)/ifs/runctl_if.sv \
  $(TB_UVM_DIR)/ifs/upload_if.sv \
  $(TB_UVM_DIR)/ifs/csr_if.sv \
  $(TB_UVM_DIR)/ifs/reset_if.sv \
  $(TB_UVM_DIR)/runctl_mgmt_env_pkg.sv \
  $(TB_UVM_DIR)/tb_top.sv
	@echo "=== Compiling runctl_mgmt_host gate smoke bench ==="
	@rm -rf $(GATE_WORK_DIR)
	@mkdir -p $(GATE_WORK_DIR) $(GATE_WORK_DIR)/verilog_libs $(LOG_DIR)
	@cd $(GATE_WORK_DIR) && $(VLIB) work
	@cp $(QSIM_INI) $(GATE_WORK_DIR)/$(MODELSIM_INI)
	@chmod u+w $(GATE_WORK_DIR)/$(MODELSIM_INI)
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini $(MODELSIM_INI) work work > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/altera_lnsim_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini altera_lnsim_ver verilog_libs/altera_lnsim_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work altera_lnsim_ver $(QUARTUS_HOME)/eda/sim_lib/altera_lnsim.sv
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/altera_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini altera_ver verilog_libs/altera_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work altera_ver $(QUARTUS_HOME)/eda/sim_lib/altera_primitives.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/lpm_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini lpm_ver verilog_libs/lpm_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work lpm_ver $(QUARTUS_HOME)/eda/sim_lib/220model.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/sgate_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini sgate_ver verilog_libs/sgate_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work sgate_ver $(QUARTUS_HOME)/eda/sim_lib/sgate.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/altera_mf_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini altera_mf_ver verilog_libs/altera_mf_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work altera_mf_ver $(QUARTUS_HOME)/eda/sim_lib/altera_mf.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/arriav_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini arriav_ver verilog_libs/arriav_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_ver $(QUARTUS_HOME)/eda/sim_lib/mentor/arriav_atoms_ncrypt.v
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_ver $(QUARTUS_HOME)/eda/sim_lib/mentor/arriav_hmi_atoms_ncrypt.v
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_ver $(QUARTUS_HOME)/eda/sim_lib/arriav_atoms.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/arriav_hssi_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini arriav_hssi_ver verilog_libs/arriav_hssi_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_hssi_ver $(QUARTUS_HOME)/eda/sim_lib/mentor/arriav_hssi_atoms_ncrypt.v
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_hssi_ver $(QUARTUS_HOME)/eda/sim_lib/arriav_hssi_atoms.v
	@cd $(GATE_WORK_DIR) && $(VLIB) verilog_libs/arriav_pcie_hip_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VMAP) -modelsimini modelsim.ini arriav_pcie_hip_ver verilog_libs/arriav_pcie_hip_ver > /dev/null
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_pcie_hip_ver $(QUARTUS_HOME)/eda/sim_lib/mentor/arriav_pcie_hip_atoms_ncrypt.v
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work arriav_pcie_hip_ver $(QUARTUS_HOME)/eda/sim_lib/arriav_pcie_hip_atoms.v
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_SIM_DIR)/common/runctl_mgmt_pkg.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_UVM_DIR)/ifs/synclink_if.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_UVM_DIR)/ifs/runctl_if.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_UVM_DIR)/ifs/upload_if.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_UVM_DIR)/ifs/csr_if.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_UVM_DIR)/ifs/reset_if.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -vlog01compat -work work $(GATE_NETLIST)
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work $(TB_SIM_DIR)/runctl_mgmt_host_gate_dut_wrapper.sv
	@cd $(GATE_WORK_DIR) && $(VLOG) -modelsimini modelsim.ini -sv -work work \
	  +incdir+$(UVM_SRC) +incdir+$(TB_SIM_DIR)/common +incdir+$(TB_UVM_DIR) +incdir+$(TB_UVM_DIR)/ifs \
	  $(UVM_SRC)/uvm_pkg.sv \
	  $(TB_UVM_DIR)/runctl_mgmt_env_pkg.sv \
	  $(TB_UVM_DIR)/tb_top.sv
	@touch $@

run_gate_uvm_smoke: compile_gate_uvm
	@echo "=== Running $(TEST) gate smoke ==="
	@cd $(GATE_WORK_DIR) && $(VSIM) -modelsimini modelsim.ini -c -work work \
	  -L altera_lnsim_ver -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver \
	  -L arriav_ver -L arriav_hssi_ver -L arriav_pcie_hip_ver \
	  -dpicpppath $(DPI_CPP) -sv_lib $(QUESTA_UVM_DPI_LIB) \
	  -suppress 19 -suppress 3009 -suppress 3473 -voptargs=+acc \
	  +UVM_TESTNAME=$(TEST) \
	  $(TB_TOP) \
	  -do "quietly set NumericStdNoWarnings 1; quietly set StdArithNoWarnings 1; run -all; quit -f" \
	  | tee $(LOG_DIR)/$(TEST)_gate.log
	@if grep -qE '\*\* Fatal:|\*\* Error:' $(LOG_DIR)/$(TEST)_gate.log; then \
	  echo "FAIL: $(TEST) gate smoke"; exit 1; \
	elif ! grep -q '\*\*\* TEST PASSED \*\*\*' $(LOG_DIR)/$(TEST)_gate.log; then \
	  echo "FAIL: $(TEST) gate smoke"; exit 1; \
	else \
	  echo "PASS: $(TEST) gate smoke"; \
	fi

clean:
	rm -rf $(WORK_DIR) $(GATE_WORK_DIR) $(LOG_DIR) transcript vsim.wlf

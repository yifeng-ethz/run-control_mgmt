################################################
# runctl_mgmt_host "Run-Control Management Host" 24.0.1125
# Yifeng Wang 
################################################

################################################
# request TCL package from ACDS 
################################################
package require qsys 


################################################
# module sc_hub
################################################
set_module_property DESCRIPTION "Converts slow-control packet into system bus (Avalon Memory-Mapped) transactions"
set_module_property NAME runctl_mgmt_host
set_module_property VERSION 24.0.1125
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property GROUP "Mu3e Control Plane/Modules"
set_module_property AUTHOR "Yifeng Wang"
set_module_property DISPLAY_NAME "Run-Control Management Host"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property ICON_PATH ../figures/mu3e_logo.png
set_module_property EDITABLE false
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false
#set_module_property ELABORATION_CALLBACK my_elaborate


################################################ 
# file sets
################################################
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL runctl_mgmt_host

add_fileset_file runctl_mgmt_host.vhd VHDL PATH runctl_mgmt_host.vhd 
add_fileset_file logging_fifo.vhd VHDL PATH ./altera_ip/logging_fifo.vhd


################################################
# parameters
################################################
add_parameter RUN_START_ACK_SYMBOL std_logic_vector "11111110"
set_parameter_property RUN_START_ACK_SYMBOL DISPLAY_NAME "Run start symbol"
set_parameter_property RUN_START_ACK_SYMBOL HDL_PARAMETER true
set_parameter_property RUN_START_ACK_SYMBOL WIDTH 8
set_parameter_property RUN_START_ACK_SYMBOL ALLOWED_RANGES {"11111110: K30.7" "11111101: K29.7"}
set dscpt \
"<html>
Select the run start ack packet lowest byte as the symbol to be recognized by run control listener.<br>
</html>"
set_parameter_property RUN_START_ACK_SYMBOL LONG_DESCRIPTION $dscpt
set_parameter_property RUN_START_ACK_SYMBOL DESCRIPTION $dscpt

add_parameter RUN_END_ACK_SYMBOL std_logic_vector "11111101"
set_parameter_property RUN_END_ACK_SYMBOL DISPLAY_NAME "Run end symbol"
set_parameter_property RUN_END_ACK_SYMBOL HDL_PARAMETER true
set_parameter_property RUN_END_ACK_SYMBOL WIDTH 8
set_parameter_property RUN_END_ACK_SYMBOL ALLOWED_RANGES {"11111110: K30.7" "11111101: K29.7"}
set dscpt \
"<html>
Select the run end ack packet lowest byte as the symbol to be recognized by run control listener.<br>
</html>"
set_parameter_property RUN_END_ACK_SYMBOL LONG_DESCRIPTION $dscpt
set_parameter_property RUN_END_ACK_SYMBOL DESCRIPTION $dscpt




add_parameter DEBUG NATURAL
set_parameter_property DEBUG DEFAULT_VALUE 1
set_parameter_property DEBUG DISPLAY_NAME "Debug level"
set_parameter_property DEBUG UNITS None
set_parameter_property DEBUG ALLOWED_RANGES {0 1 2}
set_parameter_property DEBUG HDL_PARAMETER true
set dscpt \
"<html>
Select the debug level of the IP (affects generation).<br>
<ul>
	<li><b>0</b> : off <br> </li>
	<li><b>1</b> : on, synthesizble <br> </li>
	<li><b>2</b> : on, non-synthesizble, simulation-only <br> </li>
</ul>
</html>"
set_parameter_property DEBUG LONG_DESCRIPTION $dscpt
set_parameter_property DEBUG DESCRIPTION $dscpt

################################################
# display items
################################################
add_display_item "" "IP Setting" GROUP ""
add_display_item "IP Setting" RUN_START_ACK_SYMBOL PARAMETER 
add_display_item "IP Setting" RUN_END_ACK_SYMBOL PARAMETER 
add_display_item "IP Setting" DEBUG PARAMETER 

add_display_item "" "Description" GROUP ""
set dscpt \
"<html>
Data flow: 
<ul>
    <li><b>ingress</b> : <b>synclink</b> the command from Mu3e central run control box. <br> </li>
    <li><b>egress</b> : <b>upload</b> the reply to Mu3e central run control box. <br> </li>
</ul>
<br>

Data (onboard management) flow: 
<ul>
    <li><b>egress</b> : <b>runctl</b> the run control streaming interface to all FPGA IP blocks. <br> </li>
</ul>
<br>

Control flow:
<ul>
    <li><b>non-timing critical</b> : <b>log</b> avalon-mm interface to read log fifo <br> </li>
</ul>
<br>

Clock Domain: <br>
<ul>
    <li> <b>mm</b> : memory-mapped slave</li>
    <li> <b>lvdspll</b> : 125 MHz master clock sync with the pll receiver links (also is the data path clock).</li>
</ul>
<br> 

How does it work? :<br>
<ol>
    <li>Receive the run control command on <b>synclink</b> </li>
    <li> Issue decoded run control command to qsys modules (which has runctl mgmt agent) and listens for their ack (ready signals)</li>
    <li>Ack the run control command through <b>upload</b> </li>
    
</ol>
<br> 

How to read back log fifo? :<br>
<ul>
    <li> Monitor through <b>log</b> interface </li>
    <li> User can read back the receive (received localled on <b>synclink</b>) and execution (ready asserted by all agents) timestamps of each run command.  </li>
    <li> the <b>log</b> interface connects to a fifo, you have to read 4 words for a complete log sentense.   </li>
</ul>   
<br> 
   
Log data structure is 4-tuple: <br>
<ul>
    <li> Word 0: received timestamp \[48:16\] </li>
    <li> Word 1: received timestamp \[15:0\] | empty \[7:0\] | run command \[7:0\] </li>
    <li> Word 2: payload_if \[31:0\] </li>
    <li> Word 3: execution timestamp \[31:0\] </li>
</ul>
<br> 

note: the timestamps are free-running across runs and only reset by lvdspll_reset
<br> 

</html>"
add_display_item "Description" "dscpt" TEXT $dscpt


################################################
# ports
################################################ 
############
# synclink #
############
add_interface synclink avalon_streaming end
set_interface_property synclink associatedClock "lvdspll_clock"
set_interface_property synclink associatedReset "lvdspll_reset"
set_interface_property synclink dataBitsPerSymbol 9

add_interface_port synclink asi_synclink_data data Input 9
add_interface_port synclink asi_synclink_error error Input 3

##########
# upload #
##########
add_interface upload avalon_streaming start
set_interface_property upload associatedClock "lvdspll_clock"
set_interface_property upload associatedReset "lvdspll_reset"
set_interface_property upload dataBitsPerSymbol 36

add_interface_port upload aso_upload_data data Output 36
add_interface_port upload aso_upload_valid valid Output 1
add_interface_port upload aso_upload_ready ready Input 1
add_interface_port upload aso_upload_startofpacket startofpacket Output 1
add_interface_port upload aso_upload_endofpacket endofpacket Output 1

##########
# runctl #
##########
add_interface runctl avalon_streaming start
set_interface_property runctl associatedClock "lvdspll_clock"
set_interface_property runctl associatedReset "lvdspll_reset"
set_interface_property runctl dataBitsPerSymbol 9

add_interface_port runctl aso_runctl_data data Output 9
add_interface_port runctl aso_runctl_valid valid Output 1
add_interface_port runctl aso_runctl_ready ready Input 1

#######
# log #
#######
add_interface log avalon end
set_interface_property log associatedClock "mm_clock"
set_interface_property log associatedReset "mm_reset"

add_interface_port log avs_log_read read Input 1
add_interface_port log avs_log_readdata readdata Output 32
add_interface_port log avs_log_write write Input 1
add_interface_port log avs_log_writedata writedata Input 32
add_interface_port log avs_log_waitrequest waitrequest Output 1

#############################
# Clock and reset interface #
#############################
######
# mm #
######
add_interface mm_clock clock end 
set_interface_property mm_clock clockRate 0
add_interface_port mm_clock mm_clk clk Input 1

add_interface mm_reset reset end
set_interface_property mm_reset associatedClock mm_clock
set_interface_property mm_reset synchronousEdges BOTH
add_interface_port mm_reset mm_reset reset Input 1

###########
# lvdspll #
###########
add_interface lvdspll_clock clock end 
set_interface_property lvdspll_clock clockRate 0
add_interface_port lvdspll_clock lvdspll_clk clk Input 1

add_interface lvdspll_reset reset end
set_interface_property lvdspll_reset associatedClock lvdspll_clock
set_interface_property lvdspll_reset synchronousEdges BOTH
add_interface_port lvdspll_reset lvdspll_reset reset Input 1


#####################
# hard reset source #
#####################
add_interface dp_hard_reset reset start
add_interface_port dp_hard_reset dp_hard_reset reset Output 1
set_interface_property dp_hard_reset synchronousEdges NONE

add_interface ct_hard_reset reset start
add_interface_port ct_hard_reset ct_hard_reset reset Output 1
set_interface_property ct_hard_reset synchronousEdges NONE















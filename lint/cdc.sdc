create_clock -name mm_clk -period 6.667 [get_ports {mm_clk}]
create_clock -name lvdspll_clk -period 8.000 [get_ports {lvdspll_clk}]

# The host intentionally bridges these domains through explicit
# handshake/gray-code CDC structures; they are not phase-related.
set_clock_groups -asynchronous \
  -group [get_clocks {mm_clk}] \
  -group [get_clocks {lvdspll_clk}]

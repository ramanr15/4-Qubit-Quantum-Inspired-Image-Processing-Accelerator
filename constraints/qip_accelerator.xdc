## =====================================================================
## qip_accelerator.xdc
## Vivado 2025.2
## Timing-only constraints for synthesis
## =====================================================================

## 100 MHz clock
create_clock -period 20.000 -name sys_clk [get_ports clk]

## Clock uncertainty
set_clock_uncertainty -setup 0.100 [get_clocks sys_clk]
set_clock_uncertainty -hold 0.050 [get_clocks sys_clk]

## Asynchronous reset
set_false_path -from [get_ports rst]

# pynq_z2.xdc - pin constraints for fpga_top on the PYNQ-Z2 board (xc7z020clg400-1)
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk_125]
create_clock -name clk_125 -period 8.000 [get_ports clk_125]

set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports btn_rst]   ;# BTN0
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports uart_tx]   ;# Pmod JA pin 1
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]  ;# LD0 done
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]  ;# LD1 pass
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]  ;# LD2 trap
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]  ;# LD3 heartbeat

# button and LEDs are asynchronous to the core clock (human-speed signals)
set_false_path -from [get_ports btn_rst]
set_false_path -to   [get_ports {led[*] uart_tx}]

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

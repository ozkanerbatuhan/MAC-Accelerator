# ================================================================================== #
# MAC-Accelerator - ZedBoard constraints for the NEORV32 PL top                       #
# Part: xc7z020clg484-1. Pins from the Avnet ZedBoard master XDC.                      #
# ================================================================================== #

# ---- 100 MHz onboard clock (GCLK) ------------------------------------------------- #
set_property -dict { PACKAGE_PIN Y9  IOSTANDARD LVCMOS33 } [get_ports { clk_i }]
create_clock -name sys_clk -period 10.000 [get_ports { clk_i }]

# ---- Reset button: BTNC (active-high; inverted to low-active rstn in the top) ------ #
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS25 } [get_ports { btn_rst_i }]

# ---- UART0 on PMOD JA (external 3V3 FTDI cable) ------------------------------------ #
#   FPGA TX (JA1) -> FTDI RX ; FPGA RX (JA2) <- FTDI TX ; common GND.                  #
set_property -dict { PACKAGE_PIN Y11  IOSTANDARD LVCMOS33 } [get_ports { uart0_txd_o }] ;# JA1
set_property -dict { PACKAGE_PIN AA11 IOSTANDARD LVCMOS33 } [get_ports { uart0_rxd_i }] ;# JA2

# ---- LEDs LD0..LD7 (liveness) ----------------------------------------------------- #
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[0] }]
set_property -dict { PACKAGE_PIN T21 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[1] }]
set_property -dict { PACKAGE_PIN U22 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[2] }]
set_property -dict { PACKAGE_PIN U21 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[3] }]
set_property -dict { PACKAGE_PIN V22 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[4] }]
set_property -dict { PACKAGE_PIN W22 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[5] }]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[6] }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { gpio_o[7] }]

# ---- Timing exception: UART RX is asynchronous to sys_clk -------------------------- #
set_false_path -from [get_ports { uart0_rxd_i }]
set_false_path -from [get_ports { btn_rst_i }]
set_false_path -to   [get_ports { uart0_txd_o }]
set_false_path -to   [get_ports { gpio_o[*] }]

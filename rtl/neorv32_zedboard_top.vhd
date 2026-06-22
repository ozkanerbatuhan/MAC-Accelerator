-- ================================================================================ --
-- MAC-Accelerator - NEORV32 top-level for the Avnet ZedBoard (Zynq-7020 PL)          --
-- -------------------------------------------------------------------------------- --
-- Instantiates the NEORV32 processor in the FPGA fabric with the custom MAC          --
-- instruction enabled (RISCV_ISA_Xcfu => true). The CFU is the project's override     --
-- rtl/neorv32_cpu_alu_cfu.vhd (MAC), not the upstream XTEA example.                   --
--                                                                                    --
-- Boot mode: internal UART bootloader (BOOT_MODE_SELECT = 0). On power-up the         --
-- bootloader prints its banner over UART0 -> proves core + clock + UART in the PL     --
-- (Phase 1 gate). Application executables are then uploaded over UART, or the boot     --
-- mode can later be switched to boot directly from an initialized IMEM image.          --
--                                                                                    --
-- Board wiring (see constraints/zedboard_mac.xdc):                                    --
--   clk_i      <- 100 MHz onboard oscillator (GCLK, pin Y9)                           --
--   btn_rst_i  <- BTNC push-button (active-high; inverted here to low-active rstn)     --
--   uart0_txd  -> PMOD JA1 ; uart0_rxd <- PMOD JA2  (external 3V3 FTDI cable)          --
--   gpio_o     -> LD0..LD7 (liveness)                                                 --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_zedboard_top is
  generic (
    CLOCK_FREQUENCY : natural := 100000000; -- 100 MHz PL clock
    IMEM_SIZE       : natural := 16*1024;
    DMEM_SIZE       : natural := 8*1024
  );
  port (
    clk_i       : in  std_ulogic;                    -- 100 MHz GCLK
    btn_rst_i   : in  std_ulogic;                    -- active-high reset button (BTNC)
    uart0_txd_o : out std_ulogic;                    -- UART0 TX -> FTDI RX
    uart0_rxd_i : in  std_ulogic;                    -- UART0 RX <- FTDI TX
    gpio_o      : out std_ulogic_vector(7 downto 0)  -- LEDs LD0..7
  );
end entity;

architecture rtl of neorv32_zedboard_top is
  signal rstn         : std_ulogic;
  signal con_gpio_out : std_ulogic_vector(31 downto 0);
begin

  -- active-high button -> low-active async reset for the core --
  rstn <= not btn_rst_i;

  neorv32_top_inst: neorv32_top
  generic map (
    -- Clocking --
    CLOCK_FREQUENCY  => CLOCK_FREQUENCY,
    -- Boot configuration --
    BOOT_MODE_SELECT => 0,        -- 0 = internal UART bootloader
    -- RISC-V CPU extensions --
    RISCV_ISA_C      => true,     -- compressed
    RISCV_ISA_M      => true,     -- mul/div (needed for the pure-SW MAC baseline)
    RISCV_ISA_Zicntr => true,     -- base counters (cycle CSR for the speedup metric)
    RISCV_ISA_Xcfu   => true,     -- *** enable the custom MAC instruction (CFU) ***
    -- Internal instruction memory --
    IMEM_EN          => true,
    IMEM_SIZE        => IMEM_SIZE,
    -- Internal data memory --
    DMEM_EN          => true,
    DMEM_SIZE        => DMEM_SIZE,
    -- Peripherals --
    IO_GPIO_NUM      => 8,
    IO_CLINT_EN      => true,
    IO_UART0_EN      => true
  )
  port map (
    clk_i       => clk_i,
    rstn_i      => rstn,
    gpio_o      => con_gpio_out,
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i
  );

  gpio_o <= con_gpio_out(7 downto 0);

end architecture;

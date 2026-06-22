-- ================================================================================ --
-- MAC-Accelerator - Multiply-Accumulate Datapath (custom-instruction execute unit)  --
-- -------------------------------------------------------------------------------- --
-- Single signed 16x16 multiply-accumulate functional unit, reshaped from the prior  --
-- HFT MLP accelerator's DSP-optimized MAC primitive (in_reg * w_reg, Q8.8). The AXI/ --
-- DMA/BRAM framing and the 64-wide reduction tree are stripped; only the core        --
-- multiplier + accumulator remain, now driven by register operands from the CPU      --
-- pipeline (NEORV32 CFU).                                                             --
--                                                                                    --
-- Number format : Q8.8 signed fixed-point operands (16-bit).                         --
--   product  = a * b  -> Q16.16 (32-bit)                                             --
--   acc     += product -> 48-bit signed accumulator (DSP48E1 P-register width)        --
--                                                                                    --
-- Cycle model : SINGLE-CYCLE. The multiply+add is combinational; the accumulator is  --
-- registered. 'result_o' is the COMBINATIONAL next accumulator value so the CFU can   --
-- return it to rd in the same cycle (valid_o = start). If timing does not close, this --
-- unit is the place to insert the DSP MREG/PREG pipeline stages (multi-cycle mode).   --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor extension - MAC custom instruction                    --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_datapath is
  generic (
    OP_WIDTH  : natural := 16; -- operand width (Q8.8 -> 16)
    ACC_WIDTH : natural := 48  -- accumulator width (DSP48E1 P-register)
  );
  port (
    clk_i    : in  std_ulogic;                              -- clock, rising edge
    rstn_i   : in  std_ulogic;                              -- async reset, low-active
    en_i     : in  std_ulogic;                              -- accumulate enable: acc += a*b
    clr_i    : in  std_ulogic;                              -- clear accumulator (overrides en)
    a_i      : in  std_ulogic_vector(OP_WIDTH-1 downto 0);  -- operand a (Q8.8 signed)
    b_i      : in  std_ulogic_vector(OP_WIDTH-1 downto 0);  -- operand b (Q8.8 signed)
    result_o : out std_ulogic_vector(ACC_WIDTH-1 downto 0)  -- combinational next-accumulator value
  );
end entity;

architecture rtl of mac_datapath is

  signal acc      : signed(ACC_WIDTH-1 downto 0);                 -- registered accumulator
  signal product  : signed(2*OP_WIDTH-1 downto 0);                -- a*b (Q16.16)
  signal acc_next : signed(ACC_WIDTH-1 downto 0);                 -- combinational acc update

begin

  -- Combinational multiply (DSP48E1 inferred from "signed * signed", as in mlp_engine) --
  product <= signed(a_i) * signed(b_i);

  -- Combinational accumulator update --
  acc_next <= acc + resize(product, ACC_WIDTH) when (en_i = '1') else acc;

  -- Result exposed to the CFU: cleared value on clr, else the next accumulator value.  --
  -- With en='0' and clr='0' this equals the current accumulator (used by read ops).    --
  result_o <= (others => '0') when (clr_i = '1') else std_ulogic_vector(acc_next);

  -- Registered accumulator --
  acc_reg: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      acc <= (others => '0');
    elsif rising_edge(clk_i) then
      if (clr_i = '1') then
        acc <= (others => '0');
      elsif (en_i = '1') then
        acc <= acc_next;
      end if;
    end if;
  end process;

end architecture;

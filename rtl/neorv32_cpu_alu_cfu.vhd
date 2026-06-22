-- ================================================================================ --
-- NEORV32 CPU - ALU Custom Functions Unit (CFU) - MAC custom instruction             --
-- -------------------------------------------------------------------------------- --
-- PROJECT OVERRIDE of rtl/core/neorv32_cpu_alu_cfu.vhd. Same entity name, same ports, --
-- compiled into library 'neorv32'. The upstream XTEA example is replaced by a         --
-- tightly-coupled multiply-accumulate (MAC) functional unit wrapping mac_datapath.    --
--                                                                                    --
-- Custom instruction set (RISC-V CUSTOM-0 opcode, R-type, funct3-selected):           --
--   funct3=000  mac      : acc += signed(rs1[15:0]) * signed(rs2[15:0]); rd = acc[31:0]--
--   funct3=001  mac.rdlo : rd = acc[31:0]            (accumulator unchanged)           --
--   funct3=010  mac.rdhi : rd = sign_ext(acc[47:32]) (accumulator unchanged)           --
--   funct3=011  mac.clr  : acc <= 0; rd = 0                                            --
--   others                : illegal instruction (valid_o = '0')                        --
--                                                                                    --
-- Operands are Q8.8 signed fixed-point in the low 16 bits of rs1/rs2. The product is   --
-- Q16.16; the 48-bit accumulator holds the raw running sum. Single-cycle: valid_o is   --
-- asserted in the same cycle as start (combinational result). The accumulator update   --
-- is gated by the single-shot 'start' so each instruction accumulates exactly once.    --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32                --
-- Copyright (c) NEORV32 contributors. BSD-3-Clause.                                   --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu_alu_cfu is
  port (
    -- global control --
    clk_i    : in  std_ulogic; -- global clock, rising edge
    rstn_i   : in  std_ulogic; -- global reset, low-active, async
    -- request --
    start_i  : in  std_ulogic; -- start trigger, single-shot
    inst_i   : in  std_ulogic_vector(31 downto 0); -- full instruction word
    rs1_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 1
    rs2_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 2
    -- response --
    result_o : out std_ulogic_vector(31 downto 0); -- operation result
    valid_o  : out std_ulogic                      -- operation done; result valid
  );
end neorv32_cpu_alu_cfu;

architecture neorv32_cpu_alu_cfu_rtl of neorv32_cpu_alu_cfu is

  -- supported CFU opcodes --
  constant opcode_custom0_c : std_ulogic_vector(6 downto 0) := "0001011"; -- CUSTOM-0 opcode

  -- MAC operand / accumulator widths --
  constant OP_WIDTH_c  : natural := 16; -- Q8.8 operands
  constant ACC_WIDTH_c : natural := 48; -- accumulator (DSP48E1 P-register)

  -- function identifiers (funct3 bit-field) --
  constant mac_acc_c   : std_ulogic_vector(2 downto 0) := "000"; -- acc += a*b
  constant mac_rdlo_c  : std_ulogic_vector(2 downto 0) := "001"; -- read acc[31:0]
  constant mac_rdhi_c  : std_ulogic_vector(2 downto 0) := "010"; -- read acc[47:32]
  constant mac_clr_c   : std_ulogic_vector(2 downto 0) := "011"; -- clear acc

  -- instruction decode --
  signal is_custom0 : std_ulogic;
  signal start      : std_ulogic; -- valid CFU instruction trigger (single-shot)
  signal funct3     : std_ulogic_vector(2 downto 0);

  -- datapath control --
  signal mac_en  : std_ulogic;
  signal mac_clr : std_ulogic;
  signal mac_res : std_ulogic_vector(ACC_WIDTH_c-1 downto 0); -- combinational acc / acc_next

begin

  -- Instruction Decode ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  is_custom0 <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) else '0';
  start      <= start_i and is_custom0; -- only trigger on our opcode
  funct3     <= inst_i(14 downto 12);

  -- Datapath control: accumulate / clear gated by single-shot start ------------------------
  -- -------------------------------------------------------------------------------------------
  mac_en  <= '1' when (start = '1' and funct3 = mac_acc_c) else '0';
  mac_clr <= '1' when (start = '1' and funct3 = mac_clr_c) else '0';

  -- MAC Datapath (reused HFT DSP-optimized multiply-accumulate primitive) ------------------
  -- -------------------------------------------------------------------------------------------
  mac_inst: entity neorv32.mac_datapath
  generic map (
    OP_WIDTH  => OP_WIDTH_c,
    ACC_WIDTH => ACC_WIDTH_c
  )
  port map (
    clk_i    => clk_i,
    rstn_i   => rstn_i,
    en_i     => mac_en,
    clr_i    => mac_clr,
    a_i      => rs1_i(OP_WIDTH_c-1 downto 0),
    b_i      => rs2_i(OP_WIDTH_c-1 downto 0),
    result_o => mac_res
  );

  -- Function Result Select -----------------------------------------------------------------
  -- Single-cycle: combinational result, valid in the same cycle as start.                   --
  -- -------------------------------------------------------------------------------------------
  result_select: process(funct3, mac_res)
  begin
    case funct3 is
      when mac_acc_c | mac_rdlo_c => -- accumulate (returns new acc low) / read low word
        result_o <= mac_res(31 downto 0);
        valid_o  <= '1';
      when mac_rdhi_c => -- read high word, sign-extended
        result_o <= std_ulogic_vector(resize(signed(mac_res(ACC_WIDTH_c-1 downto 32)), 32));
        valid_o  <= '1';
      when mac_clr_c => -- clear accumulator
        result_o <= (others => '0');
        valid_o  <= '1';
      when others => -- unimplemented -> illegal instruction
        result_o <= (others => '0');
        valid_o  <= '0';
    end case;
  end process result_select;

end neorv32_cpu_alu_cfu_rtl;

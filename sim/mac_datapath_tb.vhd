-- ================================================================================ --
-- MAC-Accelerator - Testbench for mac_datapath (self-checking golden model)         --
-- -------------------------------------------------------------------------------- --
-- Methodology adapted from the prior HFT mlp_tb: cycle-level stimulus plus a         --
-- software-computed golden accumulator for math-correctness checking. Unlike the     --
-- HFT TB (visual-only), this one self-checks via asserts and reports PASS/FAIL.       --
-- -------------------------------------------------------------------------------- --
-- Run (Vivado xsim):                                                                 --
--   xvhdl --2008 -work neorv32 rtl/mac_datapath.vhd                                   --
--   xvhdl --2008 sim/mac_datapath_tb.vhd                                              --
--   xelab -debug typical mac_datapath_tb -L neorv32 -s sim                            --
--   xsim sim -runall                                                                  --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;

entity mac_datapath_tb is
end entity;

architecture sim of mac_datapath_tb is

  constant OP_WIDTH  : natural := 16;
  constant ACC_WIDTH : natural := 48;
  constant CLK_PERIOD : time := 10 ns; -- 100 MHz

  signal clk    : std_ulogic := '0';
  signal rstn   : std_ulogic := '0';
  signal en     : std_ulogic := '0';
  signal clr    : std_ulogic := '0';
  signal a      : std_ulogic_vector(OP_WIDTH-1 downto 0)  := (others => '0');
  signal b      : std_ulogic_vector(OP_WIDTH-1 downto 0)  := (others => '0');
  signal result : std_ulogic_vector(ACC_WIDTH-1 downto 0);

  signal sim_done : boolean := false;

  -- test vectors (Q8.8): integer-valued for easy reasoning. 1.0 = 256.
  type vec_t is array (natural range <>) of integer;
  constant VA : vec_t := ( 256,  512, -256,  128,  1024, -512,   64,  256);
  constant VB : vec_t := ( 256,  256,  512, -256,   128,  256, 1024, -512);

begin

  -- clock
  clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

  -- DUT
  dut: entity neorv32.mac_datapath
    generic map (OP_WIDTH => OP_WIDTH, ACC_WIDTH => ACC_WIDTH)
    port map (
      clk_i => clk, rstn_i => rstn, en_i => en, clr_i => clr,
      a_i => a, b_i => b, result_o => result
    );

  stim: process
    variable golden    : integer := 0; -- software reference accumulator (Q16.16 raw int)
    variable prod      : integer;
    variable errors    : integer := 0;
  begin
    -- reset
    rstn <= '0';
    wait for CLK_PERIOD * 3;
    rstn <= '1';
    wait until rising_edge(clk);

    -- clear accumulator
    clr <= '1'; en <= '0';
    wait until rising_edge(clk);
    clr <= '0';
    golden := 0;

    -- run MAC sequence: acc += a*b each cycle
    for i in VA'range loop
      a  <= std_ulogic_vector(to_signed(VA(i), OP_WIDTH));
      b  <= std_ulogic_vector(to_signed(VB(i), OP_WIDTH));
      en <= '1';
      -- combinational result this cycle should equal golden + a*b
      wait for 1 ns; -- let combinational settle
      prod   := VA(i) * VB(i);
      golden := golden + prod;
      assert to_integer(signed(result)) = golden
        report "MAC mismatch at i=" & integer'image(i) &
               " got=" & integer'image(to_integer(signed(result))) &
               " exp=" & integer'image(golden)
        severity error;
      if to_integer(signed(result)) /= golden then
        errors := errors + 1;
      end if;
      wait until rising_edge(clk); -- accumulator latches acc_next
    end loop;
    en <= '0';

    -- read-back: with en=0, clr=0, result should hold the accumulator
    wait for 1 ns;
    assert to_integer(signed(result)) = golden
      report "Read-back mismatch got=" & integer'image(to_integer(signed(result))) &
             " exp=" & integer'image(golden) severity error;
    if to_integer(signed(result)) /= golden then
      errors := errors + 1;
    end if;

    -- clear again -> result and acc back to 0
    clr <= '1';
    wait for 1 ns;
    assert to_integer(signed(result)) = 0 report "Clear did not zero result" severity error;
    wait until rising_edge(clk);
    clr <= '0';
    wait for 1 ns;
    assert to_integer(signed(result)) = 0 report "Accumulator not zero after clear" severity error;

    -- summary
    if errors = 0 then
      report "==== mac_datapath_tb PASSED ====" severity note;
    else
      report "==== mac_datapath_tb FAILED: " & integer'image(errors) & " errors ====" severity failure;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture;

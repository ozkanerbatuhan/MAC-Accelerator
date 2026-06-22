-- ================================================================================ --
-- MAC-Accelerator - Testbench for the MAC CFU (neorv32_cpu_alu_cfu override)         --
-- -------------------------------------------------------------------------------- --
-- Drives the CFU request interface (start_i/inst_i/rs1_i/rs2_i) with hand-assembled  --
-- CUSTOM-0 R-type instruction words and checks result_o/valid_o for every operation: --
-- mac, mac.rdlo, mac.rdhi, mac.clr, and an illegal funct3 (valid_o must be '0').      --
--                                                                                    --
-- Compile order (Vivado xsim), all core files into library 'neorv32':                --
--   xvhdl --2008 -work neorv32 <neorv32>/rtl/core/neorv32_package.vhd                 --
--   xvhdl --2008 -work neorv32 rtl/mac_datapath.vhd rtl/neorv32_cpu_alu_cfu.vhd       --
--   xvhdl --2008 sim/mac_cfu_tb.vhd                                                   --
--   xelab -debug typical mac_cfu_tb -L neorv32 -s sim                                 --
--   xsim sim -runall                                                                  --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;

entity mac_cfu_tb is
end entity;

architecture sim of mac_cfu_tb is

  constant CLK_PERIOD : time := 10 ns;

  signal clk    : std_ulogic := '0';
  signal rstn   : std_ulogic := '0';
  signal start  : std_ulogic := '0';
  signal inst   : std_ulogic_vector(31 downto 0) := (others => '0');
  signal rs1    : std_ulogic_vector(31 downto 0) := (others => '0');
  signal rs2    : std_ulogic_vector(31 downto 0) := (others => '0');
  signal result : std_ulogic_vector(31 downto 0);
  signal valid  : std_ulogic;

  signal sim_done : boolean := false;

  constant OPCODE_CUSTOM0 : std_ulogic_vector(6 downto 0) := "0001011";
  constant F_MAC   : std_ulogic_vector(2 downto 0) := "000";
  constant F_RDLO  : std_ulogic_vector(2 downto 0) := "001";
  constant F_RDHI  : std_ulogic_vector(2 downto 0) := "010";
  constant F_CLR   : std_ulogic_vector(2 downto 0) := "011";
  constant F_BAD   : std_ulogic_vector(2 downto 0) := "111";

  -- build a CUSTOM-0 R-type instruction word with the given funct3 (rs/rd fields unused) --
  function make_inst(funct3 : std_ulogic_vector(2 downto 0)) return std_ulogic_vector is
    variable w : std_ulogic_vector(31 downto 0) := (others => '0');
  begin
    w(6 downto 0)   := OPCODE_CUSTOM0;
    w(14 downto 12) := funct3;
    return w;
  end function;

begin

  clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';

  dut: entity neorv32.neorv32_cpu_alu_cfu
    port map (
      clk_i => clk, rstn_i => rstn, start_i => start, inst_i => inst,
      rs1_i => rs1, rs2_i => rs2, result_o => result, valid_o => valid
    );

  stim: process
    variable golden : integer := 0;
    variable errors : integer := 0;

    -- issue one single-cycle CFU op: pulse start for one clock with given operands
    procedure do_op(funct3 : std_ulogic_vector(2 downto 0); va, vb : integer) is
    begin
      inst  <= make_inst(funct3);
      rs1   <= std_ulogic_vector(to_signed(va, 32));
      rs2   <= std_ulogic_vector(to_signed(vb, 32));
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
    end procedure;
  begin
    rstn <= '0';
    wait for CLK_PERIOD * 3;
    rstn <= '1';
    wait until rising_edge(clk);

    -- clear accumulator
    do_op(F_CLR, 0, 0);
    golden := 0;

    -- accumulate sequence (Q8.8 integers): acc += a*b
    do_op(F_MAC, 256, 256); golden := golden + 256*256;   -- 1.0 * 1.0
    do_op(F_MAC, 512, 256); golden := golden + 512*256;   -- 2.0 * 1.0
    do_op(F_MAC, -256, 512); golden := golden + (-256)*512; -- -1.0 * 2.0

    -- read low word (en=0, must hold accumulator)
    inst <= make_inst(F_RDLO);
    start <= '1';
    wait for 1 ns;
    assert to_integer(signed(result)) = golden
      report "RDLO mismatch got=" & integer'image(to_integer(signed(result))) &
             " exp=" & integer'image(golden) severity error;
    if to_integer(signed(result)) /= golden then errors := errors + 1; end if;
    assert valid = '1' report "RDLO valid not asserted" severity error;
    wait until rising_edge(clk);
    start <= '0';

    -- read high word (sign-extended acc[47:32]); golden here is small so high word = 0
    inst <= make_inst(F_RDHI);
    start <= '1';
    wait for 1 ns;
    assert to_integer(signed(result)) = 0
      report "RDHI mismatch got=" & integer'image(to_integer(signed(result))) severity error;
    if to_integer(signed(result)) /= 0 then errors := errors + 1; end if;
    wait until rising_edge(clk);
    start <= '0';

    -- illegal funct3 -> valid must be '0' (would trigger illegal-instruction trap in core)
    inst <= make_inst(F_BAD);
    start <= '1';
    wait for 1 ns;
    assert valid = '0' report "Illegal funct3 should give valid='0'" severity error;
    if valid /= '0' then errors := errors + 1; end if;
    wait until rising_edge(clk);
    start <= '0';

    -- clear and confirm zero
    do_op(F_CLR, 0, 0);
    inst <= make_inst(F_RDLO);
    start <= '1';
    wait for 1 ns;
    assert to_integer(signed(result)) = 0 report "Accumulator not zero after clear" severity error;
    if to_integer(signed(result)) /= 0 then errors := errors + 1; end if;
    wait until rising_edge(clk);
    start <= '0';

    if errors = 0 then
      report "==== mac_cfu_tb PASSED ====" severity note;
    else
      report "==== mac_cfu_tb FAILED: " & integer'image(errors) & " errors ====" severity failure;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture;

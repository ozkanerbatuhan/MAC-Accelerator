# MAC-Accelerator — NEORV32 Tightly-Coupled MAC Custom Instruction

RISC-V soft-core (NEORV32, 100% VHDL) in the Zynq-7020 PL with a custom `mac`
(multiply-accumulate) instruction tightly coupled into the execute stage via the
NEORV32 **CFU** (Custom Functions Unit). Operands come from the register file
(rs1/rs2) — not AXI/DMA. Goal: measure cycle-count speedup of a Q8.8 dot-product,
pure-software MAC vs the custom instruction.

See `.claude/CLAUDE.md` for the full design rationale and the plan in
`~/.claude/plans/proje-brief-risc-v-mellow-creek.md`.

## Layout
```
rtl/  neorv32_zedboard_top.vhd   top wrapping neorv32_top, RISCV_ISA_Xcfu => true
      mac_datapath.vhd           signed 16x16 Q8.8 MAC, 48-bit acc (reused HFT primitive)
      neorv32_cpu_alu_cfu.vhd    OVERRIDE of the upstream CFU (XTEA -> MAC)
sim/  mac_datapath_tb.vhd        self-checking datapath TB (golden model)
      mac_cfu_tb.vhd             self-checking CFU TB (mac/rdlo/rdhi/clr/illegal)
constraints/ zedboard_mac.xdc    ZedBoard pins (clk Y9, BTNC reset, UART on PMOD JA, LEDs)
scripts/ add_sources.tcl         populate the Vivado project (run first)
         run_sim.tcl             run a TB in xsim
         build_bitstream.tcl     synth+impl+bitstream + timing/utilization reports
sw/mac_demo/ main.c, makefile    bare-metal SW-vs-HW MAC benchmark
```
The NEORV32 core is a **sibling clone** at `D:/vivado projects/neorv32`
(`git clone https://github.com/stnolting/neorv32`). Not vendored into this repo.

## Custom instruction (CUSTOM-0 opcode, R-type, funct3-selected)
| mnemonic   | funct3 | semantics |
|------------|--------|-----------|
| `mac`      | 000    | acc += signed(rs1[15:0]) * signed(rs2[15:0]); rd = acc[31:0] |
| `mac.rdlo` | 001    | rd = acc[31:0] |
| `mac.rdhi` | 010    | rd = sign_ext(acc[47:32]) |
| `mac.clr`  | 011    | acc <= 0; rd = 0 |

Operands are Q8.8 (16-bit signed) in the low half of rs1/rs2. Product is Q16.16;
the 48-bit accumulator holds the raw running sum. Single-cycle (`valid_o = start`);
falls back to multi-cycle if timing fails (insert DSP MREG/PREG in `mac_datapath`).

## Prerequisites
- **Vivado 2025.2** (project targets `xc7z020clg484-1`).
- **RISC-V GCC**: `riscv-none-elf-gcc` (xPack) + `make` on PATH — **required for the
  software (sw/mac_demo); not yet installed in this environment.** Install:
  xPack `riscv-none-elf-gcc` from <https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases>
  and GNU make.

## Build & verify (phased gates)

### Sim gates (no board, no RISC-V toolchain needed — only Vivado)
```
vivado -mode batch -source scripts/add_sources.tcl
vivado -mode batch -source scripts/run_sim.tcl -tclargs mac_datapath_tb
vivado -mode batch -source scripts/run_sim.tcl -tclargs mac_cfu_tb
```
Expect `==== mac_datapath_tb PASSED ====` and `==== mac_cfu_tb PASSED ====`.

### Bitstream + timing/resources (Phase 1 & 6 gate)
```
vivado -mode batch -source scripts/build_bitstream.tcl
```
Reads back WNS (timing closure) and writes `reports/timing_summary.rpt` /
`reports/utilization.rpt` (DSP/LUT/FF). If `TIMING: FAILED`, switch the MAC to
multi-cycle (pipeline `mac_datapath`, drive `valid_o` from a done shift register).

### Software (Phase 0/4/5 — needs riscv-none-elf-gcc)
```
cd sw/mac_demo
make clean_all exe        # -> neorv32_exe.bin (upload via UART bootloader)
```
Program the bitstream, connect a 3V3 FTDI cable to PMOD JA (FPGA TX=JA1→FTDI RX,
FPGA RX=JA2←FTDI TX, GND), open a terminal at **19200-8N1**. The NEORV32
bootloader banner appearing = Phase 1 gate. Upload `neorv32_exe.bin`; the demo
prints SW vs HW results (must match) and cycle counts + speedup.

## Status
- [x] HDL: top, MAC datapath, CFU override, two self-checking TBs.
- [x] Constraints, build/sim TCL, SW benchmark.
- [ ] Run sim gates in Vivado (no simulator in the authoring environment).
- [ ] Synthesis/timing/bitstream; UART bring-up on hardware.
- [ ] Install RISC-V toolchain; build + run sw/mac_demo; record speedup.

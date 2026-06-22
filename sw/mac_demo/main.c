// ================================================================================ //
// MAC-Accelerator - bare-metal demo: pure-SW MAC vs custom-instruction MAC           //
// -------------------------------------------------------------------------------- //
// Computes a dot-product of two Q8.8 fixed-point vectors two ways and compares both  //
// the numeric result (correctness) and the cycle count (speedup):                    //
//   1. dotprod_sw : pure C, hardware 'mul' (RISC-V M extension), int64 accumulate.    //
//   2. dotprod_hw : the custom 'mac' instruction (CFU), 48-bit hardware accumulator.  //
//                                                                                    //
// Custom instruction encoding (CUSTOM-0 opcode, R-type, funct3-selected) - must match //
// rtl/neorv32_cpu_alu_cfu.vhd:                                                        //
//   mac_acc(a,b) funct3=000 : acc += signed(a[15:0]) * signed(b[15:0]); ret acc[31:0] //
//   mac_rdlo()   funct3=001 : ret acc[31:0]                                           //
//   mac_rdhi()   funct3=010 : ret sign_ext(acc[47:32])                                //
//   mac_clr()    funct3=011 : acc <= 0                                                //
//                                                                                    //
// Requires UART0, the Xcfu ISA extension, and Zicntr (cycle CSR).                     //
// ================================================================================ //

#include <neorv32.h>

#define BAUD_RATE 19200
#define N         64   /* dot-product length */

/* ---- custom MAC instruction intrinsics (see neorv32_intrinsics.h templates) ----- */
#define mac_acc(a, b) RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b000, 0b0000000, (a), (b))
#define mac_rdlo()    RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b001, 0b0000000, 0, 0)
#define mac_rdhi()    RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b010, 0b0000000, 0, 0)
#define mac_clr()     RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b011, 0b0000000, 0, 0)

/* Q8.8 input vectors */
int16_t vec_a[N];
int16_t vec_b[N];

/* ---- pure-software dot product: int64 accumulate of Q16.16 products -------------- */
int64_t dotprod_sw(const int16_t *a, const int16_t *b, int n) {
  int64_t acc = 0;
  for (int i = 0; i < n; i++) {
    acc += (int64_t)((int32_t)a[i] * (int32_t)b[i]); /* hardware 'mul' (M ext) */
  }
  return acc;
}

/* ---- custom-instruction dot product: hardware MAC, 48-bit accumulator ------------ */
int64_t dotprod_hw(const int16_t *a, const int16_t *b, int n) {
  mac_clr();
  for (int i = 0; i < n; i++) {
    mac_acc((uint32_t)(int32_t)a[i], (uint32_t)(int32_t)b[i]);
  }
  uint32_t lo = mac_rdlo();
  int32_t  hi = (int32_t)mac_rdhi(); /* sign-extended acc[47:32] */
  return ((int64_t)hi << 32) | (uint64_t)lo;
}

int main(void) {

  neorv32_rte_setup();
  if (neorv32_uart0_available() == 0) { return -1; }
  neorv32_uart0_setup(BAUD_RATE, 0);

  /* feature checks */
  if ((neorv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_XCFU)) == 0) {
    neorv32_uart0_printf("ERROR! CFU ('Xcfu') not implemented!\n");
    return -1;
  }
  if ((neorv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_ZICNTR)) == 0) {
    neorv32_uart0_printf("ERROR! Base counters ('Zicntr') not implemented!\n");
    return -1;
  }

  neorv32_uart0_printf("\n<<< MAC custom-instruction demo (Q8.8 dot-product, N=%u) >>>\n\n", N);

  /* generate test vectors: a = i (Q8.8), b = (i*3 - 96) (Q8.8) -> signed mix */
  for (int i = 0; i < N; i++) {
    vec_a[i] = (int16_t)((i + 1) << 4);          /* small Q8.8 values */
    vec_b[i] = (int16_t)(((i * 3) - 96) << 4);   /* spans negative + positive */
  }

  /* ---- software dot product (timed) ---- */
  neorv32_cpu_csr_write(CSR_MCYCLE, 0);
  int64_t res_sw = dotprod_sw(vec_a, vec_b, N);
  uint32_t cyc_sw = neorv32_cpu_csr_read(CSR_MCYCLE);

  /* ---- hardware (custom instruction) dot product (timed) ---- */
  neorv32_cpu_csr_write(CSR_MCYCLE, 0);
  int64_t res_hw = dotprod_hw(vec_a, vec_b, N);
  uint32_t cyc_hw = neorv32_cpu_csr_read(CSR_MCYCLE);

  /* ---- correctness cross-check ---- */
  neorv32_uart0_printf("SW result (raw Q16.16) = %d (hi=0x%x lo=0x%x)\n",
                       (int32_t)res_sw, (uint32_t)(res_sw >> 32), (uint32_t)res_sw);
  neorv32_uart0_printf("HW result (raw Q16.16) = %d (hi=0x%x lo=0x%x)\n",
                       (int32_t)res_hw, (uint32_t)(res_hw >> 32), (uint32_t)res_hw);
  if (res_sw == res_hw) {
    neorv32_uart0_printf("CORRECTNESS: OK (results match)\n");
  } else {
    neorv32_uart0_printf("CORRECTNESS: FAILED (mismatch)\n");
  }
  /* Q8.8 result = raw >> 8 */
  neorv32_uart0_printf("Dot-product (Q8.8 integer part) = %d\n\n", (int32_t)(res_hw >> (8 + 8)));

  /* ---- speedup ---- */
  neorv32_uart0_printf("SW MAC : %u cycles\n", cyc_sw);
  neorv32_uart0_printf("HW MAC : %u cycles\n", cyc_hw);
  if (cyc_hw > 0) {
    neorv32_uart0_printf("Speedup: %u.%02ux\n",
                         cyc_sw / cyc_hw,
                         ((cyc_sw * 100) / cyc_hw) % 100);
  }

  neorv32_uart0_printf("\nMAC demo completed.\n");
  return 0;
}

// ================================================================================ //
// MAC-Accelerator - bare-metal benchmark: pure-SW MAC vs custom-instruction MAC       //
// -------------------------------------------------------------------------------- //
// Sweeps the dot-product length N and, for each N, computes the result two ways and   //
// reports the cycle count of both. Cross-checks correctness (SW == HW) and prints      //
// machine-parseable "DATA,N,sw,hw" lines for plotting plus a human-readable table.     //
//                                                                                    //
//   1. dotprod_sw : pure C, hardware 'mul' (RISC-V M extension), int64 accumulate.    //
//   2. dotprod_hw : the custom 'mac' instruction (CFU), 48-bit hardware accumulator.  //
//                                                                                    //
// Custom instruction (CUSTOM-0 opcode, R-type, funct3) - matches neorv32_cpu_alu_cfu: //
//   mac_acc(a,b) 000 : acc += signed(a[15:0]) * signed(b[15:0]); ret acc[31:0]        //
//   mac_rdlo()   001 : ret acc[31:0]                                                  //
//   mac_rdhi()   010 : ret sign_ext(acc[47:32])                                       //
//   mac_clr()    011 : acc <= 0                                                       //
//                                                                                    //
// Requires UART0, the Xcfu ISA extension, and Zicntr (cycle CSR).                     //
// ================================================================================ //

#include <neorv32.h>

#define BAUD_RATE 19200
#define N_MAX     256

#define mac_acc(a, b) RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b000, 0b0000000, (a), (b))
#define mac_rdlo()    RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b001, 0b0000000, 0, 0)
#define mac_rdhi()    RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b010, 0b0000000, 0, 0)
#define mac_clr()     RISCV_INSTR_R_TYPE(RISCV_OPCODE_CUSTOM0, 0b011, 0b0000000, 0, 0)

int16_t vec_a[N_MAX];
int16_t vec_b[N_MAX];

/* dot-product lengths to sweep */
const int N_list[] = {4, 8, 16, 32, 64, 128, 256};
#define N_COUNT (int)(sizeof(N_list) / sizeof(N_list[0]))

int64_t dotprod_sw(const int16_t *a, const int16_t *b, int n) {
  int64_t acc = 0;
  for (int i = 0; i < n; i++) {
    acc += (int64_t)((int32_t)a[i] * (int32_t)b[i]);
  }
  return acc;
}

int64_t dotprod_hw(const int16_t *a, const int16_t *b, int n) {
  mac_clr();
  for (int i = 0; i < n; i++) {
    mac_acc((uint32_t)(int32_t)a[i], (uint32_t)(int32_t)b[i]);
  }
  uint32_t lo = mac_rdlo();
  int32_t  hi = (int32_t)mac_rdhi();
  return ((int64_t)hi << 32) | (uint64_t)lo;
}

int main(void) {

  neorv32_rte_setup();
  if (neorv32_uart0_available() == 0) { return -1; }
  neorv32_uart0_setup(BAUD_RATE, 0);

  if ((neorv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_XCFU)) == 0) {
    neorv32_uart0_printf("ERROR! CFU ('Xcfu') not implemented!\n");
    return -1;
  }
  if ((neorv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_ZICNTR)) == 0) {
    neorv32_uart0_printf("ERROR! Base counters ('Zicntr') not implemented!\n");
    return -1;
  }

  /* deterministic Q8.8 test vectors */
  for (int i = 0; i < N_MAX; i++) {
    vec_a[i] = (int16_t)(((i % 31) + 1) << 4);
    vec_b[i] = (int16_t)((((i * 3) % 61) - 30) << 4);
  }

  /* NEORV32's tiny printf has no field-width support, so columns are plain. */
  neorv32_uart0_printf("\n<<< MAC custom-instruction benchmark (Q8.8 dot-product sweep) >>>\n\n");
  neorv32_uart0_printf("N\tSW_cyc\tHW_cyc\tspeedup\tcorrect\n");

  for (int k = 0; k < N_COUNT; k++) {
    int n = N_list[k];

    neorv32_cpu_csr_write(CSR_MCYCLE, 0);
    int64_t res_sw = dotprod_sw(vec_a, vec_b, n);
    uint32_t cyc_sw = neorv32_cpu_csr_read(CSR_MCYCLE);

    neorv32_cpu_csr_write(CSR_MCYCLE, 0);
    int64_t res_hw = dotprod_hw(vec_a, vec_b, n);
    uint32_t cyc_hw = neorv32_cpu_csr_read(CSR_MCYCLE);

    uint32_t sp100 = (cyc_hw > 0) ? (cyc_sw * 100) / cyc_hw : 0;
    int ok = (res_sw == res_hw);

    neorv32_uart0_printf("%u\t%u\t%u\t%u.%u%ux\t%s\n",
                         (uint32_t)n, cyc_sw, cyc_hw,
                         sp100 / 100, (sp100 / 10) % 10, sp100 % 10,
                         ok ? "OK" : "FAIL");

    /* machine-parseable line for the plotting script */
    neorv32_uart0_printf("DATA,%u,%u,%u\n", (uint32_t)n, cyc_sw, cyc_hw);
  }

  neorv32_uart0_printf("\nBenchmark completed.\n");
  return 0;
}

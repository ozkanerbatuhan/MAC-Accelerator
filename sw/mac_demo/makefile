# MAC-Accelerator demo application makefile.
# Builds against the NEORV32 software framework (sibling clone).
#
# Usage (from this directory, with riscv-none-elf-gcc on PATH):
#   make clean_all exe        # build the executable (neorv32_exe.bin) for UART upload
#   make clean_all image      # build initialized IMEM image (application_image.vhd)
#
# Upload neorv32_exe.bin via the NEORV32 bootloader over UART0 (19200-8N1).

# CPU ISA: rv32imc + Zicsr/Zifencei. M = hardware multiply for the SW baseline;
# the custom 'mac' instruction is emitted via .insn so it needs no march flag.
MARCH = rv32imc_zicsr_zifencei

# Optimization
EFFORT = -Os

# Match the processor memory sizes configured in neorv32_zedboard_top.vhd
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=16k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k

# Path to the NEORV32 root (sibling of the MAC-Accelerator project)
NEORV32_HOME ?= ../../../neorv32

include $(NEORV32_HOME)/sw/common/common.mk

# Builds one firmware image per core configuration.
#   bench_rv32ic.hex      - no M extension (multiply via libgcc __mulsi3)
#   bench_rv32imc.hex     - M extension (MUL instruction)
#   bench_rv32imc_mac.hex - M extension + custom MAC kernels
#   bench_rv32im*.hex     - same without compressed instructions (all 32-bit, word aligned)
# "M" here is Zmmul (multiply only): the cores are built without a divider.
TOOLCHAIN ?= $(HOME)/AMD/2025.2/gnu/riscv/lin/bin/riscv64-unknown-elf-
CC      = $(TOOLCHAIN)gcc
OBJCOPY = $(TOOLCHAIN)objcopy
OBJDUMP = $(TOOLCHAIN)objdump
CFLAGS  = -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -Wall -Wextra
LDFLAGS = -T link.ld -Wl,--gc-sections,--no-warn-rwx-segments -Wl,--build-id=none -lgcc
OUT     = build

all: $(OUT)/bench_rv32ic.hex $(OUT)/bench_rv32imc.hex $(OUT)/bench_rv32imc_mac.hex \
     $(OUT)/bench_rv32im.hex $(OUT)/bench_rv32im_mac.hex

$(OUT)/bench_rv32ic.elf: start.S bench.c link.ld | $(OUT)
	$(CC) -march=rv32ic $(CFLAGS) start.S bench.c -o $@ $(LDFLAGS)
$(OUT)/bench_rv32imc.elf: start.S bench.c link.ld | $(OUT)
	$(CC) -march=rv32ic_zmmul $(CFLAGS) start.S bench.c -o $@ $(LDFLAGS)
$(OUT)/bench_rv32imc_mac.elf: start.S bench.c mac.h link.ld | $(OUT)
	$(CC) -march=rv32ic_zmmul -DUSE_MAC $(CFLAGS) start.S bench.c -o $@ $(LDFLAGS)
$(OUT)/bench_rv32im.elf: start.S bench.c link.ld | $(OUT)
	$(CC) -march=rv32i_zmmul $(CFLAGS) start.S bench.c -o $@ $(LDFLAGS)
$(OUT)/bench_rv32im_mac.elf: start.S bench.c mac.h link.ld | $(OUT)
	$(CC) -march=rv32i_zmmul -DUSE_MAC $(CFLAGS) start.S bench.c -o $@ $(LDFLAGS)

$(OUT)/%.hex: $(OUT)/%.elf
	$(OBJCOPY) -O binary $< $(OUT)/$*.bin
	python3 ../scripts/bin2hex.py $(OUT)/$*.bin $@
	$(OBJDUMP) -d $< > $(OUT)/$*.lst

$(OUT):
	mkdir -p $@

clean:
	rm -rf $(OUT)
.PHONY: all clean

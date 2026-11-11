/* mac.h - C wrappers for the pcpi_mac custom instructions.
 *
 * Encoded with the assembler's .insn directive (R-type, opcode custom-0 = 0x0B,
 * funct3 = 0), so no compiler or binutils changes are needed:
 *     .insn r opcode, funct3, funct7, rd, rs1, rs2
 *
 * The accumulator is architectural state inside the coprocessor, so every
 * wrapper is "asm volatile" to stop the compiler reordering or deleting it.
 */
#ifndef MAC_H
#define MAC_H

#include <stdint.h>

/* acc = 0 */
static inline void mac_reset(void)
{
	__asm__ volatile (".insn r 0x0B, 0, 1, x0, x0, x0");
}

/* acc += a * b  (result not written back: rd = x0) */
static inline void mac_acc(int32_t a, int32_t b)
{
	__asm__ volatile (".insn r 0x0B, 0, 0, x0, %0, %1" :: "r"(a), "r"(b));
}

/* acc += a.lo*b.lo + a.hi*b.hi  (two packed signed int16 per register) */
static inline void mac_acc16x2(uint32_t a, uint32_t b)
{
	__asm__ volatile (".insn r 0x0B, 0, 3, x0, %0, %1" :: "r"(a), "r"(b));
}

/* return acc */
static inline int32_t mac_read(void)
{
	int32_t r;
	__asm__ volatile (".insn r 0x0B, 0, 2, %0, x0, x0" : "=r"(r));
	return r;
}

#endif

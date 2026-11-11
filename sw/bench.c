/* bench.c - dot-product / matrix-multiply benchmark for the pcpi_mac unit.
 *
 * Every kernel is timed with rdcycle and checked against a reference result.
 * Output lines have the form
 *     RESULT <kernel> cycles=<n> value=<checksum> <PASS|FAIL>
 * and are parsed by scripts/run_bench.py. The exit code is the failure count.
 *
 * Build with -DUSE_MAC to include the custom-instruction kernels; without it
 * the same file runs on a core that has no MAC unit.
 */
#include <stdint.h>
#ifdef USE_MAC
#include "mac.h"
#endif

#define N   1024   /* dot-product length                 */
#define M   16     /* matrix size for the M x M x M matmul */

/* ------------------------------------------------------------ console */
#define CONSOLE (*(volatile uint32_t *)0x10000000)

static void putstr(const char *s) { while (*s) CONSOLE = *s++; }

static void putdec(int32_t v)
{
	char buf[12];
	int i = 0;
	uint32_t u = v < 0 ? -(uint32_t)v : (uint32_t)v;
	if (v < 0) CONSOLE = '-';
	do { buf[i++] = '0' + (char)(u % 10u); u /= 10u; } while (u);
	while (i) CONSOLE = buf[--i];
}

static inline uint32_t rdcycle(void)
{
	uint32_t c;
	__asm__ volatile ("rdcycle %0" : "=r"(c));
	return c;
}

/* ------------------------------------------------------------ data */
static int32_t a32[N], b32[N];
static int16_t a16[N] __attribute__((aligned(4)));
static int16_t b16[N] __attribute__((aligned(4)));
static int16_t ma[M][M] __attribute__((aligned(4)));
static int16_t mbt[M][M] __attribute__((aligned(4)));   /* B stored transposed */
static int32_t mc[M][M];

static uint32_t lcg_state = 12345u;
static uint32_t lcg(void) { lcg_state = lcg_state * 1103515245u + 12345u; return lcg_state; }

static void init_data(void)
{
	for (int i = 0; i < N; i++) {
		a32[i] = (int32_t)lcg();
		b32[i] = (int32_t)lcg();
		a16[i] = (int16_t)(lcg() >> 16);
		b16[i] = (int16_t)(lcg() >> 16);
	}
	for (int i = 0; i < M; i++)
		for (int j = 0; j < M; j++) {
			ma[i][j]  = (int16_t)(lcg() >> 16);
			mbt[i][j] = (int16_t)(lcg() >> 16);
		}
}

/* ------------------------------------------------------------ kernels: plain C */
__attribute__((noipa)) static int32_t dot32_c(const int32_t *a, const int32_t *b, int n)
{
	int32_t s = 0;
	for (int i = 0; i < n; i++) s += a[i] * b[i];
	return s;
}

__attribute__((noipa)) static int32_t dot16_c(const int16_t *a, const int16_t *b, int n)
{
	int32_t s = 0;
	for (int i = 0; i < n; i++) s += (int32_t)a[i] * (int32_t)b[i];
	return s;
}

__attribute__((noipa)) static int32_t matmul16_c(void)
{
	int32_t chk = 0;
	for (int i = 0; i < M; i++)
		for (int j = 0; j < M; j++) {
			int32_t s = 0;
			for (int k = 0; k < M; k++) s += (int32_t)ma[i][k] * (int32_t)mbt[j][k];
			mc[i][j] = s;
			chk ^= s + i * M + j;
		}
	return chk;
}

/* ------------------------------------------------------------ kernels: custom MAC */
#ifdef USE_MAC
__attribute__((noipa)) static int32_t dot32_mac(const int32_t *a, const int32_t *b, int n)
{
	const int32_t *end = a + n;      /* end-pointer loop, as GCC emits for dot32_c */
	mac_reset();
	while (a != end) mac_acc(*a++, *b++);
	return mac_read();
}

/* int16 data, one element per MAC (scalar loads) */
__attribute__((noipa)) static int32_t dot16_mac(const int16_t *a, const int16_t *b, int n)
{
	const int16_t *end = a + n;
	mac_reset();
	while (a != end) mac_acc(*a++, *b++);
	return mac_read();
}

/* int16 data, two elements per MAC (packed 32-bit loads); n must be even */
__attribute__((noipa)) static int32_t dot16_mac16x2(const int16_t *a, const int16_t *b, int n)
{
	const uint32_t *pa = (const uint32_t *)a, *pb = (const uint32_t *)b;
	const uint32_t *end = pa + n / 2;
	mac_reset();
	while (pa != end) mac_acc16x2(*pa++, *pb++);
	return mac_read();
}

__attribute__((noipa)) static int32_t matmul16_mac16x2(void)
{
	int32_t chk = 0;
	for (int i = 0; i < M; i++)
		for (int j = 0; j < M; j++) {
			const uint32_t *pa = (const uint32_t *)ma[i], *pb = (const uint32_t *)mbt[j];
			mac_reset();
			for (int k = 0; k < M / 2; k++) mac_acc16x2(pa[k], pb[k]);
			int32_t s = mac_read();
			mc[i][j] = s;
			chk ^= s + i * M + j;
		}
	return chk;
}
#endif

/* ------------------------------------------------------------ harness */
static int failures;

static void report(const char *name, uint32_t cycles, int32_t value, int32_t expect)
{
	int ok = value == expect;
	if (!ok) failures++;
	putstr("RESULT "); putstr(name);
	putstr(" cycles="); putdec((int32_t)cycles);
	putstr(" value="); putdec(value);
	putstr(ok ? " PASS\n" : " FAIL\n");
}

#define BENCH(name, expr, expect) do {              \
		uint32_t t0 = rdcycle();                    \
		int32_t v = (expr);                         \
		uint32_t t1 = rdcycle();                    \
		report(name, t1 - t0, v, (expect));         \
	} while (0)

int main(void)
{
	init_data();

	/* references, computed once with the plain C kernels */
	int32_t ref_dot32 = dot32_c(a32, b32, N);
	int32_t ref_dot16 = dot16_c(a16, b16, N);
	int32_t ref_mm    = matmul16_c();

	BENCH("dot32_c",  dot32_c(a32, b32, N), ref_dot32);
	BENCH("dot16_c",  dot16_c(a16, b16, N), ref_dot16);
	BENCH("matmul16_c", matmul16_c(), ref_mm);
#ifdef USE_MAC
	BENCH("dot32_mac",     dot32_mac(a32, b32, N),     ref_dot32);
	BENCH("dot16_mac",     dot16_mac(a16, b16, N),     ref_dot16);
	BENCH("dot16_mac16x2", dot16_mac16x2(a16, b16, N), ref_dot16);
	BENCH("matmul16_mac16x2", matmul16_mac16x2(), ref_mm);
#endif
	putstr(failures ? "BENCH FAIL\n" : "BENCH PASS\n");
	return failures;
}

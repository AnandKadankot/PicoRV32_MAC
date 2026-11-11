// core_top.v - PicoRV32 (RV32I[M]C) with optional MAC coprocessor on PCPI.
//
// Used both by the simulation testbench and as the out-of-context synthesis
// top in Vivado, so the measured hardware is exactly the simulated hardware.
//
//   ENABLE_MUL      : PicoRV32 iterative multiplier (pcpi_mul)
//   ENABLE_FAST_MUL : PicoRV32 DSP-based multiplier (pcpi_fast_mul)
//   WITH_MAC        : add pcpi_mac on the external PCPI port
//   MAC_PIPE        : pcpi_mac latency option (see pcpi_mac.v)
//   COMPRESSED_ISA  : RVC support (1 = RV32IC base, 0 = RV32I base)

`default_nettype none

module core_top #(
	parameter [0:0] ENABLE_MUL      = 0,
	parameter [0:0] ENABLE_FAST_MUL = 0,
	parameter [0:0] WITH_MAC        = 0,
	parameter       MAC_PIPE        = 2,
	parameter [0:0] COMPRESSED_ISA  = 1
) (
	input  wire        clk,
	input  wire        resetn,
	output wire        trap,

	output wire        mem_valid,
	output wire        mem_instr,
	input  wire        mem_ready,
	output wire [31:0] mem_addr,
	output wire [31:0] mem_wdata,
	output wire [ 3:0] mem_wstrb,
	input  wire [31:0] mem_rdata
);
	wire        pcpi_valid;
	wire [31:0] pcpi_insn, pcpi_rs1, pcpi_rs2;
	wire        pcpi_wr, pcpi_wait, pcpi_ready;
	wire [31:0] pcpi_rd;

	picorv32 #(
		.COMPRESSED_ISA  (COMPRESSED_ISA),
		.ENABLE_COUNTERS (1),
		.ENABLE_PCPI     (WITH_MAC),
		.ENABLE_MUL      (ENABLE_MUL),
		.ENABLE_FAST_MUL (ENABLE_FAST_MUL),
		.CATCH_ILLINSN   (1)
	) cpu (
		.clk        (clk),
		.resetn     (resetn),
		.trap       (trap),
		.mem_valid  (mem_valid),
		.mem_instr  (mem_instr),
		.mem_ready  (mem_ready),
		.mem_addr   (mem_addr),
		.mem_wdata  (mem_wdata),
		.mem_wstrb  (mem_wstrb),
		.mem_rdata  (mem_rdata),
		.pcpi_valid (pcpi_valid),
		.pcpi_insn  (pcpi_insn),
		.pcpi_rs1   (pcpi_rs1),
		.pcpi_rs2   (pcpi_rs2),
		.pcpi_wr    (pcpi_wr),
		.pcpi_rd    (pcpi_rd),
		.pcpi_wait  (pcpi_wait),
		.pcpi_ready (pcpi_ready),
		.irq        (32'b0),
		.eoi        (),
		.mem_la_read (), .mem_la_write (), .mem_la_addr (),
		.mem_la_wdata (), .mem_la_wstrb (),
		.trace_valid (), .trace_data ()
	);

	generate if (WITH_MAC) begin : g_mac
		pcpi_mac #(.PIPE(MAC_PIPE)) mac (
			.clk        (clk),
			.resetn     (resetn),
			.pcpi_valid (pcpi_valid),
			.pcpi_insn  (pcpi_insn),
			.pcpi_rs1   (pcpi_rs1),
			.pcpi_rs2   (pcpi_rs2),
			.pcpi_wr    (pcpi_wr),
			.pcpi_rd    (pcpi_rd),
			.pcpi_wait  (pcpi_wait),
			.pcpi_ready (pcpi_ready)
		);
	end else begin : g_nomac
		assign pcpi_wr    = 1'b0;
		assign pcpi_rd    = 32'b0;
		assign pcpi_wait  = 1'b0;
		assign pcpi_ready = 1'b0;
	end endgenerate
endmodule

`default_nettype wire

// fpga_top.v - complete Zynq-7020 system for the MAC-extended PicoRV32.
//
//   125 MHz board clock -> MMCM -> core clock (CORE_MHZ)
//   PicoRV32 RV32IMC + fast multiplier + MAC coprocessor (core_top)
//   128 KiB block RAM, initialised with the benchmark firmware at build time
//   UART transmitter (8N1) replacing the simulation console
//   LEDs: [0] program finished, [1] exit code == 0, [2] trap, [3] heartbeat
//
// Memory map (same as sim/tb_soc.v, so the same firmware image runs unchanged):
//   0x0000_0000 .. 0x0001_FFFF  RAM
//   0x1000_0000                 console: write a byte -> UART TX (core stalls while UART busy)
//   0x2000_0000                 exit: write the program's exit code
//
// RAM timing matches tb_soc.v (ready one cycle after mem_valid), so benchmark
// cycle counts are identical to the simulation results.
//
// Pinout: PYNQ-Z2 board (xc7z020clg400-1), see constraints/pynq_z2.xdc.

`default_nettype none

module fpga_top #(
	parameter       CORE_MHZ  = 125,                       // 1000 / CORE_MHZ must be a valid MMCM divide
	parameter       BAUD      = 115200,
	parameter       CLKS_PER_BIT = CORE_MHZ * 1000000 / BAUD,
	parameter       FIRMWARE  = "bench_rv32imc_mac.hex",
	parameter       MAC_PIPE  = 2
) (
	input  wire       clk_125,    // board oscillator
	input  wire       btn_rst,    // active-high reset button
	output wire       uart_tx,
	output wire [3:0] led
);
	// ---------------------------------------------------------------- clock
	wire clk, clk_unbuf, clk_fb, locked;
	MMCME2_BASE #(
		.CLKIN1_PERIOD    (8.0),                 // 125 MHz in
		.CLKFBOUT_MULT_F  (8.0),                 // VCO = 1000 MHz
		.CLKOUT0_DIVIDE_F (1000.0 / CORE_MHZ)
	) mmcm (
		.CLKIN1 (clk_125), .CLKFBIN (clk_fb), .CLKFBOUT (clk_fb),
		.CLKOUT0 (clk_unbuf), .LOCKED (locked), .RST (1'b0), .PWRDWN (1'b0),
		.CLKOUT0B (), .CLKOUT1 (), .CLKOUT1B (), .CLKOUT2 (), .CLKOUT2B (),
		.CLKOUT3 (), .CLKOUT3B (), .CLKOUT4 (), .CLKOUT5 (), .CLKOUT6 (), .CLKFBOUTB ()
	);
	BUFG bufg (.I(clk_unbuf), .O(clk));

	// ---------------------------------------------------------------- reset
	// button / MMCM lock are synchronised into the core clock domain, then a
	// 16-cycle counter releases reset. Everything is synchronous (no async
	// set/reset), so the block-RAM enables are never driven by a register with
	// an asynchronous reset (Vivado DRC REQP-1839).
	reg [1:0] rst_sync  = 2'b11;
	reg [4:0] rst_cnt   = 0;
	reg       resetn    = 0;
	always @(posedge clk) begin
		rst_sync <= {rst_sync[0], btn_rst || !locked};
		if (rst_sync[1])       rst_cnt <= 0;
		else if (!rst_cnt[4])  rst_cnt <= rst_cnt + 1'b1;
		resetn <= rst_cnt[4] && !rst_sync[1];
	end

	// ---------------------------------------------------------------- core
	wire        trap, mem_valid, mem_instr;
	reg         mem_ready = 0;
	wire [31:0] mem_addr, mem_wdata;
	wire [3:0]  mem_wstrb;
	reg  [31:0] mem_rdata = 0;

	core_top #(
		.ENABLE_MUL(0), .ENABLE_FAST_MUL(1), .WITH_MAC(1), .MAC_PIPE(MAC_PIPE), .COMPRESSED_ISA(1)
	) core (
		.clk(clk), .resetn(resetn), .trap(trap),
		.mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
		.mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata)
	);

	// ---------------------------------------------------------------- RAM (block RAM, byte writes)
	(* ram_style = "block" *) reg [31:0] ram [0:32767];
	initial $readmemh(FIRMWARE, ram);

	wire        sel_ram  = mem_addr[31:17] == 0;
	wire        sel_con  = mem_addr == 32'h1000_0000;
	wire        sel_exit = mem_addr == 32'h2000_0000;
	wire        req      = resetn && mem_valid && !mem_ready;
	wire [14:0] waddr    = mem_addr[16:2];

	integer b;
	always @(posedge clk) begin
		if (req && sel_ram) begin
			mem_rdata <= ram[waddr];
			for (b = 0; b < 4; b = b + 1)
				if (mem_wstrb[b]) ram[waddr][8*b +: 8] <= mem_wdata[8*b +: 8];
		end
	end

	// ---------------------------------------------------------------- UART TX (8N1)
	reg  [9:0]  tx_shift = 10'h3FF;
	reg  [3:0]  tx_bits  = 0;
	reg  [15:0] tx_cnt   = 0;
	wire        tx_busy  = tx_bits != 0;
	assign uart_tx = tx_shift[0];

	wire con_write = req && sel_con && |mem_wstrb && !tx_busy;

	always @(posedge clk) begin
		if (!resetn) begin
			tx_shift <= 10'h3FF; tx_bits <= 0; tx_cnt <= 0;
		end else if (con_write) begin
			tx_shift <= {1'b1, mem_wdata[7:0], 1'b0};   // stop, data (LSB first), start
			tx_bits  <= 10;
			tx_cnt   <= CLKS_PER_BIT - 1;
		end else if (tx_busy) begin
			if (tx_cnt == 0) begin
				tx_shift <= {1'b1, tx_shift[9:1]};
				tx_bits  <= tx_bits - 1'b1;
				tx_cnt   <= CLKS_PER_BIT - 1;
			end else
				tx_cnt <= tx_cnt - 1'b1;
		end
	end

	// ---------------------------------------------------------------- handshake, exit, LEDs
	reg done = 0, pass = 0, trapped = 0;
	always @(posedge clk) begin
		mem_ready <= 0;
		if (!resetn) begin
			done <= 0; pass <= 0; trapped <= 0;
		end else begin
			if (trap) trapped <= 1;
			if (req) begin
				if (sel_con && |mem_wstrb)
					mem_ready <= !tx_busy;          // stall the core until the UART is free
				else
					mem_ready <= 1;                 // RAM, exit, and unmapped accesses
				if (sel_exit && |mem_wstrb) begin
					done <= 1;
					pass <= mem_wdata == 0;
				end
			end
		end
	end

	reg [26:0] beat = 0;
	always @(posedge clk) beat <= beat + 1'b1;

	assign led = {beat[26], trapped, pass, done};
endmodule

`default_nettype wire

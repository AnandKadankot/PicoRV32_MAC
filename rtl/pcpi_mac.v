// pcpi_mac.v - Multiply-accumulate coprocessor for PicoRV32 (PCPI interface)
//
// Custom instructions, R-type, opcode custom-0 (7'b0001011), funct3 = 3'b000:
//
//   funct7  mnemonic   operation
//   ------  ---------  -------------------------------------------------------
//   0x00    mac        acc <= acc + rs1*rs2                    ; rd <= new acc
//   0x01    macrst     acc <= rs1*rs2                          ; rd <= new acc
//   0x02    macrd      (acc unchanged)                         ; rd <= acc
//   0x03    mac16x2    acc <= acc + rs1[15:0]*rs2[15:0]
//                             + rs1[31:16]*rs2[31:16] (signed) ; rd <= new acc
//
// The accumulator is 32 bits wide and wraps like C int32 arithmetic, so results
// are bit-exact with a plain C reference loop. PicoRV32's PCPI port does not
// forward the old rd value, which is why the accumulator lives in this unit.
//
// Parameter PIPE selects the latency (cycles from pcpi_valid to pcpi_ready):
//   PIPE = 0 : multiply straight from the core's operand registers   (latency 1)
//   PIPE = 1 : operands registered, then multiplied                  (latency 2)
//   PIPE = 2 : as PIPE = 1 plus one register stage after the multiplier, which
//              Vivado packs into the DSP48 MREG/PREG pipeline        (latency 3)

`default_nettype none

module pcpi_mac #(
	parameter PIPE = 2
) (
	input  wire        clk,
	input  wire        resetn,

	input  wire        pcpi_valid,
	input  wire [31:0] pcpi_insn,
	input  wire [31:0] pcpi_rs1,
	input  wire [31:0] pcpi_rs2,
	output wire        pcpi_wr,
	output wire [31:0] pcpi_rd,
	output wire        pcpi_wait,
	output wire        pcpi_ready
);
	localparam LAT = PIPE + 1;

	localparam [6:0] OPC_CUSTOM0 = 7'b0001011;
	localparam [1:0] OP_MAC     = 2'd0;
	localparam [1:0] OP_MACRST  = 2'd1;
	localparam [1:0] OP_MACRD   = 2'd2;
	localparam [1:0] OP_MAC16X2 = 2'd3;

	// ---------------- decode ----------------
	wire insn_hit = pcpi_valid
	             && pcpi_insn[6:0]   == OPC_CUSTOM0
	             && pcpi_insn[14:12] == 3'b000
	             && pcpi_insn[31:27] == 5'b00000;   // funct7 in 0..3
	wire [1:0] insn_op = pcpi_insn[26:25];

	// valid token shift register; the result is presented when it reaches the end
	reg  [LAT-1:0] active;
	wire           start = resetn && insn_hit && !active;
	wire           result_valid = active[LAT-1];

	// ---------------- operand stage (PIPE >= 1) ----------------
	reg  [31:0] a_q, b_q;
	reg  [1:0]  op_a;
	always @(posedge clk)
		if (start) begin
			a_q  <= pcpi_rs1;
			b_q  <= pcpi_rs2;
			op_a <= insn_op;
		end

	wire [31:0] mul_a  = PIPE ? a_q  : pcpi_rs1;
	wire [31:0] mul_b  = PIPE ? b_q  : pcpi_rs2;
	wire [1:0]  mul_op = PIPE ? op_a : insn_op;
	wire        mul_en = PIPE ? active[0] : start;

	// ---------------- multiplier stage(s) ----------------
	wire [31:0]        p32    = mul_a * mul_b;     // low 32 bits are sign-agnostic
	wire signed [31:0] p16_lo = $signed(mul_a[15:0])  * $signed(mul_b[15:0]);
	wire signed [31:0] p16_hi = $signed(mul_a[31:16]) * $signed(mul_b[31:16]);

	reg  [31:0] prod;          // product presented to the accumulator
	reg  [1:0]  op_m;          // opcode presented to the accumulator

	generate if (PIPE == 2) begin : g_pipe2
		// first register stage directly after the multipliers (-> DSP MREG/PREG),
		// packed-16 sum and the result mux happen in the second stage
		reg [31:0] p32_r, p16_lo_r, p16_hi_r;
		reg [1:0]  op_r;
		always @(posedge clk) begin
			if (mul_en) begin
				p32_r    <= p32;
				p16_lo_r <= p16_lo;
				p16_hi_r <= p16_hi;
				op_r     <= mul_op;
			end
			if (active[1]) begin
				prod <= (op_r == OP_MAC16X2) ? p16_lo_r + p16_hi_r : p32_r;
				op_m <= op_r;
			end
		end
	end else begin : g_pipe01
		always @(posedge clk)
			if (mul_en) begin
				prod <= (mul_op == OP_MAC16X2) ? p16_lo + p16_hi : p32;
				op_m <= mul_op;
			end
	end endgenerate

	// ---------------- accumulate / result ----------------
	reg  [31:0] acc;
	wire [31:0] acc_next = (op_m == OP_MACRST) ? prod : acc + prod;

	always @(posedge clk) begin
		if (!resetn) begin
			active <= 0;
			acc    <= 32'd0;
		end else begin
			active <= {active, start};
			if (result_valid && op_m != OP_MACRD)
				acc <= acc_next;
		end
	end

	assign pcpi_wr    = result_valid;
	assign pcpi_ready = result_valid;
	assign pcpi_wait  = 1'b0;
	assign pcpi_rd    = (op_m == OP_MACRD) ? acc : acc_next;
endmodule

`default_nettype wire

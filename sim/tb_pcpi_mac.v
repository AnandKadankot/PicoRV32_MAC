// tb_pcpi_mac.v - self-checking unit test for pcpi_mac.
// Drives the PCPI handshake exactly like PicoRV32 does (pcpi_valid held high
// until pcpi_ready, then dropped) and compares every result and the internal
// accumulator against a behavioural reference model.

`timescale 1ns/1ps
`default_nettype none

module tb_pcpi_mac;
	parameter PIPE = 1;
	parameter N_RANDOM = 20000;

	reg clk = 0, resetn = 0;
	always #5 clk = ~clk;

	reg         pcpi_valid = 0;
	reg  [31:0] pcpi_insn = 0, pcpi_rs1 = 0, pcpi_rs2 = 0;
	wire        pcpi_wr, pcpi_wait, pcpi_ready;
	wire [31:0] pcpi_rd;

	pcpi_mac #(.PIPE(PIPE)) dut (
		.clk(clk), .resetn(resetn),
		.pcpi_valid(pcpi_valid), .pcpi_insn(pcpi_insn),
		.pcpi_rs1(pcpi_rs1), .pcpi_rs2(pcpi_rs2),
		.pcpi_wr(pcpi_wr), .pcpi_rd(pcpi_rd),
		.pcpi_wait(pcpi_wait), .pcpi_ready(pcpi_ready)
	);

	function [31:0] insn(input [6:0] f7, input [6:0] opc, input [2:0] f3);
		insn = {f7, 5'd2, 5'd1, f3, 5'd3, opc};
	endfunction

	reg  [31:0] ref_acc = 0;
	integer errors = 0, checks = 0, latency, expected_latency, i;

	function [31:0] model(input [1:0] op, input [31:0] a, input [31:0] b, input [31:0] acc);
		reg signed [31:0] lo, hi;
		begin
			lo = $signed(a[15:0])  * $signed(b[15:0]);
			hi = $signed(a[31:16]) * $signed(b[31:16]);
			case (op)
				2'd0: model = acc + a * b;
				2'd1: model = a * b;
				2'd2: model = acc;
				2'd3: model = acc + lo + hi;
			endcase
		end
	endfunction

	// Issue one instruction; expect a response unless the encoding is foreign.
	task issue(input [31:0] ins, input [31:0] a, input [31:0] b, input expect_hit);
		reg [31:0] exp;
		begin
			@(negedge clk);
			pcpi_insn = ins; pcpi_rs1 = a; pcpi_rs2 = b; pcpi_valid = 1;
			latency = 0;
			while (!pcpi_ready && latency < 20) begin
				@(posedge clk); #1; latency = latency + 1;
			end
			if (expect_hit) begin
				exp = model(ins[26:25], a, b, ref_acc);
				checks = checks + 1;
				if (!pcpi_ready || !pcpi_wr || pcpi_rd !== exp || latency != expected_latency) begin
					errors = errors + 1;
					if (errors < 10)
						$display("FAIL op=%0d a=%h b=%h acc=%h got=%h exp=%h ready=%b lat=%0d",
						         ins[26:25], a, b, ref_acc, pcpi_rd, exp, pcpi_ready, latency);
				end
				if (ins[26:25] != 2'd2) ref_acc = exp;
			end else begin
				checks = checks + 1;
				if (pcpi_ready) begin
					errors = errors + 1;
					$display("FAIL: unit answered foreign instruction %h", ins);
				end
			end
			@(negedge clk);
			pcpi_valid = 0;
			// idle gap like the core's fetch/decode (1..3 cycles)
			repeat (1 + ($unsigned($random) % 3)) @(negedge clk);
		end
	endtask

	function [31:0] corner(input integer k);
		case (k % 8)
			0: corner = 32'h0000_0000;
			1: corner = 32'hFFFF_FFFF;
			2: corner = 32'h8000_0000;
			3: corner = 32'h7FFF_FFFF;
			4: corner = 32'h8000_7FFF;
			5: corner = 32'h7FFF_8000;
			6: corner = 32'h0001_FFFF;
			default: corner = $random;
		endcase
	endfunction

	initial begin
		expected_latency = PIPE + 1;
		repeat (4) @(posedge clk);
		resetn = 1;

		// directed: reset accumulator, small dot product, read back
		issue(insn(7'd1, 7'b0001011, 3'b000), 3, 4, 1);          // macrst 12
		issue(insn(7'd0, 7'b0001011, 3'b000), 5, 6, 1);          // mac    42
		issue(insn(7'd0, 7'b0001011, 3'b000), -7, 2, 1);         // mac    28
		issue(insn(7'd2, 7'b0001011, 3'b000), 0, 0, 1);          // macrd  28
		issue(insn(7'd3, 7'b0001011, 3'b000), {16'hFFFF,16'd3}, {16'd5,16'd7}, 1); // 28+21-5

		// foreign encodings must be ignored (MUL, other funct3/funct7, other opcode)
		issue(insn(7'd1, 7'b0110011, 3'b000), 1, 1, 0);
		issue(insn(7'd0, 7'b0001011, 3'b001), 1, 1, 0);
		issue(insn(7'd4, 7'b0001011, 3'b000), 1, 1, 0);
		issue(insn(7'd0, 7'b0101011, 3'b000), 1, 1, 0);

		// corner-case operand pairs for every op
		for (i = 0; i < 256; i = i + 1)
			issue(insn({5'd0, i[1:0]}, 7'b0001011, 3'b000), corner(i), corner(i / 8 + 3), 1);

		// random stream
		for (i = 0; i < N_RANDOM; i = i + 1)
			issue(insn({5'd0, $random} & 7'h03, 7'b0001011, 3'b000), $random, $random, 1);

		if (errors == 0)
			$display("PCPI_MAC UNIT TEST PASS (PIPE=%0d): %0d checks, latency %0d", PIPE, checks, expected_latency);
		else
			$display("PCPI_MAC UNIT TEST FAIL (PIPE=%0d): %0d errors in %0d checks", PIPE, errors, checks);
		$finish;
	end
endmodule

`default_nettype wire

// tb_fpga_top.v - runs the benchmark firmware on the complete FPGA top level
// (MMCM, reset logic, block RAM, UART) and decodes the UART output.
// The UART runs at CLKS_PER_BIT = 8 here so simulation stays fast.

`timescale 1ns/1ps
`default_nettype none

module tb_fpga_top;
	parameter FIRMWARE = "bench_rv32imc_mac.hex";
	parameter CORE_MHZ = 125;
	localparam CPB = 8;

	reg clk_125 = 0, btn_rst = 1;
	always #4 clk_125 = ~clk_125;
	wire uart_tx;
	wire [3:0] led;

	fpga_top #(.CORE_MHZ(CORE_MHZ), .CLKS_PER_BIT(CPB), .FIRMWARE(FIRMWARE)) dut (
		.clk_125(clk_125), .btn_rst(btn_rst), .uart_tx(uart_tx), .led(led));

	// UART receiver, sampling on the core clock
	integer i; reg [7:0] ch;
	initial begin
		forever begin
			@(negedge uart_tx);
			repeat (CPB + CPB / 2) @(posedge dut.clk);
			for (i = 0; i < 8; i = i + 1) begin
				ch[i] = uart_tx;
				repeat (CPB) @(posedge dut.clk);
			end
			$write("%c", ch); $fflush;
		end
	end

	initial begin
		#200 btn_rst = 0;
		wait (led[0] || led[2]);
		repeat (20 * CPB) @(posedge dut.clk);   // let the last UART byte finish
		$display("\nFPGA TOP: done=%b pass=%b trap=%b", led[0], led[1], led[2]);
		$finish;
	end
	initial begin #50_000_000; $display("\nTIMEOUT"); $finish; end
endmodule

`default_nettype wire

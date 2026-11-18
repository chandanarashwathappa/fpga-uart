`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_loopback: uart_tx output wired straight into uart_rx input
//
//   tx_data -> [uart_tx] --tx line--> [uart_rx] -> rx_data
//
// Every byte sent must come out of the receiver unchanged, with no framing
// errors and no extra or missing bytes. This tests that the two designs agree
// with each other, not just with my own testbench models.
//
// Tests:
//   1. Directed bytes: 00 FF 55 AA 01 80
//   2. 100 random bytes, back-to-back (next byte starts as soon as TX is free)
//   3. Totals: bytes received = bytes sent, frame_err never raised
//
// Prints "PASS: N checks, 0 errors" or "FAIL: ..." lines.
// -----------------------------------------------------------------------------
module tb_loopback;

    localparam int CLKS_PER_BIT = 16;
    localparam int CLK_PERIOD   = 10;     // 10 ns = 100 MHz

    logic       clk   = 1'b0;
    logic       rst_n = 1'b0;

    // TX side
    logic       tx_start = 1'b0;
    logic [7:0] tx_data  = 8'h00;
    logic       tx_busy, tx_done;

    // The wire between them
    logic       serial_line;

    // RX side
    logic [7:0] rx_data;
    logic       rx_valid, frame_err;

    int checks = 0;
    int errors = 0;
    int sent   = 0;
    logic [7:0] rand_byte;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (serial_line),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk       (clk),
        .rst_n     (rst_n),
        .rx        (serial_line),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .frame_err (frame_err)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Count every receiver output pulse
    int valid_count = 0;
    int err_count   = 0;
    always @(negedge clk) begin
        if (rx_valid  === 1'b1) valid_count++;
        if (frame_err === 1'b1) err_count++;
    end

    task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s: got 0x%0h, expected 0x%0h (t=%0t ns)", what, got, exp, $time);
        end
    endtask

    // Send a byte through TX and wait for it to come out of RX
    task automatic loop_byte(input logic [7:0] b);
        int wait_clks;

        // Wait until the transmitter is free
        while (tx_busy) @(negedge clk);

        // Pulse tx_start for one clock
        tx_data  = b;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        sent++;

        // Wait for the receiver (one frame + margin)
        wait_clks = 0;
        while (rx_valid !== 1'b1 && wait_clks < 12 * CLKS_PER_BIT) begin
            @(negedge clk);
            wait_clks++;
        end
        check("rx_valid arrived", rx_valid, 1);
        check("received byte = sent byte", rx_data, b);
        @(negedge clk);   // step past the 1-clock rx_valid pulse
    endtask

    initial begin
        $dumpfile("tb_loopback.vcd");
        $dumpvars(0, tb_loopback);

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        // 1. Directed bytes
        loop_byte(8'h00);
        loop_byte(8'hFF);
        loop_byte(8'h55);
        loop_byte(8'hAA);
        loop_byte(8'h01);
        loop_byte(8'h80);

        // 2. Random bytes, back-to-back
        repeat (100) begin
            rand_byte = $urandom_range(0, 255);
            loop_byte(rand_byte);
        end

        // 3. Totals, after the line has gone idle
        while (tx_busy) @(negedge clk);
        repeat (2 * CLKS_PER_BIT) @(negedge clk);
        check("bytes received = bytes sent", valid_count, sent);
        check("no framing errors", err_count, 0);

        if (errors == 0)
            $display("PASS: %0d checks, 0 errors (%0d bytes looped back)", checks, sent);
        else
            $display("FAIL: %0d checks, %0d errors", checks, errors);
        $finish;
    end

    // Safety net: stop if the simulation hangs
    initial begin
        #(CLK_PERIOD * 500_000);
        $display("FAIL: timeout, simulation took too long");
        $finish;
    end

endmodule

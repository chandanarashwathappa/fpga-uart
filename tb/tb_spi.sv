`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_spi: self-checking testbench for spi_master, all 4 SPI modes
//
// Structure:
//   tb_spi            top: clock, reset, runs 4 mode tests in parallel,
//                     adds up the results, prints PASS / FAIL
//   spi_mode_test     one spi_master + one SPI slave model for a given
//                     CPOL / CPHA / CLK_DIV, plus the test sequence
//   spi_slave_model   behavioural SPI slave written straight from the SPI
//                     definition, so it is an independent reference
//
// Each mode test checks, for every transfer:
//   - MOSI path: byte the slave received  = byte the master sent
//   - MISO path: byte the master received = byte the slave sent
//   - SCLK was at its idle level (CPOL) when CS_n fell and after the transfer
//   - exactly 8 bits were clocked
//   - CS_n high and busy low after done
// with directed byte pairs (00/FF, 55/AA, 01/80 ...) and 30 random pairs.
//
// The 4 modes also use different CLK_DIV values (1, 2, 3, 4) to test the
// clock divider.
//
// Prints "PASS: N checks, 0 errors" or "FAIL: ..." lines.
// -----------------------------------------------------------------------------

// ============================================================================
// SPI slave model (testbench only, not synthesisable)
// ============================================================================
module spi_slave_model #(
    parameter bit CPOL = 1'b0,
    parameter bit CPHA = 1'b0
) (
    input  logic       sclk,
    input  logic       cs_n,
    input  logic       mosi,
    output logic       miso,
    input  logic [7:0] tx_byte,        // byte the slave sends back
    output logic [7:0] rx_byte,        // byte the slave received
    output logic [31:0] bit_count,     // bits sampled in this transfer
    output logic       sclk_at_cs_fall // SCLK level when CS_n went low
);
    logic [7:0] sh_out, sh_in;
    logic       is_leading, is_sample;

    initial begin
        miso            = 1'b0;
        rx_byte         = 8'h00;
        bit_count       = 0;
        sclk_at_cs_fall = 1'bx;
    end

    // Transfer begins
    always @(negedge cs_n) begin
        sclk_at_cs_fall = sclk;
        bit_count       = 0;
        sh_in           = 8'h00;
        sh_out          = tx_byte;
        if (!CPHA) begin
            // CPHA = 0: first bit must be on MISO before the first edge
            miso   = sh_out[7];
            sh_out = {sh_out[6:0], 1'b0};
        end
    end

    // Every SCLK edge while selected
    always @(posedge sclk or negedge sclk) begin
        if (cs_n === 1'b0) begin
            // Leading edge = SCLK moves away from its idle level
            is_leading = (sclk !== CPOL);
            is_sample  = CPHA ? !is_leading : is_leading;

            if (is_sample) begin
                sh_in = {sh_in[6:0], mosi};     // read MOSI, MSB first
                bit_count++;
            end else begin
                miso   = sh_out[7];             // put next bit on MISO
                sh_out = {sh_out[6:0], 1'b0};
            end
        end
    end

    // Transfer ends
    always @(posedge cs_n) begin
        rx_byte = sh_in;
        miso    = 1'b0;
    end
endmodule

// ============================================================================
// One SPI mode: master + slave model + test sequence
// ============================================================================
module spi_mode_test #(
    parameter bit CPOL    = 1'b0,
    parameter bit CPHA    = 1'b0,
    parameter int CLK_DIV = 2
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic        finished,
    output logic [31:0] checks,
    output logic [31:0] errors
);
    localparam int MODE = {CPOL, CPHA};

    logic       start   = 1'b0;
    logic [7:0] data_in = 8'h00;
    logic [7:0] data_out;
    logic       busy, done;
    logic       sclk, mosi, miso, cs_n;

    logic [7:0] slave_tx = 8'h00;
    logic [7:0] slave_rx;
    logic [31:0] slave_bits;
    logic       slave_sclk_at_cs;

    logic [7:0] m_byte, s_byte;

    spi_master #(.CLK_DIV(CLK_DIV), .CPOL(CPOL), .CPHA(CPHA)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .data_in  (data_in),
        .data_out (data_out),
        .busy     (busy),
        .done     (done),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso),
        .cs_n     (cs_n)
    );

    spi_slave_model #(.CPOL(CPOL), .CPHA(CPHA)) slave (
        .sclk            (sclk),
        .cs_n            (cs_n),
        .mosi            (mosi),
        .miso            (miso),
        .tx_byte         (slave_tx),
        .rx_byte         (slave_rx),
        .bit_count       (slave_bits),
        .sclk_at_cs_fall (slave_sclk_at_cs)
    );

    task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL: mode %0d: %s: got 0x%0h, expected 0x%0h (t=%0t ns)",
                     MODE, what, got, exp, $time);
        end
    endtask

    // One full-duplex transfer: master sends m, slave sends s
    task automatic xfer(input logic [7:0] m, input logic [7:0] s);
        int wait_clks;

        slave_tx = s;
        data_in  = m;
        start    = 1'b1;
        @(negedge clk);
        start    = 1'b0;
        check("busy after start", busy, 1);
        check("cs_n low during transfer", cs_n, 0);

        // Wait for done (one transfer is 18 * CLK_DIV clocks; allow plenty)
        wait_clks = 0;
        while (done !== 1'b1 && wait_clks < 40 * CLK_DIV) begin
            @(negedge clk);
            wait_clks++;
        end
        check("done pulse seen", done, 1);
        check("MISO path: master received slave byte", data_out, s);
        check("MOSI path: slave received master byte", slave_rx, m);
        check("8 bits clocked", slave_bits, 8);
        check("SCLK idle level at CS_n fall", slave_sclk_at_cs, CPOL);
        check("SCLK back at idle level", sclk, CPOL);
        check("cs_n high after done", cs_n, 1);
        check("busy low after done", busy, 0);

        @(negedge clk);
        check("done is a 1-clock pulse", done, 0);
    endtask

    initial begin
        finished = 1'b0;
        checks   = 0;
        errors   = 0;

        wait (rst_n === 1'b1);
        repeat (2) @(negedge clk);

        // Idle state after reset
        check("idle cs_n high", cs_n, 1);
        check("idle SCLK = CPOL", sclk, CPOL);
        check("idle not busy", busy, 0);

        // Directed pairs: master byte, slave byte
        xfer(8'h00, 8'hFF);
        xfer(8'hFF, 8'h00);
        xfer(8'h55, 8'hAA);
        xfer(8'hAA, 8'h55);
        xfer(8'h01, 8'h80);
        xfer(8'h80, 8'h01);
        xfer(8'hA5, 8'hA5);

        // Random pairs, back-to-back
        repeat (30) begin
            m_byte = $urandom_range(0, 255);
            s_byte = $urandom_range(0, 255);
            xfer(m_byte, s_byte);
        end

        $display("mode %0d (CPOL=%0d CPHA=%0d CLK_DIV=%0d): %0d checks, %0d errors",
                 MODE, CPOL, CPHA, CLK_DIV, checks, errors);
        finished = 1'b1;
    end
endmodule

// ============================================================================
// Top level
// ============================================================================
module tb_spi;

    localparam int CLK_PERIOD = 10;   // 10 ns = 100 MHz

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic [3:0]  fin;
    logic [31:0] c0, c1, c2, c3;
    logic [31:0] e0, e1, e2, e3;

    spi_mode_test #(.CPOL(1'b0), .CPHA(1'b0), .CLK_DIV(2)) mode0 (.clk(clk), .rst_n(rst_n), .finished(fin[0]), .checks(c0), .errors(e0));
    spi_mode_test #(.CPOL(1'b0), .CPHA(1'b1), .CLK_DIV(3)) mode1 (.clk(clk), .rst_n(rst_n), .finished(fin[1]), .checks(c1), .errors(e1));
    spi_mode_test #(.CPOL(1'b1), .CPHA(1'b0), .CLK_DIV(4)) mode2 (.clk(clk), .rst_n(rst_n), .finished(fin[2]), .checks(c2), .errors(e2));
    spi_mode_test #(.CPOL(1'b1), .CPHA(1'b1), .CLK_DIV(1)) mode3 (.clk(clk), .rst_n(rst_n), .finished(fin[3]), .checks(c3), .errors(e3));

    initial begin
        int total_checks, total_errors;

        $dumpfile("tb_spi.vcd");
        $dumpvars(0, tb_spi);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        wait (fin === 4'b1111);
        @(negedge clk);

        total_checks = c0 + c1 + c2 + c3;
        total_errors = e0 + e1 + e2 + e3;

        if (total_errors == 0)
            $display("PASS: %0d checks, 0 errors (SPI modes 0-3)", total_checks);
        else
            $display("FAIL: %0d checks, %0d errors", total_checks, total_errors);
        $finish;
    end

    // Safety net: stop if the simulation hangs
    initial begin
        #(CLK_PERIOD * 200_000);
        $display("FAIL: timeout, simulation took too long (finished = %b)", fin);
        $finish;
    end

endmodule

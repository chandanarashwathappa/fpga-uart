`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// spi_master: SPI master, 8-bit, full duplex, MSB first, SPI modes 0-3
//
// SPI mode = {CPOL, CPHA}
//   CPOL: level of SCLK when idle (0 = low, 1 = high)
//   CPHA: 0 = data sampled on the LEADING edge (first edge after CS_n falls),
//             changed on the trailing edge. The first bit is put on MOSI
//             as soon as CS_n goes low.
//         1 = data changed on the leading edge, sampled on the TRAILING edge.
//
//   Mode | CPOL | CPHA | SCLK idle | sample on
//   -----+------+------+-----------+-----------
//    0   |  0   |  0   |   low     | rising
//    1   |  0   |  1   |   low     | falling
//    2   |  1   |  0   |   high    | falling
//    3   |  1   |  1   |   high    | rising
//
// SCLK frequency = clk frequency / (2 * CLK_DIV)
//   e.g. 100 MHz clk, CLK_DIV = 50 -> 1 MHz SCLK
//
// Usage: put a byte on data_in and pulse start for one clock while busy = 0.
//        When done pulses, data_out holds the byte received on MISO.
// -----------------------------------------------------------------------------
module spi_master #(
    parameter int CLK_DIV = 4,      // clk cycles per SCLK half-period (>= 1)
    parameter bit CPOL    = 1'b0,
    parameter bit CPHA    = 1'b0
) (
    input  logic       clk,
    input  logic       rst_n,       // active-low reset
    input  logic       start,       // 1-clock pulse: start a transfer
    input  logic [7:0] data_in,     // byte to send on MOSI
    output logic [7:0] data_out,    // byte received on MISO
    output logic       busy,        // 1 during a transfer
    output logic       done,        // 1-clock pulse at the end of a transfer
    output logic       sclk,
    output logic       mosi,
    input  logic       miso,
    output logic       cs_n         // chip select, active low
);

    typedef enum logic [1:0] {
        IDLE,     // CS_n high, SCLK at idle level
        XFER,     // 16 SCLK edges = 8 bits
        FINISH    // half a SCLK period before CS_n goes high again
    } state_t;

    state_t state;

    localparam int DIV_W = (CLK_DIV > 1) ? $clog2(CLK_DIV) : 1;
    logic [DIV_W-1:0] div_cnt;      // counts clk cycles in one SCLK half-period
    logic [3:0]       edge_cnt;     // which SCLK edge is next: 0 .. 15
    logic [7:0]       tx_sh;        // bits still to send, MSB first
    logic [7:0]       rx_sh;        // bits received so far

    logic div_end, leading, sample_edge;
    assign div_end     = (div_cnt == CLK_DIV - 1);
    assign leading     = ~edge_cnt[0];              // edges 0,2,4.. are leading
    assign sample_edge = CPHA ? ~leading : leading; // otherwise it's a shift edge

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            div_cnt  <= '0;
            edge_cnt <= '0;
            tx_sh    <= '0;
            rx_sh    <= '0;
            data_out <= '0;
            done     <= 1'b0;
            sclk     <= CPOL;
            mosi     <= 1'b0;
            cs_n     <= 1'b1;
        end else begin
            done <= 1'b0;                // default: done is a 1-clock pulse

            case (state)
                IDLE: begin
                    sclk     <= CPOL;
                    cs_n     <= 1'b1;
                    div_cnt  <= '0;
                    edge_cnt <= '0;
                    if (start) begin
                        cs_n  <= 1'b0;
                        rx_sh <= '0;
                        if (!CPHA) begin
                            // CPHA = 0: first bit must be ready before the first edge
                            mosi  <= data_in[7];
                            tx_sh <= {data_in[6:0], 1'b0};
                        end else begin
                            tx_sh <= data_in;
                        end
                        state <= XFER;
                    end
                end

                XFER: begin
                    if (div_end) begin
                        div_cnt  <= '0;
                        sclk     <= ~sclk;              // make one SCLK edge
                        edge_cnt <= edge_cnt + 1'b1;

                        if (sample_edge) begin
                            rx_sh <= {rx_sh[6:0], miso};   // read MISO, MSB first
                        end else begin
                            mosi  <= tx_sh[7];              // put next bit on MOSI
                            tx_sh <= {tx_sh[6:0], 1'b0};
                        end

                        if (edge_cnt == 4'd15)
                            state <= FINISH;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                FINISH: begin
                    if (div_end) begin
                        div_cnt  <= '0;
                        cs_n     <= 1'b1;
                        mosi     <= 1'b0;
                        data_out <= rx_sh;
                        done     <= 1'b1;
                        state    <= IDLE;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign busy = (state != IDLE);

endmodule

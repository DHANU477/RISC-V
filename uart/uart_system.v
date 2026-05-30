`timescale 1ns/1ps
`default_nettype none

module uart_mm (
    input  wire        clk,
    input  wire        reset,

    // CPU Memory Interface
    input  wire        mem_write,
    input  wire        mem_read,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,

    // Physical UART Pins
    input  wire        rx,
    output wire        tx
);

    // =====================================================
    // Address Map
    // =====================================================
    localparam UART_TX   = 32'h1000_0000;
    localparam UART_RX   = 32'h1000_0004;
    localparam UART_STAT = 32'h1000_0008;

    // =====================================================
    // Baud Generator
    // =====================================================
    wire txclk_en, rxclk_en;

    baud_rate_gen BRG (
        .clk(clk),
        .reset(reset),
        .rxclk_en(rxclk_en),
        .txclk_en(txclk_en)
    );

    // =====================================================
    // TX Logic
    // =====================================================
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire       tx_done;

    tx_fsm TX (
        .clk(clk),
        .reset(reset),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .txclk_en(txclk_en),
        .tx_out(tx),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // Generate 1-cycle start pulse on write
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_start <= 0;
            tx_data  <= 8'b0;
        end else begin
            tx_start <= 0;  // default

            if (mem_write && addr == UART_TX && !tx_busy) begin
                tx_data  <= write_data[7:0];
                tx_start <= 1;
            end
        end
    end

    // =====================================================
    // RX Logic
    // =====================================================
    wire [7:0] rx_data;
    wire       rx_done;
    wire       rx_error;

    rx_fsm RX (
        .clk(clk),
        .reset(reset),
        .rx_in(rx),
        .rxclk_en(rxclk_en),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .rx_error(rx_error)
    );

    // Sticky RX ready flag
    reg rx_ready;

    always @(posedge clk or posedge reset) begin
        if (reset)
            rx_ready <= 0;
        else if (rx_done)
            rx_ready <= 1;
        else if (mem_read && addr == UART_RX)
            rx_ready <= 0;  // clear when CPU reads
    end

    // =====================================================
    // Read Data Mux
    // =====================================================
    always @(*) begin
        if (mem_read) begin
            case (addr)
                UART_RX:   read_data = {24'b0, rx_data};
                UART_STAT: read_data = {29'b0, rx_error, rx_ready, tx_busy};
                default:   read_data = 32'b0;
            endcase
        end else begin
            read_data = 32'b0;
        end
    end

endmodule

// =====================================================
// Baud Rate Generator
// =====================================================
module baud_rate_gen #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire reset,
    output reg  txclk_en,
    output reg  rxclk_en
);

    localparam integer TX_DIV = CLK_FREQ / BAUD_RATE;
    localparam integer RX_DIV = CLK_FREQ / (BAUD_RATE * 16);

    reg [31:0] tx_cnt;
    reg [31:0] rx_cnt;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_cnt   <= 0;
            rx_cnt   <= 0;
            txclk_en <= 0;
            rxclk_en <= 0;
        end else begin
            // TX
            if (tx_cnt >= TX_DIV-1) begin
                tx_cnt   <= 0;
                txclk_en <= 1;
            end else begin
                tx_cnt   <= tx_cnt + 1;
                txclk_en <= 0;
            end

            // RX (16x)
            if (rx_cnt == RX_DIV-1) begin
                rx_cnt   <= 0;
                rxclk_en <= 1;
            end else begin
                rx_cnt   <= rx_cnt + 1;
                rxclk_en <= 0;
            end
        end
    end

endmodule

// =====================================================
// Transmit FSM
// =====================================================
module tx_fsm(
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    input  wire       txclk_en,
    output reg        tx_out,
    output reg        tx_busy,
    output reg        tx_done
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_index;
    reg [7:0] data_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            tx_out    <= 1'b1;
            tx_busy   <= 0;
            tx_done   <= 0;
            bit_index <= 0;
        end else begin
            tx_done <= 0;

            case (state)

                IDLE: begin
                    tx_out  <= 1'b1;
                    tx_busy <= 0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1;
                        state    <= START;
                    end
                end

                START: if (txclk_en) begin
                    tx_out    <= 1'b0;
                    bit_index <= 0;
                    state     <= DATA;
                end

                DATA: if (txclk_en) begin
                    tx_out <= data_reg[bit_index];
                    if (bit_index == 3'd7)
                        state <= STOP;
                    else
                        bit_index <= bit_index + 1;
                end

                STOP: if (txclk_en) begin
                    tx_out  <= 1'b1;
                    tx_busy <= 0;
                    tx_done <= 1;
                    state   <= IDLE;
                end

            endcase
        end
    end

endmodule

// =====================================================
// Receive FSM
// =====================================================
module rx_fsm(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx_in,
    input  wire       rxclk_en,
    output reg  [7:0] rx_data,
    output reg        rx_done,
    output reg        rx_error
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_index;
    reg [7:0] data_reg;
    reg [3:0] sample_cnt;

    // Synchronizer for rx_in
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        rx_sync1 <= rx_in;
        rx_sync2 <= rx_sync1;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            rx_done    <= 0;
            rx_error   <= 0;
            rx_data    <= 0;
            bit_index  <= 0;
            sample_cnt <= 0;
        end else begin
            rx_done <= 0;

            case (state)

                IDLE: begin
                    if (!rx_sync2) begin
                        state      <= START;
                        sample_cnt <= 0;
                    end
                end

                START: if (rxclk_en) begin
                    if (sample_cnt == 7) begin
                        if (!rx_sync2) begin
                            state      <= DATA;
                            bit_index  <= 0;
                            sample_cnt <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end else
                        sample_cnt <= sample_cnt + 1;
                end

                DATA: if (rxclk_en) begin
                    if (sample_cnt == 15) begin
                        data_reg[bit_index] <= rx_sync2;
                        sample_cnt <= 0;
                        if (bit_index == 7)
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1;
                    end else
                        sample_cnt <= sample_cnt + 1;
                end

                STOP: if (rxclk_en) begin
                    if (!rx_sync2)
                        rx_error <= 1;

                    rx_data <= data_reg;
                    rx_done <= 1;
                    state   <= IDLE;
                end

            endcase
        end
    end

endmodule

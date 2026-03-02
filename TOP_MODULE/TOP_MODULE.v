

`timescale 1ns/1ps

module riscv_3stage_top (
    input wire clk,
    input wire reset,
    input wire uart_rx,     // external RX pin
    output wire uart_tx     // external TX pin
);

    // =====================================================
    // FETCH STAGE
    // =====================================================
    wire [31:0] pc, instr;
    wire take_branch;
    wire [31:0] target_pc;
    wire stall;

    pc_unit PC(clk, reset, stall, take_branch, target_pc, pc);

    reg [31:0] imem [0:255];
    initial $readmemh("instruction.hex", imem);

    reg [31:0] instr_reg;
    always @(posedge clk)
        instr_reg <= imem[pc[31:2]];

    assign instr = instr_reg;

    reg [31:0] IF_ID_pc, IF_ID_instr;

    always @(posedge clk or posedge reset)
        if (reset) begin
            IF_ID_pc <= 0;
            IF_ID_instr <= 0;
        end else if (take_branch) begin
            IF_ID_instr <= 0;
        end else if (!stall) begin
            IF_ID_pc <= pc;
            IF_ID_instr <= instr;
        end

    // =====================================================
    // DECODE STAGE
    // =====================================================
    wire [4:0] rs1, rs2, rd;
    wire [31:0] reg_rs1, reg_rs2, imm;
    wire [2:0] alu_op, branch_funct3;
    wire alu_sub, use_imm, branch, jal, jalr;
    wire mem_read, mem_write, reg_write;
    wire [1:0] wb_sel, mem_size;
    wire mem_signext;

    decoder DEC(IF_ID_instr, rs1, rs2, rd, alu_op, alu_sub, use_imm,
                branch, branch_funct3, jal, jalr,
                mem_read, mem_write, mem_size, mem_signext, reg_write, wb_sel);

    imm_gen IMM(IF_ID_instr, imm);

    reg ID_EX_mem_read;
    reg [4:0] ID_EX_rd;

    always @(posedge clk or posedge reset)
        if (reset || stall) begin
            ID_EX_mem_read <= 0;
            ID_EX_rd <= 0;
        end else begin
            ID_EX_mem_read <= mem_read;
            ID_EX_rd <= rd;
        end

    assign stall = ID_EX_mem_read &&
                   ((ID_EX_rd == rs1 && rs1 != 0) ||
                    (ID_EX_rd == rs2 && rs2 != 0));

    // =====================================================
    // REGISTER FILE
    // =====================================================
    wire [31:0] wb_data;
    reg ID_WB_reg_write;
    reg [4:0] ID_WB_rd;

    regfile RF(clk, ID_WB_reg_write,
               rs1, rs2,
               ID_WB_rd,
               wb_data,
               reg_rs1, reg_rs2);

    // Forwarding
    wire [31:0] fwd_rs1 =
        (ID_WB_reg_write && (ID_WB_rd == rs1) && (rs1 != 0)) ?
        wb_data : reg_rs1;

    wire [31:0] fwd_rs2 =
        (ID_WB_reg_write && (ID_WB_rd == rs2) && (rs2 != 0)) ?
        wb_data : reg_rs2;

    wire [31:0] store_data =
        (ID_WB_reg_write && (ID_WB_rd == rs2) && (rs2 != 0)) ?
        wb_data : fwd_rs2;

    wire [31:0] alu_src2 = use_imm ? imm : fwd_rs2;
    wire [31:0] alu_result;

    alu ALU(fwd_rs1, alu_src2, alu_op, alu_sub, alu_result);

    // =====================================================
    // BRANCH
    // =====================================================
    assign take_branch =
        (branch && alu_result[0]) || jal || jalr;

    assign target_pc =
        jalr ? {alu_result[31:1], 1'b0} :
               (IF_ID_pc + imm);

    // =====================================================
    // MEMORY + UART INTERCONNECT
    // =====================================================

    wire [31:0] dmem_raw;
    wire [31:0] dmem_data;
    wire [31:0] uart_data;

    // Address decode: 0x1xxxxxxx → UART
    wire uart_sel = (alu_result[31:28] == 4'h1);

    // -----------------------------
    // DATA MEMORY
    // -----------------------------
    data_memory DM (
        .clk(clk),
        .mem_write(mem_write && !uart_sel),
        .addr(alu_result),
        .write_data(store_data),
        .read_data(dmem_data)
    );

    // -----------------------------
    // UART (memory mapped)
    // -----------------------------
    uart_mm UART (
        .clk(clk),
        .reset(reset),
        .mem_write(mem_write && uart_sel),
        .mem_read(mem_read && uart_sel),
        .addr(alu_result),
        .write_data(store_data),
        .read_data(uart_data),
        .rx(uart_rx),
        .tx(uart_tx)
    );

    // Memory/UART read mux
    assign dmem_raw = uart_sel ? uart_data : dmem_data;

    // =====================================================
    // WRITEBACK STAGE
    // =====================================================
    wire [31:0] mem_aligned;

    load_align LA(
        alu_result[1:0],
        mem_size,
        mem_signext,
        dmem_raw,
        mem_aligned
    );

    reg [31:0] ID_WB_alu, ID_WB_mem;
    reg [1:0] ID_WB_wb_sel;

    always @(posedge clk or posedge reset)
        if (reset) begin
            ID_WB_alu <= 0;
            ID_WB_mem <= 0;
            ID_WB_rd <= 0;
            ID_WB_reg_write <= 0;
            ID_WB_wb_sel <= 0;
        end else begin
            ID_WB_alu <= alu_result;
            ID_WB_mem <= mem_read ? mem_aligned : 32'b0;
            ID_WB_rd <= rd;
            ID_WB_reg_write <= reg_write;
            ID_WB_wb_sel <= wb_sel;
        end

    assign wb_data =
        (ID_WB_wb_sel == 2'b00) ? ID_WB_alu :
        (ID_WB_wb_sel == 2'b01) ? ID_WB_mem :
                                 (ID_WB_alu + 4);

endmodule

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

`default_nettype none

module baud_rate_gen #(
    parameter CLK_FREQ  = 50_000_000,   // System clock frequency
    parameter BAUD_RATE = 115200        // Desired baud rate
)(
    input  wire clk,
    input  wire reset,

    output reg  txclk_en,   // 1 pulse per bit period
    output reg  rxclk_en    // 1 pulse per 1/16 bit period
);

    // ----------------------------------------------------
    // Divider calculations
    // ----------------------------------------------------
    localparam integer TX_DIV = CLK_FREQ / BAUD_RATE;
    localparam integer RX_DIV = CLK_FREQ / (BAUD_RATE * 16);

    // ----------------------------------------------------
    // Counters
    // ----------------------------------------------------
    reg [31:0] tx_cnt;
    reg [31:0] rx_cnt;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_cnt   <= 0;
            rx_cnt   <= 0;
            txclk_en <= 0;
            rxclk_en <= 0;
        end else begin
            //------------------------------------------------
            // TX Baud Enable
            //------------------------------------------------
            if (tx_cnt == TX_DIV - 1) begin
                tx_cnt   <= 0;
                txclk_en <= 1;      // 1-cycle pulse
            end else begin
                tx_cnt   <= tx_cnt + 1;
                txclk_en <= 0;
            end

            //------------------------------------------------
            // RX Baud Enable (16x oversampling)
            //------------------------------------------------
            if (rx_cnt == RX_DIV - 1) begin
                rx_cnt   <= 0;
                rxclk_en <= 1;      // 1-cycle pulse
            end else begin
                rx_cnt   <= rx_cnt + 1;
                rxclk_en <= 0;
            end
        end
    end

endmodule
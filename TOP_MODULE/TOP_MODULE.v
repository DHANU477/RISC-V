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

    reg [31:0] instr_pc;
    reg [31:0] instr_reg;
    always @(posedge clk) begin
        instr_reg <= imem[pc[9:2]];
        instr_pc  <= pc;
    end

    assign instr = instr_reg;

    reg [31:0] IF_ID_pc, IF_ID_instr;

    always @(posedge clk or posedge reset)
        if (reset) begin
            IF_ID_pc <= 0;
            IF_ID_instr <= 32'h00000013; // addi x0, x0, 0 (NOP)
        end else if (take_branch) begin
            IF_ID_instr <= 32'h00000013; // NOP
        end else if (!stall) begin
            IF_ID_pc <= instr_pc;
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

    wire [1:0] alu_src1_sel;
    decoder DEC(IF_ID_instr, rs1, rs2, rd, alu_op, alu_sub, use_imm,
                branch, branch_funct3, jal, jalr,
                mem_read, mem_write, mem_size, mem_signext, reg_write, wb_sel, alu_src1_sel);

    imm_gen IMM(IF_ID_instr, imm);

    reg ID_EX_mem_read;
    reg [4:0] ID_EX_rd;
    reg [31:0] ID_EX_pc;

    always @(posedge clk or posedge reset)
        if (reset || stall) begin
            ID_EX_mem_read <= 0;
            ID_EX_rd <= 0;
            ID_EX_pc <= 0;
        end else begin
            ID_EX_mem_read <= mem_read;
            ID_EX_rd <= rd;
            ID_EX_pc <= IF_ID_pc;
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

    wire [31:0] alu_src1 = (alu_src1_sel == 2'b01) ? IF_ID_pc :
                           (alu_src1_sel == 2'b10) ? 32'b0 :
                                                      fwd_rs1;
    wire [31:0] alu_src2 = use_imm ? imm : fwd_rs2;
    wire [31:0] alu_result;

    alu ALU(alu_src1, alu_src2, alu_op, alu_sub, alu_result);

    // =====================================================
    // BRANCH
    // =====================================================
    wire branch_true =
        (branch_funct3 == 3'b000) ? (fwd_rs1 == fwd_rs2) : // BEQ
        (branch_funct3 == 3'b001) ? (fwd_rs1 != fwd_rs2) : // BNE
        (branch_funct3 == 3'b100) ? ($signed(fwd_rs1) < $signed(fwd_rs2)) : // BLT
        (branch_funct3 == 3'b101) ? ($signed(fwd_rs1) >= $signed(fwd_rs2)) : // BGE
        (branch_funct3 == 3'b110) ? (fwd_rs1 < fwd_rs2) : // BLTU
        (branch_funct3 == 3'b111) ? (fwd_rs1 >= fwd_rs2) : // BGEU
        1'b0;

    wire instr_valid = (IF_ID_instr !== 32'hxxxxxxxx);
    assign take_branch = instr_valid && (
        (branch && branch_true) || jal || jalr);

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
        .mem_read(mem_read && !uart_sel),
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

    reg [31:0] ID_WB_alu, ID_WB_mem, ID_WB_pc;
    reg [1:0] ID_WB_wb_sel;

    always @(posedge clk or posedge reset)
        if (reset) begin
            ID_WB_alu <= 0;
            ID_WB_mem <= 0;
            ID_WB_pc  <= 0;
            ID_WB_rd <= 0;
            ID_WB_reg_write <= 0;
            ID_WB_wb_sel <= 0;
        end else begin
            ID_WB_alu <= alu_result;
            ID_WB_mem <= mem_read ? mem_aligned : 32'b0;
            ID_WB_pc  <= ID_EX_pc;
            ID_WB_rd <= rd;
            ID_WB_reg_write <= reg_write;
            ID_WB_wb_sel <= wb_sel;
        end

    assign wb_data =
        (ID_WB_wb_sel == 2'b00) ? ID_WB_alu :
        (ID_WB_wb_sel == 2'b01) ? ID_WB_mem :
                                 (ID_WB_pc + 4);

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

`default_nettype none

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

`default_nettype none

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
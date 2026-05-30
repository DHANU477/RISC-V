`timescale 1ns/1ps

module riscv_3stage_top (
    input wire clk,
    input wire reset,
    input wire uart_rx,     
    output wire uart_tx     
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
    initial $readmemh("uart_demo.hex", imem);

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
        end else if (flush) begin
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

    // =====================================================
    // HAZARD UNIT
    // =====================================================
    wire fwd_rs1_sel, fwd_rs2_sel;
    wire flush;

    hazard_unit HU (
        .ID_EX_mem_read(ID_EX_mem_read),
        .ID_EX_rd(ID_EX_rd),
        .IF_ID_rs1(rs1),
        .IF_ID_rs2(rs2),
        .ID_WB_reg_write(ID_WB_reg_write),
        .ID_WB_rd(ID_WB_rd),
        .take_branch(take_branch),
        .stall(stall),
        .flush(flush),
        .fwd_rs1_sel(fwd_rs1_sel),
        .fwd_rs2_sel(fwd_rs2_sel)
    );

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
    wire [31:0] fwd_rs1 = fwd_rs1_sel ? wb_data : reg_rs1;
    wire [31:0] fwd_rs2 = fwd_rs2_sel ? wb_data : reg_rs2;

    wire [31:0] store_data = (ID_WB_reg_write && (ID_WB_rd == rs2) && (rs2 != 0)) ?
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

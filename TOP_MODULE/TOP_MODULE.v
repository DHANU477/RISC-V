`timescale 1ns/1ps

/* =========================
   TOP MODULE (WITH FORWARDING)
========================= */
module riscv_3stage_top (
    input wire clk,
    input wire reset
);
    wire [31:0] pc, instr;
    wire take_branch;
    wire [31:0] target_pc;
    wire stall;

    pc_unit PC(clk, reset, stall, take_branch, target_pc, pc);

    reg [31:0] imem [0:255];
    initial $readmemh("instruction.hex", imem);
    reg [31:0] instr_reg;

    always @(posedge clk) begin
    	instr_reg <= imem[pc[31:2]];
    end

    assign instr = instr_reg;

    reg [31:0] IF_ID_pc, IF_ID_instr;

    always @(posedge clk or posedge reset)
        if (reset) begin
            IF_ID_pc <= 0; IF_ID_instr <= 0;
        end else if (take_branch) begin
            IF_ID_instr <= 0;
        end else if (!stall) begin
            IF_ID_pc <= pc;
            IF_ID_instr <= instr;
        end

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
            ID_EX_mem_read <= 0; ID_EX_rd <= 0;
        end else begin
            ID_EX_mem_read <= mem_read; ID_EX_rd <= rd;
        end

    assign stall = ID_EX_mem_read &&
                  ((ID_EX_rd == rs1 && rs1 != 0) || (ID_EX_rd == rs2 && rs2 != 0));

    // --- REGISTER FILE & WRITE BACK SIGNALS ---
    wire [31:0] wb_data;
    reg ID_WB_reg_write;
    reg [4:0] ID_WB_rd;

    regfile RF(clk, ID_WB_reg_write, rs1, rs2, ID_WB_rd, wb_data, reg_rs1, reg_rs2);

    // ==========================================
    // NEW: FORWARDING LOGIC
    // ==========================================
    wire [31:0] fwd_rs1 = (ID_WB_reg_write && (ID_WB_rd == rs1) && (rs1 != 0)) ? wb_data : reg_rs1;
    wire [31:0] fwd_rs2 = (ID_WB_reg_write && (ID_WB_rd == rs2) && (rs2 != 0)) ? wb_data : reg_rs2;

    // Store data forwarding (to remove X in memory)
    wire [31:0] store_data = (ID_WB_reg_write && (ID_WB_rd == rs2) && (rs2 != 0)) ? wb_data : fwd_rs2;

    // Use forwarded values for ALU and Memory Data
    wire [31:0] alu_src2 = use_imm ? imm : fwd_rs2;
    wire [31:0] alu_result;
    alu ALU(fwd_rs1, alu_src2, alu_op, alu_sub, alu_result);

    // ==========================================
    // BRANCH LOGIC
    // ==========================================
    assign take_branch = (branch && alu_result[0]) || jal || jalr;
    assign target_pc = jalr ? {alu_result[31:1], 1'b0} : (IF_ID_pc + imm);

    reg [31:0] ID_WB_alu, ID_WB_mem;
    reg [4:0] ID_WB_rd;
    reg [1:0] ID_WB_wb_sel;

    // -----------------------
    // DATA MEMORY
    // -----------------------
    wire [31:0] dmem_raw;

    data_memory DM (
    	.clk(clk),
    	.mem_write(mem_write),
    	.addr(alu_result),      // SAME signal as before
    	.write_data(store_data),   // SAME signal as before
    	.read_data(dmem_raw)
);

    wire [31:0] mem_aligned;
    load_align LA(ID_WB_alu[1:0], mem_size, mem_signext, dmem_raw, mem_aligned);

    // Store operation
    
    always @(posedge clk or posedge reset)
        if (reset) begin
            ID_WB_alu <= 0; ID_WB_mem <= 0;
            ID_WB_rd <= 0; ID_WB_reg_write <= 0;
            ID_WB_wb_sel <= 0;
        end else begin
            ID_WB_alu <= alu_result;
            ID_WB_mem <= (mem_read) ? mem_aligned : 32'b0;
            ID_WB_rd <= rd;
            ID_WB_reg_write <= reg_write;
            ID_WB_wb_sel <= wb_sel;
        end

    assign wb_data =
        (ID_WB_wb_sel == 2'b00) ? ID_WB_alu :
        (ID_WB_wb_sel == 2'b01) ? ID_WB_mem :
                                 (ID_WB_alu + 4);
endmodule
`timescale 1ns/1ps

/* =========================
   DECODER
========================= */
module decoder (
    input  wire [31:0] inst,
    output wire [4:0]  rs1, rs2, rd,
    output reg  [2:0]  alu_op,
    output reg         alu_sub, use_imm,
    output reg         branch,
    output reg  [2:0]  branch_funct3,
    output reg         jal, jalr,
    output reg         mem_read, mem_write,
    output reg  [1:0]  mem_size,
    output reg         mem_signext,
    output reg         reg_write,
    output reg  [1:0]  wb_sel,
    output reg  [1:0]  alu_src1_sel // 0:rs1, 1:pc, 2:zero
);
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

    always @(*) begin
        alu_op=0; alu_sub=0; use_imm=0;
        branch=0; branch_funct3=0;
        jal=0; jalr=0;
        mem_read=0; mem_write=0;
        mem_size=2'b10; mem_signext=1;
        reg_write=0; wb_sel=2'b00;
        alu_src1_sel=2'b00;

        case (opcode)
            7'b0110111: begin // LUI
                reg_write=1; use_imm=1; alu_src1_sel=2'b10; // zero + imm
            end
            7'b0010111: begin // AUIPC
                reg_write=1; use_imm=1; alu_src1_sel=2'b01; // pc + imm
            end
            7'b0110011: begin
                reg_write=1; alu_op=funct3;
                alu_sub=(funct7==7'b0100000);
            end
            7'b0010011: begin
                reg_write=1; use_imm=1;
                alu_op=funct3;
                alu_sub=(funct3==3'b101 && funct7[5]);
            end
            7'b0000011: begin
                reg_write=1; use_imm=1; mem_read=1; wb_sel=2'b01;
                case(funct3)
                    3'b000: mem_size=0;
                    3'b001: mem_size=1;
                    3'b010: mem_size=2;
                    3'b100: begin mem_size=0; mem_signext=0; end
                    3'b101: begin mem_size=1; mem_signext=0; end
                endcase
            end
            7'b0100011: begin
                use_imm=1; mem_write=1;
                case(funct3)
                    3'b000: mem_size=0;
                    3'b001: mem_size=1;
                    3'b010: mem_size=2;
                endcase
            end
            7'b1100011: begin
                branch=1; branch_funct3=funct3;
            end
            7'b1101111: begin
                jal=1; reg_write=1; wb_sel=2'b10;
            end
            7'b1100111: begin
                jalr=1; reg_write=1; use_imm=1; wb_sel=2'b10;
            end
        endcase
    end
endmodule
`timescale 1ns/1ps

module hazard_unit (
    // Load-Use Stall Inputs
    input  wire       ID_EX_mem_read,
    input  wire [4:0] ID_EX_rd,
    input  wire [4:0] IF_ID_rs1,
    input  wire [4:0] IF_ID_rs2,

    // Forwarding Inputs (WB to EX)
    input  wire       ID_WB_reg_write,
    input  wire [4:0] ID_WB_rd,
    
    // Branch Inputs
    input  wire       take_branch,

    // Outputs
    output wire       stall,
    output wire       flush,
    output wire       fwd_rs1_sel,
    output wire       fwd_rs2_sel
);

    // =====================================================
    // LOAD-USE STALL LOGIC
    // =====================================================
    // Stall if the instruction in EX is a 'Load' and its destination
    // register matches either rs1 or rs2 of the current instruction
    // (except for x0).
    assign stall = ID_EX_mem_read &&
                   ((ID_EX_rd == IF_ID_rs1 && IF_ID_rs1 != 0) ||
                    (ID_EX_rd == IF_ID_rs2 && IF_ID_rs2 != 0));

    // =====================================================
    // FORWARDING LOGIC
    // =====================================================
    // Select the WB data if the register being written back 
    // matches the source registers of the current instruction.
    assign fwd_rs1_sel = (ID_WB_reg_write && (ID_WB_rd == IF_ID_rs1) && (IF_ID_rs1 != 0));
    assign fwd_rs2_sel = (ID_WB_reg_write && (ID_WB_rd == IF_ID_rs2) && (IF_ID_rs2 != 0));

    // =====================================================
    // FLUSH LOGIC
    // =====================================================
    // The flush signal is triggered when a branch or jump is taken.
    assign flush = take_branch;

endmodule

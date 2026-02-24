`timescale 1ns/1ps

/* =========================
   PC UNIT
========================= */
module pc_unit (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,
    input  wire        branch_taken,
    input  wire [31:0] branch_addr,
    output reg  [31:0] pc
);
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 0;
        else if (branch_taken)
            pc <= branch_addr;
        else if (!stall)
            pc <= pc + 4;
    end
endmodule
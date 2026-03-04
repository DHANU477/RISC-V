`timescale 1ns/1ps

/* =========================
   REGISTER FILE
========================= */
module regfile (
    input  wire clk,
    input  wire we,
    input  wire [4:0] raddr1, raddr2, waddr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata1, rdata2
);
    integer i;
    reg [31:0] regs [31:0];
    assign rdata1 = (raddr1==0)?0:regs[raddr1];
    assign rdata2 = (raddr2==0)?0:regs[raddr2];
    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'b0;
    end
    always @(posedge clk)
        if (we && waddr!=0)
            regs[waddr] <= wdata;
endmodule

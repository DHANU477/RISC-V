/* =========================
   ALU
========================= */
module alu(
    input wire [31:0] a,b,
    input wire [2:0] alu_op,
    input wire alu_sub,
    output reg [31:0] result
);
    always @(*) begin
        case (alu_op)
            3'b000: result = alu_sub ? a-b : a+b;
            3'b001: result = a << b[4:0];
            3'b010: result = ($signed(a)<$signed(b));
            3'b011: result = (a<b);
            3'b100: result = a^b;
            3'b101: result = alu_sub ? $signed(a)>>>b[4:0] : a>>b[4:0];
            3'b110: result = a|b;
            3'b111: result = a&b;
            default: result = 0;
        endcase
    end
endmodule

/* =========================
   LOAD ALIGN
========================= */
`timescale 1ns/1ps

module load_align(
    input wire [1:0] addr_lsb,
    input wire [1:0] size,
    input wire signext,
    input wire [31:0] rdata_raw,
    output reg [31:0] rdata
);
    always @(*) begin
        case(size)
            2'b00:
                rdata = signext ?
                    {{24{rdata_raw[8*addr_lsb+7]}}, rdata_raw[8*addr_lsb +:8]} :
                    {24'b0, rdata_raw[8*addr_lsb +:8]};
            2'b01:
                rdata = signext ?
                    {{16{rdata_raw[addr_lsb[1]*16+15]}}, rdata_raw[addr_lsb[1]*16 +:16]} :
                    {16'b0, rdata_raw[addr_lsb[1]*16 +:16]};
            default:
                rdata = rdata_raw;
        endcase
    end
endmodule
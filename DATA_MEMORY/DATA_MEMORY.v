`timescale 1ns/1ps

module data_memory (
    input clk,
    input mem_read,
    input mem_write,
    input [31:0] addr,
    input [31:0] write_data,
    output [31:0] read_data
);

    reg [31:0] dmem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            dmem[i] = 32'b0;
    end

    assign read_data = dmem[addr[9:2]];

    always @(posedge clk) begin
        if (mem_write)
            dmem[addr[9:2]] <= write_data;
    end

endmodule
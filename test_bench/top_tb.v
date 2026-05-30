module top_tb;

reg clk;
reg reset;

wire uart_tx;
wire uart_rx;

riscv_3stage_top dut (
    .clk(clk),
    .reset(reset),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
);

assign uart_rx = uart_tx;   // LOOPBACK

initial begin
    clk = 0;
    forever #10 clk = ~clk;
end

initial begin
    reset = 1;
    #100;
    reset = 0;

    #2000000;

    $finish;
end

// Monitor to print Register Updates for comparison with Python
always @(posedge clk) begin
    if (!reset && dut.ID_WB_reg_write && (dut.ID_WB_rd != 0)) begin
        $display("PC: %08x | A:%08x |B: %08x | Result written: %08x to Register x%02d", 
                  dut.pc, dut.ALU.a, dut.ALU.b, dut.wb_data, dut.ID_WB_rd);
    end
end

endmodule
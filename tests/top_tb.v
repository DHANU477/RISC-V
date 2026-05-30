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

    #200000;

    $finish;
end

    // Monitor Block to Output Execution Trace
    always @(posedge clk) begin
        if (!reset) begin
            // Wait for instruction to reach the Writeback (WB) stage of the pipeline
            if (dut.ID_WB_pc != 0 || dut.ID_WB_wb_sel != 0) begin
                $display("PC: %08x | Result written: %08x to Register x%02d", 
                          dut.ID_WB_pc, dut.wb_data, dut.ID_WB_rd);
            end
        end
    end


endmodule
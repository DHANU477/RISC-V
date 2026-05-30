`timescale 1ns/1ps

module uart_standalone_tb;
    reg clk;
    reg reset;
    reg mem_write;
    reg mem_read;
    reg [31:0] addr;
    reg [31:0] write_data;
    wire [31:0] read_data;
    reg rx;
    wire tx;

    // Instantiate UART MM
    uart_mm dut (
        .clk(clk),
        .reset(reset),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .addr(addr),
        .write_data(write_data),
        .read_data(read_data),
        .rx(rx),
        .tx(tx)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Simulation
    initial begin
        $display("Starting Standalone UART Test...");
        reset = 1;
        rx = 1;
        mem_write = 0;
        mem_read = 0;
        addr = 0;
        write_data = 0;
        
        #100;
        reset = 0;
        #100;

        // Write 'H' to TX
        $display("[%t] Writing 'H' (0x48) to UART_TX", $time);
        addr = 32'h1000_0000;
        write_data = 32'h48;
        mem_write = 1;
        #20;
        mem_write = 0;

        // Wait for busy to clear
        #100000;
        
        $display("Standalone test finished at %t", $time);
        $finish;
    end

    always @(negedge tx) begin
        $display("[%t] UART TX START BIT detect", $time);
    end

endmodule

`timescale 1ns/1ps

module top_tb;
    reg clk;
    reg reset;
    reg uart_rx;
    wire uart_tx;

    // Instantiate Top Module
    riscv_3stage_top dut (
        .clk(clk),
        .reset(reset),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // Clock Generation (50MHz -> 20ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Simulation Control
    initial begin
        $display("Starting System Integration Test (Loopback)...");
        $display("Character 'A' (0x41) will be sent to UART_RX.");
        
        reset = 1;
        uart_rx = 1; // Idle high
        #100;
        reset = 0;
        
        #1000;
        
        // Send character 'A' (0x41)
        uart_send_byte(8'h41);
        
        #50000; 
        
        $display("Simulation finished at time %t", $time);
        $finish;
    end

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("[%t] TESTBENCH: Sending byte 0x%h to UART_RX", $time, data);
            uart_rx = 0; // Start bit
            #(8680);
            for (i=0; i<8; i=i+1) begin
                uart_rx = data[i];
                #(8680);
            end
            uart_rx = 1; // Stop bit
            #(8680);
        end
    endtask

    // Optional: Log memory writes or other signals if possible
    always @(posedge clk) begin
        if (!reset) begin
            $display("[%t] PC:%h Instr:%h x1:%h x2:%h x3:%h x4:%h x5:%h x6:%h x7:%h", 
                     $time, dut.pc, dut.instr, 
                     dut.RF.regs[1], dut.RF.regs[2], dut.RF.regs[3], dut.RF.regs[4],
                     dut.RF.regs[5], dut.RF.regs[6], dut.RF.regs[7]);
            $display("         x8:%h x9:%h x10:%h x11:%h x12:%h x13:%h x14:%h x15:%h x16:%h x17:%h",
                     dut.RF.regs[8], dut.RF.regs[9], dut.RF.regs[10], dut.RF.regs[11],
                     dut.RF.regs[12], dut.RF.regs[13], dut.RF.regs[14], dut.RF.regs[15],
                     dut.RF.regs[16], dut.RF.regs[17]);
            
            if (dut.uart_sel && dut.mem_write) begin
                $display("[%t] UART WRITE DETECTED: Addr=%h, Data=%h", $time, dut.alu_result, dut.store_data);
            end
            if (dut.UART.rx_done) begin
                 $display("[%t] UART RX RECEIVED: Data=%h", $time, dut.UART.rx_data);
            end
        end
    end

    always @(negedge uart_tx) begin
        $display("[%t] UART TX START BIT DETECTED (Line goes LOW)", $time);
    end

endmodule

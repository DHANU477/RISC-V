# RISC-V UART Test Program
# Writes "HELLO" to UART TX and polls status

.text
.global _start

_start:
    # Initialize UART base address
    lui t0, 0x10000        # t0 = 0x10000000 (UART_TX)
    
    # 1. Write 'H' (0x48)
    addi t1, zero, 0x48    # 'H'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx        # Wait for transmission

    # 2. Write 'E' (0x45)
    addi t1, zero, 0x45    # 'E'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx

    # 3. Write 'L' (0x4C)
    addi t1, zero, 0x4C    # 'L'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx

    # 4. Write 'L' (0x4C)
    addi t1, zero, 0x4C    # 'L'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx

    # 5. Write 'O' (0x4F)
    addi t1, zero, 0x4F    # 'O'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx

    # 6. Write '\n' (0x0A)
    addi t1, zero, 0x0A    # '\n'
    sw t1, 0(t0)           # Write to UART_TX
    jal ra, wait_tx

loop:
    j loop                 # End of program

# Subroutine to wait for UART TX to be ready (not busy)
# UART_STAT at 0x10000008
# Status bits: {29'b0, rx_error, rx_ready, tx_busy}
# tx_busy is bit 0
wait_tx:
    lw t2, 8(t0)           # Read UART_STAT
    andi t2, t2, 1         # Mask tx_busy bit
    bne t2, zero, wait_tx  # If busy, stay in loop
    ret

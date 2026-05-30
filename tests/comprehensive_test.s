addi x1, x0, 10
addi x2, x0, 20
add x3, x1, x2
sub x4, x2, x1
sw x3, 0(x0)
sw x4, 4(x0)
lw x5, 0(x0)
lw x6, 4(x0)
and x7, x5, x6
or x8, x5, x6
xor x9, x5, x6
slt x10, x6, x5
slti x11, x1, 5
slli x12, x1, 2
srli x13, x2, 1
srai x14, x2, 1
lui x15, 0x10000
addi x16, x15, 65
sw x16, 0(x15)
beq x1, x13, label
addi x1, x1, 1
label: addi x17, x0, 255
jal x0, 0

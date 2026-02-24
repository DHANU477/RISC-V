import re

class RISCVAssembler:
    def __init__(self):
        # Full RV32I Instruction Set Map
        self.instructions = {
            # R-TYPE
            'add':  {'type': 'R', 'opcode': '0110011', 'f3': '000', 'f7': '0000000'},
            'sub':  {'type': 'R', 'opcode': '0110011', 'f3': '000', 'f7': '0100000'},
            'sll':  {'type': 'R', 'opcode': '0110011', 'f3': '001', 'f7': '0000000'},
            'slt':  {'type': 'R', 'opcode': '0110011', 'f3': '010', 'f7': '0000000'},
            'sltu': {'type': 'R', 'opcode': '0110011', 'f3': '011', 'f7': '0000000'},
            'xor':  {'type': 'R', 'opcode': '0110011', 'f3': '100', 'f7': '0000000'},
            'srl':  {'type': 'R', 'opcode': '0110011', 'f3': '101', 'f7': '0000000'},
            'sra':  {'type': 'R', 'opcode': '0110011', 'f3': '101', 'f7': '0100000'},
            'or':   {'type': 'R', 'opcode': '0110011', 'f3': '110', 'f7': '0000000'},
            'and':  {'type': 'R', 'opcode': '0110011', 'f3': '111', 'f7': '0000000'},

            # I-TYPE (Arithmetic/Logical)
            'addi':  {'type': 'I', 'opcode': '0010011', 'f3': '000'},
            'slti':  {'type': 'I', 'opcode': '0010011', 'f3': '010'},
            'sltiu': {'type': 'I', 'opcode': '0010011', 'f3': '011'},
            'xori':  {'type': 'I', 'opcode': '0010011', 'f3': '100'},
            'ori':   {'type': 'I', 'opcode': '0010011', 'f3': '110'},
            'andi':  {'type': 'I', 'opcode': '0010011', 'f3': '111'},
            'slli':  {'type': 'I_shift', 'opcode': '0010011', 'f3': '001', 'f7': '0000000'},
            'srli':  {'type': 'I_shift', 'opcode': '0010011', 'f3': '101', 'f7': '0000000'},
            'srai':  {'type': 'I_shift', 'opcode': '0010011', 'f3': '101', 'f7': '0100000'},

            # I-TYPE (Loads & JALR)
            'lb':    {'type': 'I', 'opcode': '0000011', 'f3': '000'},
            'lh':    {'type': 'I', 'opcode': '0000011', 'f3': '001'},
            'lw':    {'type': 'I', 'opcode': '0000011', 'f3': '010'},
            'lbu':   {'type': 'I', 'opcode': '0000011', 'f3': '100'},
            'lhu':   {'type': 'I', 'opcode': '0000011', 'f3': '101'},
            'jalr':  {'type': 'I', 'opcode': '1100111', 'f3': '000'},

            # S-TYPE (Stores)
            'sb':    {'type': 'S', 'opcode': '0100011', 'f3': '000'},
            'sh':    {'type': 'S', 'opcode': '0100011', 'f3': '001'},
            'sw':    {'type': 'S', 'opcode': '0100011', 'f3': '010'},

            # B-TYPE (Branches)
            'beq':   {'type': 'B', 'opcode': '1100011', 'f3': '000'},
            'bne':   {'type': 'B', 'opcode': '1100011', 'f3': '001'},
            'blt':   {'type': 'B', 'opcode': '1100011', 'f3': '100'},
            'bge':   {'type': 'B', 'opcode': '1100011', 'f3': '101'},
            'bltu':  {'type': 'B', 'opcode': '1100011', 'f3': '110'},
            'bgeu':  {'type': 'B', 'opcode': '1100011', 'f3': '111'},

            # U-TYPE
            'lui':   {'type': 'U', 'opcode': '0110111'},
            'auipc': {'type': 'U', 'opcode': '0010111'},

            # J-TYPE
            'jal':   {'type': 'J', 'opcode': '1101111'},
            
            # Pseudo
            'nop':   {'type': 'pseudo', 'val': '00000013'} 
        }

        self.reg_map = {
            'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 't0': 5, 't1': 6, 't2': 7,
            's0': 8, 'fp': 8, 's1': 9, 'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14,
            'a5': 15, 'a6': 16, 'a7': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
            's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
            't3': 28, 't4': 29, 't5': 30, 't6': 31
        }

    def get_reg_bin(self, reg_str):
        reg_str = reg_str.lower().strip()
        if reg_str.startswith('x'): return format(int(reg_str[1:]), '05b')
        return format(self.reg_map[reg_str], '05b')

    def get_imm_bin(self, val, bits):
        if val < 0: val = (1 << bits) + val
        return format(val & ((1 << bits) - 1), f'0{bits}b')

    def assemble(self, asm_code):
        lines = [l.split('#')[0].split('//')[0].strip() for l in asm_code.split('\n') if l.strip()]
        labels = {}
        processed_lines = []
        pc = 0

        # Pass 1: Label Resolution
        for line in lines:
            if ':' in line:
                label_part, *rest = line.split(':')
                labels[label_part.strip()] = pc
                content = ":".join(rest).strip()
                if content:
                    processed_lines.append((pc, content))
                    pc += 4
            else:
                processed_lines.append((pc, line))
                pc += 4

        # Pass 2: Encoding
        hex_output = []
        for current_pc, line in processed_lines:
            tokens = line.replace(',', ' ').replace('(', ' ').replace(')', ' ').split()
            mnemonic = tokens[0].lower()
            
            if mnemonic == 'nop':
                hex_output.append(self.instructions['nop']['val'])
                continue
                
            inst = self.instructions[mnemonic]
            bin_str = ""

            if inst['type'] == 'R':
                bin_str = inst['f7'] + self.get_reg_bin(tokens[3]) + self.get_reg_bin(tokens[2]) + \
                          inst['f3'] + self.get_reg_bin(tokens[1]) + inst['opcode']

            elif inst['type'] == 'I':
                # Load format: lw rd, offset(rs1) -> [lw, rd, offset, rs1]
                # Normal format: addi rd, rs1, imm -> [addi, rd, rs1, imm]
                if mnemonic in ['lb', 'lh', 'lw', 'lbu', 'lhu', 'jalr']:
                    rd, imm, rs1 = tokens[1], tokens[2], tokens[3]
                else:
                    rd, rs1, imm = tokens[1], tokens[2], tokens[3]
                bin_str = self.get_imm_bin(int(imm, 0), 12) + self.get_reg_bin(rs1) + \
                          inst['f3'] + self.get_reg_bin(rd) + inst['opcode']

            elif inst['type'] == 'I_shift':
                # slli rd, rs1, shamt (shamt is 5 bits, f7 holds the rest)
                bin_str = inst['f7'] + self.get_imm_bin(int(tokens[3], 0), 5) + self.get_reg_bin(tokens[2]) + \
                          inst['f3'] + self.get_reg_bin(tokens[1]) + inst['opcode']

            elif inst['type'] == 'S':
                rs2, imm, rs1 = tokens[1], tokens[2], tokens[3]
                imm_b = self.get_imm_bin(int(imm, 0), 12)
                bin_str = imm_b[:7] + self.get_reg_bin(rs2) + self.get_reg_bin(rs1) + \
                          inst['f3'] + imm_b[7:] + inst['opcode']

            elif inst['type'] == 'B':
                rs1, rs2, target = tokens[1], tokens[2], tokens[3]
                offset = (labels[target] - current_pc) if target in labels else int(target, 0)
                imm_b = self.get_imm_bin(offset, 13)
                bin_str = imm_b[0] + imm_b[2:8] + self.get_reg_bin(rs2) + self.get_reg_bin(rs1) + \
                          inst['f3'] + imm_b[8:12] + imm_b[1] + inst['opcode']

            elif inst['type'] == 'U':
                imm_val = int(tokens[2], 0)
                bin_str = self.get_imm_bin(imm_val, 20) + self.get_reg_bin(tokens[1]) + inst['opcode']

            elif inst['type'] == 'J':
                rd, target = tokens[1], tokens[2]
                offset = (labels[target] - current_pc) if target in labels else int(target, 0)
                imm_b = self.get_imm_bin(offset, 21)
                bin_str = imm_b[0] + imm_b[10:20] + imm_b[9] + imm_b[1:9] + \
                          self.get_reg_bin(rd) + inst['opcode']

            hex_output.append(format(int(bin_str, 2), '08x'))
        
        return hex_output

%%writefile program.s
addi x1, x0, 5
addi x2, x0, 7
add x3, x1, x2
sw x3, 0(x0)



asm = RISCVAssembler()

with open("program.s", "r") as f:
    test_program = f.read()

hex_code = asm.assemble(test_program)

with open("instruction.hex", "w") as f:
    f.write("\n".join(hex_code))

print("Assembly finished. Output: instruction.hex")
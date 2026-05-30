import re
import sys
import os

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
            'nop':   {'type': 'pseudo', 'val': '00000013'},
            'ret':   {'type': 'pseudo_jalr', 'rd': 'zero', 'rs1': 'ra', 'imm': '0'},
            'j':     {'type': 'pseudo_j'}
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
        # Pre-process: remove comments and extra whitespace
        lines = []
        for l in asm_code.split('\n'):
            l = l.split('#')[0].split('//')[0].strip()
            if l:
                lines.append(l)

        labels = {}
        processed_lines = []
        pc = 0

        # Pass 1: Label Resolution and Filtering
        for line in lines:
            if line.startswith('.'): # Skip directives
                continue
            
            if line.endswith(':'):
                labels[line[:-1].strip()] = pc
                continue
            
            if ':' in line:
                label_part, content = line.split(':', 1)
                labels[label_part.strip()] = pc
                content = content.strip()
                if content:
                    processed_lines.append((pc, content))
                    pc += 4
            else:
                processed_lines.append((pc, line))
                pc += 4

        # Pass 2: Encoding
        hex_output = []
        for current_pc, line in processed_lines:
            # Normalize line: replace ( ) , with spaces
            norm_line = line.replace(',', ' ').replace('(', ' ').replace(')', ' ')
            tokens = norm_line.split()
            if not tokens: continue
            
            mnemonic = tokens[0].lower()
            
            if mnemonic == 'nop':
                hex_output.append(self.instructions['nop']['val'])
                continue
            
            if mnemonic == 'ret':
                # ret -> jalr x0, 0(x1)
                inst = self.instructions['jalr']
                bin_str = self.get_imm_bin(0, 12) + self.get_reg_bin('ra') + \
                          inst['f3'] + self.get_reg_bin('zero') + inst['opcode']
                hex_output.append(format(int(bin_str, 2), '08x'))
                continue

            if mnemonic == 'j':
                # j target -> jal x0, target
                inst = self.instructions['jal']
                target = tokens[1]
                offset = (labels[target] - current_pc) if target in labels else int(target, 0)
                imm_b = self.get_imm_bin(offset, 21)
                # J-type: imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd | opcode
                # imm_b is bits 20:0 of offset
                bin_str = imm_b[0] + imm_b[10:20] + imm_b[9] + imm_b[1:9] + \
                          self.get_reg_bin('zero') + inst['opcode']
                hex_output.append(format(int(bin_str, 2), '08x'))
                continue

            if mnemonic not in self.instructions:
                print(f"Error: Unknown instruction {mnemonic} at PC {hex(current_pc)}")
                sys.exit(1)
                
            inst = self.instructions[mnemonic]
            bin_str = ""

            try:
                if inst['type'] == 'R':
                    bin_str = inst['f7'] + self.get_reg_bin(tokens[3]) + self.get_reg_bin(tokens[2]) + \
                              inst['f3'] + self.get_reg_bin(tokens[1]) + inst['opcode']

                elif inst['type'] == 'I':
                    if mnemonic in ['lb', 'lh', 'lw', 'lbu', 'lhu', 'jalr']:
                        rd, imm, rs1 = tokens[1], tokens[2], tokens[3]
                    else:
                        rd, rs1, imm = tokens[1], tokens[2], tokens[3]
                    bin_str = self.get_imm_bin(int(imm, 0), 12) + self.get_reg_bin(rs1) + \
                              inst['f3'] + self.get_reg_bin(rd) + inst['opcode']

                elif inst['type'] == 'I_shift':
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
                    if imm_val > 0xFFFFF:
                        imm_val = imm_val >> 12
                    bin_str = self.get_imm_bin(imm_val, 20) + self.get_reg_bin(tokens[1]) + inst['opcode']

                elif inst['type'] == 'J':
                    rd, target = tokens[1], tokens[2]
                    offset = (labels[target] - current_pc) if target in labels else int(target, 0)
                    imm_b = self.get_imm_bin(offset, 21)
                    bin_str = imm_b[0] + imm_b[10:20] + imm_b[9] + imm_b[1:9] + \
                              self.get_reg_bin(rd) + inst['opcode']

                hex_output.append(format(int(bin_str, 2), '08x'))
            except Exception as e:
                print(f"Error encoding line '{line}': {e}")
                sys.exit(1)
        
        return hex_output

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python assemble_test.py input.s output.hex")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found")
        sys.exit(1)
        
    with open(input_file, "r") as f:
        asm_code = f.read()
        
    assembler = RISCVAssembler()
    hex_code = assembler.assemble(asm_code)
    
    with open(output_file, "w") as f:
        f.write("\n".join(hex_code))
        
    print(f"Successfully assembled {input_file} to {output_file}")

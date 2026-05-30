import sys
import os

# CPU Architectural Mapping
UART_TX   = 0x10000000
UART_RX   = 0x10000004
UART_STAT = 0x10000008

class RISCVModel:
    def __init__(self, trace_enabled=True):
        self.pc = 0
        self.registers = [0] * 32
        self.imem = []  # Instruction array 
        self.dmem = {}  # Data memory words (Dict keyed by address)
        self.trace_enabled = trace_enabled
        self.halted = False

        # UART Stub configs - Used to simulate RX behavior
        self.uart_rx_buffer = "HelloRISCV"
        self.uart_rx_index = 0

    def load_hex(self, filename):
        """Loads instructions from a hex file, handling comments and empty lines."""
        with open(filename, 'r') as f:
            for line in f:
                # Strip comments (anything after '//' or '#')
                line = line.split('//')[0].split('#')[0].strip()
                if not line:
                    continue
                try:
                    # Convert the hex string to an integer
                    self.imem.append(int(line, 16))
                except ValueError as e:
                    print(f"Warning: Skipping invalid line: '{line}' - {e}")
        print(f"Loaded {len(self.imem)} instructions.")
        
    def read_mem(self, addr, size):
        """Reads from memory or simulated memory mapped I/O."""
        # Handle UART Memory Map
        if addr == UART_RX:
            if self.uart_rx_index < len(self.uart_rx_buffer):
                char = ord(self.uart_rx_buffer[self.uart_rx_index])
                self.uart_rx_index += 1
                return char # Byte returned in bottom 8 bits
            return 0
        elif addr == UART_STAT:
            # Returns status indicating RX ready (0x02), TX not busy
            return 0x02 
        elif addr == UART_TX:
            return 0 

        # Standard Data Memory - Aligned to word boundary
        word_addr = addr & 0xFFFFFFFC
        val = self.dmem.get(word_addr, 0)
        
        # Applies size mask for sub-word accesses
        if size == 0: # Byte
            shift = (addr & 3) * 8
            val = (val >> shift) & 0xFF
        elif size == 1: # Half-word
            shift = (addr & 2) * 8
            val = (val >> shift) & 0xFFFF

        return val

    def write_mem(self, addr, size, val):
        """Writes to memory or simulated memory mapped I/O."""
        # Handle UART Memory Map
        if addr == UART_TX:
            char = chr(val & 0xFF)
            sys.stdout.write(char)
            sys.stdout.flush()
            if self.trace_enabled:
                print(f" [UART TX]: '{char}'")
            return
        elif addr in (UART_RX, UART_STAT):
            return # Ignore writes to read-only UART registers
            
        # Standard Data Memory - Read/Modify/Write capability for sub-words
        word_addr = addr & 0xFFFFFFFC
        
        if size == 2: # Word
            self.dmem[word_addr] = val & 0xFFFFFFFF
        elif size == 0: # Byte
            shift = (addr & 3) * 8
            mask = ~(0xFF << shift)
            cur = self.dmem.get(word_addr, 0)
            self.dmem[word_addr] = (cur & mask) | ((val & 0xFF) << shift)
        elif size == 1: # Half
            shift = (addr & 2) * 8
            mask = ~(0xFFFF << shift)
            cur = self.dmem.get(word_addr, 0)
            self.dmem[word_addr] = (cur & mask) | ((val & 0xFFFF) << shift)

    def sign_extend(self, val, bits):
        sign_bit = 1 << (bits - 1)
        return (val & (sign_bit - 1)) - (val & sign_bit)

    def execute_step(self):
        """Fetches, decodes, and executes exactly 1 instruction."""
        if self.halted: return False
        
        # Word index in imem
        imem_idx = self.pc >> 2
        if imem_idx < 0 or imem_idx >= len(self.imem):
            if self.trace_enabled: print(f"PC out of bounds: {hex(self.pc)}. Halting.")
            self.halted = True
            return False

        inst = self.imem[imem_idx]
        opcode = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        funct3 = (inst >> 12) & 0x7
        rs1 = (inst >> 15) & 0x1F
        rs2 = (inst >> 20) & 0x1F
        funct7 = (inst >> 25) & 0x7F
        
        pc_next = self.pc + 4
        trace_str = f"PC: 0x{self.pc:08x} | Inst: 0x{inst:08x} | "

        def write_rd(val):
            val = val & 0xFFFFFFFF
            if rd != 0:
                self.registers[rd] = val
            return val

        val_rs1 = self.registers[rs1]
        val_rs2 = self.registers[rs2]

        if opcode == 0x33: # R-type instructions
            if funct3 == 0x0: res = (val_rs1 - val_rs2) if funct7 == 0x20 else (val_rs1 + val_rs2)
            elif funct3 == 0x1: res = val_rs1 << (val_rs2 & 0x1F)
            elif funct3 == 0x2: res = 1 if self.sign_extend(val_rs1, 32) < self.sign_extend(val_rs2, 32) else 0 # SLT
            elif funct3 == 0x3: res = 1 if val_rs1 < val_rs2 else 0 # SLTU
            elif funct3 == 0x4: res = val_rs1 ^ val_rs2
            elif funct3 == 0x5: 
                res = self.sign_extend(val_rs1, 32) >> (val_rs2 & 0x1F) if funct7 == 0x20 else val_rs1 >> (val_rs2 & 0x1F) # SRA vs SRL
            elif funct3 == 0x6: res = val_rs1 | val_rs2
            elif funct3 == 0x7: res = val_rs1 & val_rs2
            else: res = 0
            
            res = write_rd(res)
            trace_str += f"R-Type | x{rd:02d} = 0x{res:08x}"
            
        elif opcode == 0x13: # I-type ALU instructions
            imm = self.sign_extend(inst >> 20, 12)
            imm_unsigned = imm & 0xFFFFFFFF
            
            if funct3 == 0x0: res = val_rs1 + imm_unsigned # ADDI
            elif funct3 == 0x2: res = 1 if self.sign_extend(val_rs1, 32) < self.sign_extend(imm_unsigned & 0xFFF, 12) else 0 # SLTI
            elif funct3 == 0x3: res = 1 if val_rs1 < imm_unsigned else 0 # SLTIU
            elif funct3 == 0x4: res = val_rs1 ^ imm_unsigned # XORI
            elif funct3 == 0x6: res = val_rs1 | imm_unsigned # ORI
            elif funct3 == 0x7: res = val_rs1 & imm_unsigned # ANDI
            elif funct3 == 0x1: res = val_rs1 << (imm_unsigned & 0x1F) # SLLI
            elif funct3 == 0x5: 
                res = self.sign_extend(val_rs1, 32) >> (imm_unsigned & 0x1F) if funct7 == 0x20 else val_rs1 >> (imm_unsigned & 0x1F) # SRAI vs SRLI
            else: res = 0
                
            res = write_rd(res)
            trace_str += f"I-Type | x{rd:02d} = 0x{res:08x}"
            if rd == 0 and imm == 0 and funct3 == 0:
                trace_str = f"PC: 0x{self.pc:08x} | Inst: 0x{inst:08x} | NOP"

        elif opcode == 0x23: # S-type (Store) instructions
            imm = self.sign_extend(((inst >> 25) << 5) | ((inst >> 7) & 0x1F), 12)
            addr = (val_rs1 + imm) & 0xFFFFFFFF
            size = 2 if funct3 == 2 else (1 if funct3 == 1 else 0)
            self.write_mem(addr, size, val_rs2)
            trace_str += f"STORE  | M[0x{addr:08x}] = 0x{val_rs2:08x}"

        elif opcode == 0x03: # Load instructions
            imm = self.sign_extend(inst >> 20, 12)
            addr = (val_rs1 + imm) & 0xFFFFFFFF
            size = 2 if funct3 == 2 else (1 if funct3 == 1 else 0)
            val = self.read_mem(addr, size)
            
            if funct3 == 0: val = self.sign_extend(val, 8) 
            elif funct3 == 1: val = self.sign_extend(val, 16)
                
            res = write_rd(val)
            trace_str += f"LOAD   | x{rd:02d} = M[0x{addr:08x}] (0x{res:08x})"

        elif opcode == 0x63: # B-type (Branch) instructions
            imm = self.sign_extend(((inst >> 31) << 12) | (((inst >> 7) & 1) << 11) | (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1), 13)
            
            taken = False
            if funct3 == 0x0: taken = (val_rs1 == val_rs2) # BEQ
            elif funct3 == 0x1: taken = (val_rs1 != val_rs2) # BNE
            elif funct3 == 0x4: taken = (self.sign_extend(val_rs1, 32) < self.sign_extend(val_rs2, 32)) # BLT 
            elif funct3 == 0x5: taken = (self.sign_extend(val_rs1, 32) >= self.sign_extend(val_rs2, 32)) # BGE 
            elif funct3 == 0x6: taken = (val_rs1 < val_rs2) # BLTU
            elif funct3 == 0x7: taken = (val_rs1 >= val_rs2) # BGEU
            
            if taken:
                pc_next = (self.pc + imm) & 0xFFFFFFFF
            trace_str += f"BRANCH | Taken: {taken} | Target: 0x{pc_next:08x}"
            if taken and pc_next == self.pc:
                self.halted = True # Graceful Halt
                trace_str += " (HALTING on infinite loop block)"

        elif opcode == 0x37: # LUI Instruction
            imm = inst & 0xFFFFF000
            res = write_rd(imm)
            trace_str += f"LUI    | x{rd:02d} = 0x{res:08x}"

        elif opcode == 0x17: # AUIPC Instruction
            imm = inst & 0xFFFFF000
            res = write_rd(self.pc + imm)
            trace_str += f"AUIPC  | x{rd:02d} = 0x{res:08x}"

        elif opcode == 0x6F: # JAL Instruction
            imm = self.sign_extend(((inst >> 31) << 20) | (((inst >> 12) & 0xFF) << 12) | (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1), 21)
            res = write_rd(self.pc + 4)
            pc_next = (self.pc + imm) & 0xFFFFFFFF
            trace_str += f"JAL    | x{rd:02d} = 0x{res:08x} | Target: 0x{pc_next:08x}"
            if pc_next == self.pc:
                self.halted = True # Graceful Halt

        elif opcode == 0x67: # JALR Instruction
            imm = self.sign_extend(inst >> 20, 12)
            res = write_rd(self.pc + 4)
            pc_next = (val_rs1 + imm) & 0xFFFFFFFE
            trace_str += f"JALR   | x{rd:02d} = 0x{res:08x} | Target: 0x{pc_next:08x}"
            if pc_next == self.pc:
                self.halted = True # Graceful Halt

        else:
            trace_str += f"UNKNOWN OPCODE 0x{opcode:x}"
            self.halted = True

        if self.trace_enabled:
            print(trace_str)
            
        self.pc = pc_next
        return True

    def run(self, max_cycles=1000):
        print("--- Starting RISC-V Python Reference Model Execution ---")
        cycle = 0
        while not self.halted and cycle < max_cycles:
            self.execute_step()
            cycle += 1
        print(f"--- Execution Complete ({cycle} cycles) ---")
        print(f"Final PC: 0x{self.pc:08x}")


if __name__ == '__main__':
    model = RISCVModel(trace_enabled=True)

    # Filter out Jupyter kernel files if accidentally passed by the environment
    args = [a for a in sys.argv[1:] if not a.endswith('.json')]

    # Handle command-line arguments properly
    if len(args) > 1 and args[0] == "-f":
        hex_file = args[1]
    elif len(args) > 0:
        hex_file = args[0]
    else:
        hex_file = "instruction.hex"

    # Check if file exists
    if not os.path.exists(hex_file):
        # Fallback for Jupyter environment where file paths might be different
        if os.path.exists("verification_suite.hex"):
            hex_file = "verification_suite.hex"
        else:
            print(f"Error: Could not find '{hex_file}'. Please place hex in the same directory.")
            sys.exit(1)

    print(f"Loading '{hex_file}'...")
    model.load_hex(hex_file)

    # Start simulation
    model.run(max_cycles=300)

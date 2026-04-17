# SERV HARDWARE QUIRKS
## Everything that will burn you when hooking into the WASM simulation

> **Scope**: SERV `serv_rf_top` synthesized via Yosys CXXRTL, driven from JavaScript.
> Every claim below is traceable to a specific RTL file and line.
> "You might expect X" means any reasonable RISC-V programmer would expect X.
> "SERV actually does Y" means the RTL proves otherwise.

---

## 1. ILLEGAL INSTRUCTIONS EXECUTE SILENTLY

**You might expect**: An illegal instruction (e.g. `0xFFFFFFFF`) causes a trap with mcause=2.

**SERV actually does**: Nothing. It executes the instruction as undefined garbage and continues. No trap. No mcause update. Execution proceeds to the next fetch.

**Why**: `serv_decode.v` contains zero validity checking. It is a pure combinational decode of opcode/funct3 bits. The README states explicitly: *"Many logic expressions are hand-optimized... and shamelessly take advantage of the fact that some opcodes aren't supposed to appear."* There is no `illegal` signal anywhere in the design.

**Consequence for testing**: Do NOT write tests expecting mcause=2 from bad encodings. SERV will silently misexecute and your test will hang or read garbage.

---

## 2. EBREAK IN THE POST-MRET INSTRUCTION STREAM RE-TRAPS

**You might expect**: After a trap handler does `mret`, the CPU returns to the saved mepc and continues normally. If you use `ebreak` as a halt sentinel after some stores, it just halts.

**SERV actually does**: If `ebreak` appears at a PC that is reachable after `mret`, and `mtvec` is still set to a live handler, the `ebreak` fires the handler **again**. The handler runs a second time, potentially overwriting your results.

**Why**: `ebreak` has `i_e_op=1` and `i_ebreak=1` from `serv_decode.v` (`wire co_ebreak = op20`; `wire co_e_op = opcode[4] & opcode[2] & !op21 & !(|funct3)`). `o_ctrl_trap = WITH_CSR & (i_e_op | i_new_irq | misalign_trap_sync)` from `serv_state.v`. Any `ebreak` anywhere in the instruction stream, as long as `mtvec` points somewhere valid, will trap.

**Consequence for testing**: Never use `ebreak` as a halt instruction in the fallthrough path after `mret`. Use NOPs, an infinite loop (`j .`), or place the halt `ebreak` at a PC the handler explicitly avoids by setting mepc past it.

**The safe pattern**:
```asm
ecall                    # byte 8: causes trap
addi a1, zero, 42        # byte 12: executes after mret (mepc set to here)
sw a1, 256(zero)         # byte 16
j halt                   # byte 20: jump to halt
...nops...
handler:
  addi a3, zero, 12
  csrrw zero, 0x341, a3  # mepc = 12
  mret
halt:
  ebreak                 # safe: handler is never re-entered from here
                         # because mret went to byte 12, not here
```

---

**Quirk #2b: THE HALT COUNTDOWN RACES WITH TRAP HANDLER EXECUTION**

The JS driver detects ebreak on **fetch** and immediately starts a countdown (`halted = 400`). SERV then spends the next ~105–139 cycles completing the trap sequence before the handler's first store executes. If the countdown expires before that store, results are lost.

Measured deltas in our WASM simulation:

- ecall/ebreak fetch → handler first fetch: **35 cycles**
- ecall/ebreak fetch → first store inside handler: **105 cycles** (35 + 2 instructions × 35 cycles)
- misalign fetch → handler first fetch: **69 cycles**
- misalign fetch → first store inside handler: **139 cycles** (69 + 2 instructions × 35 cycles)


**The safe pattern**: never use `ebreak` as a halt sentinel in any test where mtvec is live. Use `j halt` (infinite loop) instead. `run_cycles` times out naturally, and results are already in memory before the loop starts. The only safe use of `ebreak` as halt is in tests that never write mtvec.

**Why misalign costs more**: `misalign_trap_sync_r` persists across a full instruction fetch boundary before firing. ecall/ebreak trap directly via `i_e_op` with no such delay.

**RTL root**: `o_ctrl_trap = WITH_CSR & (i_e_op | i_new_irq | misalign_trap_sync)` — any ebreak anywhere in the instruction stream unconditionally asserts `o_ctrl_trap` with no MIE check and no "already in handler" guard.

---

## 3. TIMER IRQ IS EDGE-TRIGGERED, NOT LEVEL-TRIGGERED

**You might expect**: Holding `timer_irq` high will continuously retrigger interrupts.

**SERV actually does**: The interrupt fires exactly once per low→high transition. A sustained high signal after the first IRQ is handled will NOT re-trigger.

**Why**: `serv_csr.v`:
```verilog
always @(posedge i_clk) begin
  if (i_trig_irq) begin
    timer_irq_r <= timer_irq;
    o_new_irq   <= timer_irq & !timer_irq_r;  // edge detect
  end
end
```
`o_new_irq` is true only when `timer_irq=1` AND previous sampled value was `0`. The `i_trig_irq` sampling gate is `wb_ibus_ack` — it samples on every instruction fetch acknowledgment.

**Consequence for testing**: In the JS driver, `run_with_timer_irq(assert_at, max_cycles)` asserts the signal at cycle `assert_at` and holds it high. The IRQ will fire once. To fire it again you must deassert and reassert. If you want to test "IRQ not taken", assert it late enough that the program has already halted.

**Additional**: A timer IRQ that goes high and low again **between** two instruction fetches is missed entirely — it is never sampled. Only edges that straddle an `ibus_ack` cycle are detected. `run_with_timer_irq(assert_at, ...)` must assert the signal early enough to be seen during an ibus_ack cycle.

---

## 4. JALR CLEARS THE LSB OF THE TARGET ADDRESS

**You might expect**: `jalr ra, a0, 1` where a0=8 jumps to address 9.

**SERV actually does**: Jumps to address 8. The LSB is unconditionally cleared.

**Why**: `serv_ctrl.v`:
```verilog
assign pc_plus_offset_aligned[0] = pc_plus_offset[0] & !i_cnt0;
```
`i_cnt0` is high during counter cycle 0, which processes bit 0 of the address. `& !i_cnt0` unconditionally forces bit 0 to zero at that cycle. `pc_plus_offset_aligned` is the path used by JAL, JALR, and branches — all of them. The LSB is cleared at the ctrl level for every jump target without exception.

**Consequence**: Any odd target address fed to JALR gets rounded down to even. This matches the RISC-V spec but surprises people who forget it.

---

## 5. UNIMPLEMENTED CSRs READ BACK RF RAM GARBAGE, NOT ZERO

**You might expect**: Reading an unimplemented CSR like `mvendorid` (0xF11) or `mhartid` (0xF14) returns 0.

**SERV actually does**: Returns whatever happens to be in the RF RAM slot that the address partially decodes to.

**Why**: `serv_decode.v` maps CSR addresses using only bits 26, 21, 20:
```verilog
wire csr_valid = op20 | (op26 & !op21);
wire co_csr_addr = {op26 & op20, !op26 | op21};
```
Address 0xF11 has op26=1, op21=1, op20=1 → `csr_valid=1`, `csr_addr=11` (mtval slot). So writing 0xF11 actually writes mtval (RF[35]), and reading it back returns whatever is in mtval. It is NOT silently ignored and NOT zero.

**The only CSRs SERV actually implements**:
| Address | Name | Storage | csr_addr |
|---------|------|---------|----------|
| 0x300 | mstatus | serv_csr.v FFs | (direct) |
| 0x304 | mie | serv_csr.v FF | (direct) |
| 0x305 | mtvec | RF[33] | 01 |
| 0x340 | mscratch | RF[32] | 00 |
| 0x341 | mepc | RF[34] | 10 |
| 0x342 | mcause | serv_csr.v FFs | (direct) |
| 0x343 | mtval | RF[35] | 11 |

Any other CSR address partially aliases into one of these seven. Never rely on unimplemented CSR reads returning 0.

---

## 6. MISALIGNED ACCESSES TRAP — mcause=4 (LOAD) OR mcause=6 (STORE)

**You might expect**: Misaligned accesses either silently do something wrong or are not implemented.

**SERV actually does**: Traps with a precise mcause. The faulting address is written to mtval.

**Why**: `serv_mem_if.v`:
```verilog
assign o_misalign = WITH_CSR & ((i_lsb[0] & (i_word | i_half)) | (i_lsb[1] & i_word));
```
Exact misalign conditions:
| Access | Address LSBs | Misalign? |
|--------|-------------|-----------|
| LB/SB | any | Never |
| LH/SH | `01` or `11` | Yes (lsb[0]=1 & half) |
| LW/SW | `01`, `10`, or `11` | Yes |
| LW/SW | `00` | Never |

`serv_state.v` routes `i_mem_misalign` through `trap_pending` → `misalign_trap_sync_r` → `o_ctrl_trap`. The mcause encoding from `serv_csr.v` truth table: load misalign (`i_mem_op=1, i_mem_cmd=0`) → mcause=4; store misalign (`i_mem_op=1, i_mem_cmd=1`) → mcause=6.

Critically: **`o_dbus_cyc` is gated by `!i_mem_misalign`**. A misaligned access produces NO data bus transaction at all. The memory is never touched. The trap fires directly.

**mtval gets the faulting address**: `serv_rf_if.v`: `wire [B:0] mtval = i_mtval_pc ? i_bad_pc : i_bufreg_q`. For data misalign, `i_mtval_pc=0` so mtval = `bufreg_q` = the computed (misaligned) effective address.

**Additional**: `misalign_trap_sync_r` persists across the instruction fetch boundary:
```verilog
misalign_trap_sync_r <= !(i_ibus_ack | i_rst) &
    ((trap_pending & o_init) | misalign_trap_sync_r);
```
This register stays set until the next `ibus_ack` clears it. Even if misalignment is detected at the very last cycle of init, the trap will still fire at the start of the next instruction slot. This is why misalign traps have a higher cycle cost than ecall/ebreak.

---

## 7. THE RF RAM IS 2 BITS WIDE — RECONSTRUCTING REGISTERS FROM dump_rfram()

**You might expect**: `dump_rfram(i)` gives you a 32-bit register value at index `i`.

**SERV actually does**: Returns a 2-bit chunk. Each 32-bit register is stored across 16 consecutive 2-bit entries.

**Why**: `serv_rf_top.v`: `parameter RF_WIDTH = W * 2 = 2`. `serv_rf_ram.v`: `parameter depth = 32*(32+csr_regs)/width = 32*36/2 = 576`.

**RF memory layout** (for W=1, RF_WIDTH=2):
```
RF word index = register_number * 16 + bit_pair_index

GPR x0:  RF[0]   .. RF[15]   (bits [1:0], [3:2], ..., [31:30])
GPR x1:  RF[16]  .. RF[31]
...
GPR x31: RF[496] .. RF[511]
mscratch:RF[512] .. RF[527]   (reg 32)
mtvec:   RF[528] .. RF[543]   (reg 33)
mepc:    RF[544] .. RF[559]   (reg 34)
mtval:   RF[560] .. RF[575]   (reg 35)
```

**To reconstruct a full 32-bit register value in JS**:
```javascript
function readReg(cpu, regNum) {
    let val = 0;
    const base = regNum * 16;
    for (let i = 0; i < 16; i++) {
        const chunk = cpu.dump_rfram(base + i) & 0x3; // 2 bits
        val |= (chunk << (i * 2));
    }
    return val >>> 0;
}
// readReg(cpu, 10)  → a0
// readReg(cpu, 33)  → mtvec (RF reg 33)
```

Note: x0 is gated to zero by `serv_rf_ram.v`'s `regzero` logic, so `readReg(cpu, 0)` will always return 0 regardless of what's in RF[0..15].

**Additional**: When `i_ren=0`, the RAM output is explicitly `X` (undefined). In CXXRTL it will hold the last value — `dump_rfram()` after a read with `ren=0` returns stale data, not zero. Also, `regzero` is registered (one cycle delay): the x0 zero-gating applies to the **next** cycle's output after the address is presented. Both the data and the zero gate are registered with the same latency, so the net behavior is correct, but you cannot speculatively read x0 and expect zero in the same cycle.

---

## 8. mstatus, mie, mcause ARE NOT IN THE RF RAM

**You might expect**: You can inspect mstatus/mie/mcause via `dump_rfram()`.

**SERV actually does**: These three CSRs live as individual flip-flops inside `serv_csr.v`, not in the RF RAM. They are NOT accessible via `dump_rfram()`.

**The split**:
| CSR | Storage | Inspectable via dump_rfram? |
|-----|---------|---------------------------|
| mstatus | FFs in serv_csr | No — read via `csrr` + SW |
| mie | FF in serv_csr | No |
| mcause | FFs in serv_csr | No |
| mtvec | RF[528..543] | Yes, via readReg(cpu,33) |
| mscratch | RF[512..527] | Yes, via readReg(cpu,32) |
| mepc | RF[544..559] | Yes, via readReg(cpu,34) |
| mtval | RF[560..575] | Yes, via readReg(cpu,35) |

The only way to read mstatus/mie/mcause from JS is to run a program that reads them with `csrr` and stores the result to memory, then read memory with `read_mem()`.

**Additional — mie only exposes bit 7 (MTIE)**: Writing `0xFFFFFFFF` to mie (0x304) stores only `mie_mtie` (bit 7). All other bits read back as zero. `csrw mie, 0xFF` expecting to enable multiple interrupt sources will not work — SERV has one interrupt source and one interrupt enable bit.

**Additional — mcause bit 31 is software-writable**: `if (i_mcause_en & i_cnt_done | i_trap) mcause31 <= i_trap ? o_new_irq : csr_in[B]`. Software can set or clear bit 31 via CSRRW. It has no practical use but can confuse inspection after a software write.

---

## 9. mstatus ONLY EXPOSES MIE (bit 3) AND MPIE (bit 7) — MPIE IS NOT SOFTWARE-READABLE

**You might expect**: Writing a value to mstatus and reading it back returns the same value.

**SERV actually does**: Only bit 3 (MIE) is readable. Bit 7 (MPIE) is stored internally but **intentionally not readable or writable from software**.

**Why**: `serv_csr.v`:
```verilog
// Note: To save resources mstatus_mpie (mstatus bit 7) is not
// readable or writable from sw
if (i_trap & i_cnt_done)
    mstatus_mpie <= mstatus_mie;
```
MPIE is only updated on trap entry and only read internally during `mret` to restore MIE. The `mstatus` wire output only drives bit 3 and bits 11-12 (hardwired for M-mode). All other bits read as 0.

**Consequence**: `csrrw a0, 0x300, a1` where a1=0xFF will write 0xFF but reading back gives only `(a1 & 0x8)`. Don't try to use mstatus as general-purpose storage.

---

## 10. THE mcause ENCODING IS HAND-COMPUTED FROM A TRUTH TABLE

**You might expect**: mcause is set by a simple case statement.

**SERV actually does**: Computes mcause bits via a 4-bit combinational truth table optimized for minimal LUTs. The four lowest bits are set based on this exact table (from `serv_csr.v` comments):

```
irq   => 0111  (timer = 7)
e_op  => x011  (ebreak=3 when i_ebreak=1, ecall=11 when i_ebreak=0)
mem   => 01x0  (store=6 when i_mem_cmd=1, load=4 when i_mem_cmd=0)
ctrl  => 0000  (misaligned jump = 0)
```

Bit 31 (interrupt flag): set to 1 for timer IRQ, 0 for all exceptions.

**Consequence**: mcause values you can actually observe from SERV:

| Event | mcause |
|-------|--------|
| Misaligned jump | 0 |
| Misaligned load | 4 |
| Misaligned store | 6 |
| ebreak | 3 |
| ecall | 11 |
| Timer IRQ | 0x80000007 |

Nothing else. Not mcause=1 (instruction access fault), not mcause=2 (illegal instruction), not mcause=5/7 (load/store access fault). Those are architecturally defined but SERV never generates them.

---

## 11. MINIMUM INSTRUCTION CYCLE COST IS NOT WHAT YOU EXPECT

**You might expect**: A simple `addi` takes 32 cycles (one per bit, bit-serial).

**SERV actually does**: Every instruction costs more due to RF read latency and bus handshake:

| Phase | Cycles |
|-------|--------|
| Instruction fetch (ibus_cyc → ibus_ack) | 1 (our sim acks immediately) |
| RF read request → ready | 2 (rgnt = rreq_r delayed 2 cycles in serv_rf_ram_if.v) |
| Bit-serial execution (cnt=0..31) | 32 |
| **Single-stage op (addi, add, CSR, etc.)** | **35 cycles** |
| Two-stage op (shifts, branches, jumps) | 67 cycles |
| Memory op (load/store) | 68 cycles |
| ecall/ebreak trap entry (to handler fetch) | 35 cycles |
| Misalign trap entry (to handler fetch) | 69 cycles |

**Consequence**: Cycle budgets in tests must be generous. The gauntlet uses 100,000 cycles for simple tests and up to 400,000 for trap-heavy ones. These are conservative test budgets, not instruction latencies — see the CYCLE TIMING REFERENCE section for exact costs. If a test times out, double the budget before assuming a bug.

**Additional — RF write/read pipeline overlap**: `wcnt = rcnt - 4` — writes happen exactly 4 count ticks behind reads. There is a 4-cycle window where a register is being read for the current instruction while simultaneously being written with the result of the previous instruction. SERV's architecture guarantees these are always different registers. If you build an extension that violates this assumption, you get a silent read-before-write hazard.

**Additional — trap entry suppresses two-stage init**: If a timer IRQ arrives (`i_new_irq=1`) during the init phase of a two-stage operation (load/store/shift), `o_init` goes low immediately and the instruction is abandoned. The half-computed address in bufreg is discarded and the IRQ is taken correctly. No partial execution occurs.

---

## 12. THE BUS PROTOCOL: ACK MUST ONLY BE ASSERTED WHEN CYC IS HIGH

**You might expect**: You can assert `ibus_ack` or `dbus_ack` freely.

**SERV actually does**: Become "very confused" (direct quote from README) if you assert ack without cyc being high.

**Why**: The state machine in `serv_state.v` uses `i_ibus_ack` directly to clock `ibus_cyc`, trigger the RF read request, and advance the misalign sync register. Spurious acks desynchronize these state machines in ways that are nearly impossible to debug.

**Our JS driver does this correctly**: `bus_tick_traced()` only asserts ack when `dut.p_ibus_cyc` or `dut.p_dbus_cyc` is high respectively. Never change this.

**Additional — reset starts fetching immediately**: `ibus_cyc <= o_ctrl_pc_en | i_rst` — on reset, `ibus_cyc` goes high immediately via `i_rst`. The very first instruction fetch begins as soon as reset deasserts. There is no idle cycle.

---

## 13. dbus_adr IS ALWAYS WORD-ALIGNED — USE dbus_sel FOR BYTE OFFSET

**You might expect**: `sb a0, 257(zero)` puts address 257 on the data bus.

**SERV actually does**: Puts address 256 on the data bus and asserts `dbus_sel[1]` to indicate byte lane 1.

**Why**: `serv_bufreg.v`: `assign o_dbus_adr = {data[31:2], 2'b00}`. The bottom 2 bits are hardwired to zero. The actual byte offset within the word comes from `dbus_sel`:

```
dbus_sel[0] = byte 0 (bits 7:0)    ← lsb=00
dbus_sel[1] = byte 1 (bits 15:8)   ← lsb=01
dbus_sel[2] = byte 2 (bits 23:16)  ← lsb=10
dbus_sel[3] = byte 3 (bits 31:24)  ← lsb=11
```

For a halfword at lsb=10: sel=0b1100 (bytes 2 and 3).
For a word: sel=0b1111 always.

**Consequence for the JS sim**: The RAM driver in `bus_tick_traced()` uses `dbus_sel` to apply the byte mask correctly:
```javascript
if(sel&1) mask|=0x000000FFu;
if(sel&2) mask|=0x0000FF00u;
if(sel&4) mask|=0x00FF0000u;
if(sel&8) mask|=0xFF000000u;
ram[idx] = (ram[idx] & ~mask) | (dat & mask);
```
The data bus presents the value **pre-shifted to the correct byte lane position**. So for `sb a0, 257(zero)` where a0=0xAB: `dbus_dat = 0x0000AB00` and `dbus_sel = 0b0010`.

**Additional — `o_lsb` is only valid after the first two counter cycles of init**: `serv_mem_if.v`'s misalign check happens after init anyway so this is harmless in practice, but probing `o_lsb` early will return garbage. `o_wb_sel` is computed combinatorially from `i_lsb` and is valid as soon as lsb is valid — alternative drivers must use it to apply byte masks or every SB/SH will corrupt adjacent bytes.

**Additional — bufreg2 pre-shifts store data**: For a byte store at lsb=3 (byte address `xxx11`), the byte value gets shifted into bits [31:24] of `o_dbus_dat`. The JS driver's byte mask then writes only those bits. An alternative driver must not apply an additional shift on top of what bufreg2 already did.

---

## 14. THE ASSEMBLER HAS ONE CRITICAL SIGN-EXTENSION PITFALL WITH LUI+ADDI

**You might expect**: `lui a0, 0xAAAAA` + `addi a0, a0, 0xAAA` gives `0xAAAAAAAA`.

**SERV actually does**: Gives `0xAAAA9AAA` because `addi`'s 12-bit immediate `0xAAA` sign-extends to `-1366`, not `+2730`.

**Why**: LUI places `imm<<12` in the register. `addi` adds a sign-extended 12-bit value. `0xAAA = 0b101010101010` — bit 11 is 1, so it sign-extends to `0xFFFFFAAA = -1366`. Result: `0xAAAAA000 + (-1366) = 0xAAAA9AAA`.

**The fix**: When the low 12 bits have bit 11 set, add 1 to the LUI immediate to pre-compensate:
```asm
# Goal: a0 = 0xAAAAAAAA
lui  a0, 0xAAAAB      # 0xAAAAB000
addi a0, a0, 0xAAA   # + sign_ext(0xAAA) = -1366
                      # 0xAAAAB000 - 0x566 = 0xAAAAAAAA ✓
```

This affects any constant where the low 12 bits have bit 11 set. The pattern: if `(constant & 0x800)`, then LUI immediate = `(constant >> 12) + 1`.

**Additional — CSR immediates are zero-extended, not sign-extended**: `signbit = imm31 & !i_csr_imm_en` in `serv_immdec.v` — when `i_csr_imm_en=1`, signbit is forced to 0. So `csrrwi zero, 0x300, 0x1F` writes 31, not -1.

---

## 15. RESET DOES NOT CLEAR THE RF RAM UNLESS YOU DO IT MANUALLY

**You might expect**: Asserting `rst_n=0` clears all registers to zero.

**SERV actually does**: `RESET_STRATEGY="MINI"` only resets the minimum FFs needed to restart execution from RESET_PC. The RF RAM contents are **undefined after reset** unless explicitly cleared.

**Why**: `serv_rf_ram.v` only clears memory if `SERV_CLEAR_RAM` is defined at compile time (not set in our synthesis). The reset strategy only affects `serv_state.v` (`init_done`, `o_ctrl_jump`, `cnt_lsb`, `o_cnt`) and `serv_rf_ram_if.v` (`rgate`, `rgnt`, `rreq_r`, `rcnt`).

**Our JS driver handles this correctly**: `init_cpu()` explicitly zeros all 576 RF RAM entries:
```cpp
for(size_t i = 0; i < 576; i++)
    dut.memory_p_cpu_2e_rf__ram_2e_memory.data[i] = cxxrtl::value<2>{0u};
```
If you add a second WASM module or multiple `init_cpu()` calls, this zeroing must happen every time. Without it, registers will contain values from the previous test.

---

## 16. ALU CARRY AND COMPARISON INTERNALS

**serv_alu.v — carry reset between instructions**: `add_cy_r[0] <= i_en ? add_cy : i_sub`. When the counter is NOT running, the carry register resets to `i_sub`, not zero. SUB automatically gets carry-in=1 (two's complement). Probing `add_cy_r` mid-instruction will show a non-zero carry at cycle 0 for SUB.

**serv_alu.v — BEQ/BNE comparison spans all 32 cycles**: `result_eq = !(|result_add) & (cmp_r | i_cnt0)`. The equality comparator is an AND-accumulator. `cmp_r` starts false and only goes true if ALL bits so far have matched — the result is only valid at cnt=31. BEQ/BNE results are not available early.

**serv_alu.v — boolean output is zeroed during shifts**: `result_bool` with `i_bool_op=01` outputs zero by design during shift operations so that `i_buf` passes through uncontaminated. Probing the boolean output during a shift will show zeros; this is not a bug.

---

## 17. BUFREG ADDRESS ACCUMULATION

**serv_bufreg.v — carry chain resets on `i_en=0`**: `c_r[0] <= c & i_en`. The rs1+imm adder carry chain resets between instructions. If `i_en` drops mid-accumulation (abnormal; requires bus interference), the carry is lost and the computed address is wrong.

**serv_bufreg.v — `o_lsb` comes from the shift register**: Bits 1:0 are loaded during `i_cnt0 | i_cnt1` of init. `o_lsb` is only valid after those first two counter cycles. Misalign detection in `serv_mem_if.v` happens after init completes, so this is safe architecturally.

**serv_bufreg.v — `o_ext_rs1` exposes full bufreg to extension port**: When MDU=0 this wire is unused. When adding MDU support, rs1 is valid in the data register after the init phase completes.

---

## 18. RF INTERFACE PRIORITY AND WRITE SUPPRESSION

**serv_rf_if.v — `o_rreg1` mux priority**: `sel_rs2 = !(i_trap | i_mret | i_csr_en)`. Priority is: trap > mret > csr_en > rs2. If both `i_csr_en` and `i_trap` are asserted simultaneously (architecturally impossible but possible in a buggy extension), trap wins and mtvec is read instead of the CSR address.

**serv_rf_if.v — x0 write suppression is here, not in rf_ram**: `rd_wen = i_rd_wen & (|i_rd_waddr)`. Writes to x0 are suppressed in `rf_if` by checking that rd_addr is non-zero. The RAM still receives a write strobe at address 0, but because `rd_wen=0` and trap writes go to address 35, no spurious write to RF[0] occurs.

**serv_rf_if.v — CSR read is gated**: `o_csr = i_rdata1 & {W{i_csr_en}}`. During non-CSR instructions `o_csr=0`, which is correct since `i_rf_csr_out` in `serv_csr.v` is only consumed when CSR enables are active.

---

## 19. RF RAM WRITE PIPELINE — PARTIAL-WRITE SAFETY

**serv_rf_ram_if.v — write data shifts in serially**: `wdata0_r <= {i_wdata0, wdata0_r[width-1:W]}`. The full 32-bit result assembles in `wdata0_r` over 32 cycles. `o_wen` is only asserted at `wtrig0`/`wtrig1` after the full shift completes. A hypothetical partial write (abnormal) would produce a corrupted result because only the bits shifted so far would be correct.

**serv_rf_ram_if.v — write transactions get `o_ready` immediately**: `o_ready = rgnt | i_wreq`. A write-only transaction (e.g. trap writing mepc+mtval without needing new register reads) gets ready asserted immediately via the `i_wreq` path, not the 2-cycle `rgnt` path. Trap entry is therefore faster than normal instruction dispatch from an RF-handshake perspective.

---

## 20. SIGN EXTENSION DURING LOADS

**serv_bufreg2.v / serv_mem_if.v — signbit capture timing**: For `LB`, `dat_valid=1` only at `bytecnt=00`, so `signbit` is latched from byte 0 and held for the three remaining byte-counts where sign extension applies. For `LH` at lsb=10 (upper halfword), `dat_valid=1` for `bytecnt=00` and `bytecnt=01`; during the false cycles `o_rd` outputs `{W{i_signed & signbit}}`. Sign extension is correct only if `signbit` was latched from the correct (last valid) byte.

**serv_bufreg2.v — shift-by-zero identity is correct**: Confirmed by tests #27 and #28. The internal counter mechanism that achieves this is implementation-internal and not fully traced here.

---

## 21. CXXRTL `/*outline*/` SIGNALS ARE ALWAYS STALE AFTER `step()`

**You might expect**: Reading `p_cpu_2e_rf__ram__if_2e_wcnt.data[0]` after `step()` gives the current wcnt value.

**SERV actually does**: Returns 0. Always. Regardless of the actual circuit state.

**Why**: CXXRTL marks combinatorial signals as `/*outline*/` and evaluates them lazily. After `step()` returns, outline signals hold their last explicitly-evaluated value — which for most combinatorial wires is 0 from initialization. They are not re-evaluated unless something downstream forces evaluation.

**The three signals that will burn you**:
- `p_cpu_2e_rf__ram__if_2e_wcnt` — always reads 0. Compute as `rcnt - 4` in JS instead.
- `p_cpu_2e_cpu_2e_state_2e_o__cnt__en` — always reads 0. Use `cnt_lsb != 0` as proxy.
- `p_cpu_2e_cpu_2e_rf__if_2e_o__wen1` — always reads 0. Use `wen1_r.curr` instead.

**The rule**: If the CXXRTL declaration contains `/*outline*/`, do not read it after `step()`. Only read signals declared as `wire<N>` via `.curr.data[0]`. This is not a SERV quirk — it is a CXXRTL backend behavior that affects every design synthesized through Yosys CXXRTL.

---

## QUICK REFERENCE: JS API

```javascript
// Load a program (word-indexed, not byte-indexed)
cpu.load_inst(wordIndex, encodedWord32);
// word 0 = byte address 0, word 1 = byte address 4, etc.

// Read memory (same word-indexed scheme)
cpu.read_mem(wordIndex);
// word 64 = byte address 256 (the conventional test data area)

// Run
cpu.run_cycles(maxCycles);           // normal execution
cpu.run_with_timer_irq(assertAt, max); // asserts timer_irq from cycle assertAt onward

// Bus trace (call run_traced first)
const len = cpu.run_traced(nCycles); // returns number of trace words
// Trace format: 6 words per event
// [0] cycle number
// [1] ibus_adr (0xFFFFFFFF if no fetch this cycle)
// [2] instruction word fetched
// [3] dbus_adr (0xFFFFFFFF if no data bus this cycle)
// [4] dbus_dat | (dbus_we << 31)
// [5] opcode[6:0] | (funct3 << 8)
cpu.get_trace_word(i);

// RF RAM inspection (2-bit chunks)
cpu.dump_rfram(i); // i in [0,575], returns 2-bit value
// Reconstruct full register: 16 chunks per register, LSB-first

// Signal flags (checked after run)
// bit 8: ibus_adr was not word-aligned at some point (should never happen)
// bit 9: dbus_adr was not word-aligned at some point (should never happen)
cpu.get_flags();
```

---

## QUICK REFERENCE: CYCLE BUDGETS

| Instruction class | Safe cycle budget | Actual cost (exact) |
|-----------------|-----------------|-------------------|
| ALU (addi, add, xor, etc.) | 100,000 | 35 cycles |
| Shifts | 100,000 | 67 cycles |
| Loads / Stores | 100,000 | 68 cycles |
| Branches / Jumps | 100,000 | 67 cycles |
| CSR access | 100,000 | 35 cycles |
| Single trap (ecall/ebreak) + mret | 200,000 | 35 + N×35 + 35 cycles |
| Trap with handler stores | 300,000 | 69 + N×35 + 35 cycles (misalign worst case) |
| Nested sequences (trap-in-loop etc.) | 500,000 | program-dependent, use CYCLE TIMING REFERENCE |
| Timer IRQ (needs cycles to reach assert point) | 400,000 | 35 cycles from last wait fetch to handler |


These are conservative test budgets, not instruction latencies. For exact cycle costs per instruction, see the CYCLE TIMING REFERENCE section. When a test fails unexpectedly, triple the cycle budget before investigating logic — SERV's bit-serial nature means some sequences take far longer than intuition suggests.


---

## CYCLE TIMING REFERENCE (Measured from synthesized hardware)

All values measured fetch-to-fetch via cycle-accurate bus trace on the CXXRTL WASM simulation. These are exact, not estimates.

**Single-stage instructions** (35 cycles each):
addi, add, sub, and, or, xor, lui, auipc, slt, sltu, slti, sltiu, all CSR instructions (RF-backed and FF-backed), ecall, ebreak, mret

**Two-stage instructions** (67 cycles each):
slli, srli, srai, sll, srl, sra, beq, bne, blt, bge, bltu, bgeu, jal, jalr

**Memory instructions** (68 cycles each):
sw, sh, sb, lw, lh, lb, lbu, lhu

**Trap entry latency** (fetch-to-handler-first-fetch):
- ecall/ebreak: **35 cycles**
- misaligned load/store: **69 cycles**

**Trap entry to first store inside handler:**
- ecall/ebreak + N single-stage instructions: 35 + N×35 cycles
- misalign + N single-stage instructions: 69 + N×35 cycles

**Practical consequence for the halted countdown:**
The driver's `halted=400` countdown starts on ebreak fetch. Any handler with up to 10 single-stage instructions before its critical store (35 + 10×35 = 385 cycles) completes safely within the countdown. Handlers deeper than that risk the countdown expiring before results are written.

**Deriving any sequence's cycle budget:**
Sum the cost of each instruction in order. For trap handlers, add the trap entry latency first. For loops, multiply the per-iteration cost by iteration count. These numbers are exact for this simulation — real silicon timing will differ based on clock frequency and bus latency.


// My personal favourite one: Make sure your JS is able to instaniate the memory it thinks its instantiating, because this is baremetal, 
// will harden this later on but until i can impelment a state of the art memory manager, don't go around instantiating 4GB+ hotswap RAM unless you know what you're doing!

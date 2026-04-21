\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // ==============================================================================
   // JTAG TAP CONTROLLER SIMULATION
   // ==============================================================================
   
   |jtag
      @1
         $reset = *reset;
         
         // TCK: The fundamental JTAG clock. Runs at half the frequency of the simulation cyc_cnt.
         // Rising edge: Samples TMS and TDI. Updates State. Shifts Registers.
         // Falling edge: Updates TDO.
         $tck = *cyc_cnt[0];
         $tck_rising  = ($tck && !(>>1$tck));
         $tck_falling = (!$tck && (>>1$tck));
         
         // Synthetic Stimulus sequence spanning ~60 cyc_cnt ticks (30 TCK cycles)
         // Cycle index here roughly corresponds to TCK cycles
         $seq_idx[7:0] = {1'b0, *cyc_cnt[7:1]}; 
         
         $tms = ($seq_idx < 5)   ? 1'b1 :  // Reset sequence
                ($seq_idx == 5)  ? 1'b0 :  // Run-Test/Idle
                ($seq_idx == 6)  ? 1'b1 :  // Select-DR
                ($seq_idx == 7)  ? 1'b1 :  // Select-IR
                ($seq_idx == 8)  ? 1'b0 :  // Capture-IR
                ($seq_idx == 9)  ? 1'b0 :  // Shift-IR
                ($seq_idx < 14)  ? 1'b0 :  // (stay in Shift-IR for 4 bits)
                ($seq_idx == 14) ? 1'b1 :  // Exit1-IR
                ($seq_idx == 15) ? 1'b1 :  // Update-IR
                ($seq_idx == 16) ? 1'b1 :  // Select-DR
                ($seq_idx == 17) ? 1'b0 :  // Capture-DR
                ($seq_idx == 18) ? 1'b0 :  // Shift-DR
                ($seq_idx < 28)  ? 1'b0 :  // (stay in Shift-DR)
                1'b1;                      // Return to reset
                
         // Simple alternating 0/1 pattern on TDI, stable across TCK rising edge
         $tdi = (*cyc_cnt[2]); 
         
         // -------------------------------------------------------------
         // FSM STATE TRANSITIONS (Only evaluate on TCK rising edge)
         // -------------------------------------------------------------
         $state[3:0] = 
            $reset ? 4'd0 :
            !$tck_rising ? >>1$state : 
            (>>1$state == 4'd0)  ? ($tms ? 4'd0 : 4'd1)  : // Reset
            (>>1$state == 4'd1)  ? ($tms ? 4'd2 : 4'd1)  : // Run-Test
            (>>1$state == 4'd2)  ? ($tms ? 4'd9 : 4'd3)  : // Sel-DR
            (>>1$state == 4'd3)  ? ($tms ? 4'd5 : 4'd4)  : // Cap-DR
            (>>1$state == 4'd4)  ? ($tms ? 4'd5 : 4'd4)  : // Shift-DR
            (>>1$state == 4'd5)  ? ($tms ? 4'd8 : 4'd6)  : // Ex1-DR
            (>>1$state == 4'd6)  ? ($tms ? 4'd7 : 4'd6)  : // Pause-DR
            (>>1$state == 4'd7)  ? ($tms ? 4'd8 : 4'd4)  : // Ex2-DR
            (>>1$state == 4'd8)  ? ($tms ? 4'd2 : 4'd1)  : // Upd-DR
            (>>1$state == 4'd9)  ? ($tms ? 4'd0 : 4'd10) : // Sel-IR
            (>>1$state == 4'd10) ? ($tms ? 4'd12 : 4'd11) : // Cap-IR
            (>>1$state == 4'd11) ? ($tms ? 4'd12 : 4'd11) : // Shift-IR
            (>>1$state == 4'd12) ? ($tms ? 4'd15 : 4'd13) : // Ex1-IR
            (>>1$state == 4'd13) ? ($tms ? 4'd14 : 4'd13) : // Pause-IR
            (>>1$state == 4'd14) ? ($tms ? 4'd15 : 4'd11) : // Ex2-IR
            (>>1$state == 4'd15) ? ($tms ? 4'd2 : 4'd1)  : // Upd-IR
            4'd0;

         $shift_ir = ($state == 4'd11);
         $upd_ir   = ($state == 4'd15);
         $cap_dr   = ($state == 4'd3);
         $shift_dr = ($state == 4'd4);
         
         // -------------------------------------------------------------
         // INSTRUCTION REGISTER (IR) - 4 bits
         // -------------------------------------------------------------
         $ir_shift_next[3:0] = 
            $reset    ? 4'd1 :           // Default IDCODE inst
            $shift_ir ? {$tdi, >>1$ir_shift[3:1]} : 
            >>1$ir_shift;
            
         $ir_shift[3:0] = $tck_rising ? $ir_shift_next : >>1$ir_shift;
            
         $ir_reg_next[3:0] = 
            $reset  ? 4'd1 :
            $upd_ir ? >>1$ir_shift : 
            >>1$ir_reg;
            
         $ir_reg[3:0] = $tck_falling ? $ir_reg_next : >>1$ir_reg;
            
         $inst_bypass = ($ir_reg == 4'hF);
         $inst_idcode = ($ir_reg == 4'h1);

         // -------------------------------------------------------------
         // DATA REGISTERS (DR)
         // -------------------------------------------------------------
         $idcode_val[31:0] = 32'h14B3B093; 
         
         $idcode_sr_next[31:0] = 
            ($cap_dr && $inst_idcode)   ? $idcode_val :
            ($shift_dr && $inst_idcode) ? {$tdi, >>1$idcode_sr[31:1]} :
            >>1$idcode_sr;
            
         $idcode_sr[31:0] = $tck_rising ? $idcode_sr_next : >>1$idcode_sr;
            
         $bypass_sr_next = 
            ($cap_dr && $inst_bypass)   ? 1'b0 :
            ($shift_dr && $inst_bypass) ? $tdi :
            >>1$bypass_sr;
            
         $bypass_sr = $tck_rising ? $bypass_sr_next : >>1$bypass_sr;
            
         // -------------------------------------------------------------
         // TDO MULTIPLEXER (Updated on Falling Edge)
         // -------------------------------------------------------------
         $ir_shift_d[3:0]   = >>1$ir_shift;
         $idcode_sr_d[31:0] = >>1$idcode_sr;
         $bypass_sr_d       = >>1$bypass_sr;
         
         $tdo_internal = 
            $shift_ir ? $ir_shift_d[0] :
            $shift_dr ? (
               $inst_bypass ? $bypass_sr_d :
               $inst_idcode ? $idcode_sr_d[0] : 1'b0
            ) : 1'b0;
            
         $tdo = $tck_falling ? $tdo_internal : >>1$tdo;
            
         `BOGUS_USE($tdo)

   *passed = *cyc_cnt > 70; // Ensures enough cyc_cnt ticks for the full sequence
   *failed = 1'b0;

   // ==============================================================================
   // VISUALIZER
   // ==============================================================================
   /viz
      \viz_js
         box: {width: 1550, height: 950, fill: "#0a0a0a"},
         init() {
            const self = this;
            const VI = {};
            this._VI = VI;

            VI._labels = {}; VI._objects = {}; VI._clickZones = [];
            VI.redraw = function() {
               if (self._viz && self._viz.pane) {
                  self._viz.pane.unrender(); self._viz.pane.render();
               }
               self.getCanvas().renderAll();
            };

            const canvasEl = fabric.document.querySelector("canvas");
            VI.toCanvasCoords = function(cx, cy) {
               if (!canvasEl) return {x: 0, y: 0};
               const rect = canvasEl.getBoundingClientRect();
               const vpt = self.getCanvas().viewportTransform || [1, 0, 0, 1, 0, 0];
               return { x: Math.round((cx - rect.left - vpt[4])/vpt[0]), y: Math.round((cy - rect.top - vpt[5])/vpt[3]) };
            };

            VI.label = function(id, text, x, y, color, fz, ff, align) {
               if (!VI._labels[id]) {
                  const obj = new fabric.Text(String(text), {
                     left: x, top: y, fontSize: fz||16, fill: color||"#e0e0e0",
                     selectable: false, evented: false, fontFamily: ff||"monospace", originX: align||"left"
                  });
                  self.getCanvas().add(obj); VI._labels[id] = obj;
               } else {
                  VI._labels[id].set({text: String(text), left: x, top: y, fill: color||VI._labels[id].fill});
               }
               return VI._labels[id];
            };

            VI.rect = function(id, x, y, w, h, fill, stroke, sw, rx) {
               if (!VI._objects[id]) {
                  const obj = new fabric.Rect({
                     left: x, top: y, width: w, height: h, fill: fill||"#444",
                     stroke: stroke||"transparent", strokeWidth: sw||0, rx: rx||0, ry: rx||0, selectable: false, evented: false
                  });
                  self.getCanvas().add(obj); VI._objects[id] = obj;
               } else {
                  VI._objects[id].set({left: x, top: y, width: w, height: h, fill: fill||VI._objects[id].fill, stroke: stroke||VI._objects[id].stroke});
               }
               return VI._objects[id];
            };

            VI.onClick = function(id, x, y, w, h, cb) { VI._clickZones.push({x,y,w,h,cb}); };
            VI.clearAll = function() { self.getCanvas().clear(); VI._labels={}; VI._objects={}; VI._clickZones=[]; };

            fabric.document.addEventListener("mouseup", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(z => { if(pos.x>=z.x && pos.x<=z.x+z.w && pos.y>=z.y && pos.y<=z.y+z.h) z.cb(pos.x, pos.y); });
            });

            this._firstRender = true;
         },

         onTraceData() {
            this._firstRender = true;
         },

         render() {
            const VI = this._VI; if (!VI) return;
            VI.clearAll();
            const pane = this._viz.pane;
            const wd = pane.waveData;
            if (!wd) return;

            const hex = (v, pad) => "0x" + (typeof v === "bigint" ? v.toString(16).toUpperCase() : v.toString(16).toUpperCase().padStart(pad||8, "0"));
            const bin = (v, pad) => (typeof v === "number" ? v.toString(2).padStart(pad||1, "0") : "");
            
            let getSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asInt(def); } catch(e) { return def; } };
            let getBigSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asBigInt(def); } catch(e) { return def; } };

            let state = getSigAt("TLV|jtag$state", pane.cyc, 0);
            let tms   = getSigAt("TLV|jtag$tms", pane.cyc, 0);
            let tdi   = getSigAt("TLV|jtag$tdi", pane.cyc, 0);
            let tdo   = getSigAt("TLV|jtag$tdo", pane.cyc, 0);
            let tck   = getSigAt("TLV|jtag$tck", pane.cyc, 0);
            
            let ir_reg    = getSigAt("TLV|jtag$ir_reg", pane.cyc, 1);
            let ir_shift  = getSigAt("TLV|jtag$ir_shift", pane.cyc, 1);
            let bypass    = getSigAt("TLV|jtag$bypass_sr", pane.cyc, 0);
            let idcode    = getBigSigAt("TLV|jtag$idcode_sr", pane.cyc, 0x14B3B093n);

            const STATE_NAMES = [
               "TEST-LOGIC-RESET", "RUN-TEST/IDLE", 
               "SELECT-DR", "CAPTURE-DR", "SHIFT-DR", "EXIT1-DR", "PAUSE-DR", "EXIT2-DR", "UPDATE-DR",
               "SELECT-IR", "CAPTURE-IR", "SHIFT-IR", "EXIT1-IR", "PAUSE-IR", "EXIT2-IR", "UPDATE-IR"
            ];
            
            const STATE_EXPLANATIONS = [
               "TAP is reset. Instruction forced to IDCODE. Safe default state.",
               "Idle state. Waiting for JTAG operations to begin.",
               "Controller branch point. TMS=1 goes to IR scan, TMS=0 goes to DR scan.",
               "Capture: Pre-loading active DR with parallel data before shifting begins.",
               `Shifting TDI into Data Register. TDO outputs LSB. (Outputs IDCODE or BYPASS)`,
               "Shift-DR complete. Pathing to Pause or Update.",
               "Shifting paused temporarily. TCK can be stopped without losing state.",
               "Resuming from Pause. Pathing back to Shift or to Update.",
               "Latching shifted serial data into the parallel holding Data Register.",
               "Controller branch point for IR operations.",
               "Capture: Pre-loading IR shift register with status bits (ends in 01).",
               `Shifting TDI into Instruction Register. Next TCK rises pushes TDI=${tdi} into MSB.`,
               "Shift-IR complete. Pathing to Pause or Update.",
               "Shifting paused temporarily.",
               "Resuming from Pause. Pathing back to Shift or to Update.",
               "Latching shifted serial data into the parallel holding Instruction Register."
            ];

            // ================================================================
            // FSM DIAGRAM (Left Side)
            // ================================================================
            const FX = 40, FY = 40, FW = 620, FH = 720;
            VI.rect("fsm_bg", FX, FY, FW, FH, "#111", "#333", 2, 8);
            VI.label("fsm_t", "TAP CONTROLLER STATE MACHINE (IEEE 1149.1)", FX+20, FY+20, "#4fc3f7", 16, "sans-serif");

            const nodes = [
               { id: 0,  lbl: "TEST-LOGIC-RESET", x: 180, y: 100 },
               { id: 1,  lbl: "RUN-TEST/IDLE",    x: 180, y: 180 },
               { id: 2,  lbl: "SELECT-DR",        x: 330, y: 260 },
               { id: 3,  lbl: "CAPTURE-DR",       x: 330, y: 340 },
               { id: 4,  lbl: "SHIFT-DR",         x: 330, y: 420 },
               { id: 5,  lbl: "EXIT1-DR",         x: 330, y: 500 },
               { id: 6,  lbl: "PAUSE-DR",         x: 330, y: 580 },
               { id: 7,  lbl: "EXIT2-DR",         x: 330, y: 660 },
               { id: 8,  lbl: "UPDATE-DR",        x: 180, y: 580 },
               { id: 9,  lbl: "SELECT-IR",        x: 480, y: 260 },
               { id: 10, lbl: "CAPTURE-IR",       x: 480, y: 340 },
               { id: 11, lbl: "SHIFT-IR",         x: 480, y: 420 },
               { id: 12, lbl: "EXIT1-IR",         x: 480, y: 500 },
               { id: 13, lbl: "PAUSE-IR",         x: 480, y: 580 },
               { id: 14, lbl: "EXIT2-IR",         x: 480, y: 660 },
               { id: 15, lbl: "UPDATE-IR",        x: 180, y: 660 }
            ];

            const drawArr = (n1, n2, val) => {
               let x1 = FX + nodes[n1].x, y1 = FY + nodes[n1].y;
               let x2 = FX + nodes[n2].x, y2 = FY + nodes[n2].y;
               let active = (state === n1 && tms === val);
               let c = active ? "#4fc3f7" : "#333";
               let w = active ? 3 : 1;
               
               let midY = Math.min(y1, y2) + Math.abs(y2-y1)/2;
               let midX = Math.min(x1, x2) + Math.abs(x2-x1)/2;
               
               if (n1 === n2) {
                  // Self-Loop
                  VI.rect(`arr_${n1}_${n2}`, x1+60, y1-10, 20, 20, "transparent", c, w, 4);
                  VI.label(`arl_${n1}_${n2}`, val, x1+85, y1-5, c, 10, "monospace");
                  if (active) VI.rect(`arr_head_${n1}_${n2}`, x1+55, y1-10, 6, 6, c); // Arrowhead
               } else if (x1 === x2) {
                  // Vertical Straight
                  VI.rect(`arr_${n1}_${n2}`, x1, Math.min(y1, y2)+15, w, Math.abs(y2-y1)-30, c);
                  VI.label(`arl_${n1}_${n2}`, val, x1+5, midY, c, 10, "monospace");
                  if (active && y2>y1) VI.rect(`arr_head_${n1}_${n2}`, x2-2, y2-20, 6, 6, c); // Down Arrow
                  if (active && y1>y2) VI.rect(`arr_head_${n1}_${n2}`, x2-2, y2+15, 6, 6, c); // Up Arrow
               } else { 
                  // Dog-leg Routing
                  let routeY = y1 + 5; 
                  VI.rect(`arr_${n1}_${n2}_h`, Math.min(x1, x2), routeY, Math.abs(x2-x1), w, c);
                  VI.rect(`arr_${n1}_${n2}_v`, x2, Math.min(routeY, y2)+15, w, Math.abs(y2-routeY)-15, c);
                  VI.label(`arl_${n1}_${n2}`, val, midX, routeY-10, c, 10, "monospace");
                  
                  if (active) {
                     if (y2 > routeY) VI.rect(`arr_head_${n1}_${n2}`, x2-2, y2-20, 6, 6, c); // Down Arrow
                     else VI.rect(`arr_head_${n1}_${n2}`, x2-2, y2+15, 6, 6, c);             // Up Arrow
                  }
               }
            };

            drawArr(0,0,1); drawArr(0,1,0); drawArr(1,1,0); drawArr(1,2,1);
            drawArr(2,3,0); drawArr(2,9,1); drawArr(3,4,0); drawArr(3,5,1);
            drawArr(4,4,0); drawArr(4,5,1); drawArr(5,6,0); drawArr(5,8,1);
            drawArr(6,6,0); drawArr(6,7,1); drawArr(7,4,0); drawArr(7,8,1);
            drawArr(8,1,0); drawArr(8,2,1); drawArr(9,10,0); drawArr(9,0,1);
            drawArr(10,11,0); drawArr(10,12,1); drawArr(11,11,0); drawArr(11,12,1);
            drawArr(12,13,0); drawArr(12,15,1); drawArr(13,13,0); drawArr(13,14,1);
            drawArr(14,11,0); drawArr(14,15,1); drawArr(15,1,0); drawArr(15,2,1);

            nodes.forEach(n => {
               let active = (state === n.id);
               let fill = active ? "#0d47a1" : "#1a1a1a";
               let stroke = active ? "#4fc3f7" : "#444";
               VI.rect("sn_"+n.id, FX + n.x - 60, FY + n.y - 15, 120, 30, fill, stroke, 2, 6);
               VI.label("sl_"+n.id, n.lbl, FX + n.x, FY + n.y - 5, active ? "#fff" : "#aaa", 10, "sans-serif", "center");
               
               // Annotate physical BSCANE2 primitives mapped to States
               if(n.id === 11 || n.id === 4) VI.label("bsc_sh_"+n.id, "BSCANE2: SHIFT", FX + n.x + 65, FY + n.y - 5, "#9c27b0", 9, "sans-serif");
               if(n.id === 10 || n.id === 3) VI.label("bsc_cap_"+n.id, "BSCANE2: CAPTURE", FX + n.x + 65, FY + n.y - 5, "#9c27b0", 9, "sans-serif");
               if(n.id === 15 || n.id === 8) VI.label("bsc_upd_"+n.id, "BSCANE2: UPDATE", FX + n.x - 145, FY + n.y - 5, "#9c27b0", 9, "sans-serif");
            });

            // Signal Info Overlay
            VI.rect("sig_pnl", FX+20, FY+600, 110, 100, "#111", "#444", 1, 4);
            VI.label("sig_tck", "TCK: " + tck, FX+30, FY+610, tck?"#ffeb3b":"#888", 14);
            VI.label("sig_tms", "TMS: " + tms, FX+30, FY+630, tms?"#4fc3f7":"#888", 14);
            VI.label("sig_tdi", "TDI: " + tdi, FX+30, FY+650, tdi?"#81c784":"#888", 14);
            VI.label("sig_tdo", "TDO: " + tdo, FX+30, FY+670, tdo?"#ff9800":"#888", 14);

            // ================================================================
            // JTAG ARCHITECTURE (Right Side)
            // ================================================================
            const AX = 640, AY = 40, AW = 850, AH = 720;
            VI.rect("arch_bg", AX, AY, AW, AH, "#15181e", "#333", 2, 8);
            VI.label("arch_t", "JTAG DATA & INSTRUCTION REGISTERS", AX+20, AY+20, "#4fc3f7", 16, "sans-serif");

            let shift_ir = (state === 11);
            let shift_dr = (state === 4);
            let inst_bypass = (ir_reg === 15);
            let inst_idcode = (ir_reg === 1);

            // Exterior JTAG Pins
            VI.rect("p_tdi", AX-10, AY+130, 10, 15, "#81c784"); VI.label("l_tdi", "TDI", AX-45, AY+130, "#81c784", 14);
            VI.rect("p_tdo", AX+AW, AY+650, 10, 15, "#ff9800"); VI.label("l_tdo", "TDO", AX+AW+15, AY+650, "#ff9800", 14);
            VI.rect("p_trst", AX-10, AY+650, 10, 15, "#555"); VI.label("l_trst", "TRST", AX-55, AY+650, "#888", 14);
            VI.label("trst_note", "(Optional async reset: assumed inactive high)", AX+15, AY+650, "#666", 10, "sans-serif");

            // TDI & TDO Backbone Buses
            VI.rect("tdi_bus", AX, AY+135, 2, 400, "#81c784"); 
            VI.rect("tdo_bus", AX+600, AY+170, 2, 420, shift_ir||shift_dr ? "#ff9800" : "#333");

            // IR Register Structure
            VI.label("t_ir", "INSTRUCTION PATH", AX+100, AY+100, "#aaa", 12, "sans-serif");
            
            // IR Shift Block
            VI.rect("r_ir_sh", AX+100, AY+120, 400, 40, shift_ir ? "#0d47a1" : "#202a35", shift_ir ? "#4fc3f7" : "#555", 1, 4);
            VI.label("rl_ir_sh", "IR SHIFT REG [3:0]", AX+110, AY+133, shift_ir ? "#fff" : "#8892b0", 12, "sans-serif");
            VI.label("rv_ir_sh", bin(ir_shift, 4), AX+480, AY+133, shift_ir ? "#4fc3f7" : "#aaa", 14, "monospace", "right");
            
            // Bit-by-bit serial protocol explanation
            if (shift_ir) {
               VI.label("ir_ser", `Serial Load: TDI(${tdi}) -> [${bin(ir_shift,4)}] -> TDO`, AX+110, AY+145, "#4fc3f7", 10, "monospace");
            }
            
            VI.rect("lin_ir", AX, AY+140, 100, 2, shift_ir ? "#81c784" : "#333");
            VI.rect("lout_ir", AX+500, AY+140, 100, 2, shift_ir ? "#81c784" : "#333");

            // IR Latch Block
            let upd_ir = (state === 15);
            VI.rect("r_ir_ld", AX+100, AY+180, 400, 40, upd_ir ? "#0d47a1" : "#202a35", upd_ir ? "#4fc3f7" : "#555", 1, 4);
            VI.label("rl_ir_ld", "IR HOLD REG  [3:0]", AX+110, AY+193, upd_ir ? "#fff" : "#8892b0", 12, "sans-serif");
            VI.label("rv_ir_ld", bin(ir_reg, 4), AX+480, AY+193, upd_ir ? "#4fc3f7" : "#aaa", 14, "monospace", "right");
            VI.rect("ir_upd_arrow", AX+300, AY+160, 2, 20, upd_ir ? "#4fc3f7" : "#555"); 
            if(upd_ir) VI.rect("ir_arr_hd", AX+297, AY+175, 8, 5, "#4fc3f7");

            // Instruction Decode Panel
            VI.rect("dec_bg", AX+520, AY+100, 310, 120, "#111", "#444", 1, 4);
            let inst_str = inst_idcode ? "IDCODE (0001)" : inst_bypass ? "BYPASS (1111)" : "UNKNOWN ("+bin(ir_reg,4)+")";
            VI.label("ir_dec", "ACTIVE INSTRUCTION: " + inst_str, AX+530, AY+110, "#ffbaba", 12, "sans-serif");
            VI.label("dec_t", "Standard JTAG Opcodes:", AX+530, AY+140, "#aaa", 10, "sans-serif");
            VI.label("dec_1", "0001: IDCODE", AX+530, AY+155, inst_idcode?"#fff":"#777", 10, "monospace");
            VI.label("dec_f", "1111: BYPASS", AX+530, AY+170, inst_bypass?"#fff":"#777", 10, "monospace");
            VI.label("dec_x", "0000: EXTEST (Not Simulated)", AX+530, AY+185, "#555", 10, "monospace");
            VI.label("dec_s", "0010: SAMPLE (Not Simulated)", AX+530, AY+200, "#555", 10, "monospace");

            // DR Registers
            VI.label("t_dr", "DATA PATH (Selected by IR)", AX+100, AY+280, "#aaa", 12, "sans-serif");
            
            // BYPASS
            let b_act = shift_dr && inst_bypass;
            VI.rect("r_byp", AX+100, AY+300, 400, 40, b_act ? "#0d47a1" : "#202a35", b_act ? "#4fc3f7" : "#555", 1, 4);
            VI.label("rl_byp", "BYPASS REG [0]", AX+110, AY+313, b_act ? "#fff" : "#8892b0", 12, "sans-serif");
            VI.label("rv_byp", bin(bypass, 1), AX+480, AY+313, b_act ? "#4fc3f7" : "#aaa", 14, "monospace", "right");
            VI.rect("lin_byp", AX, AY+320, 100, 2, b_act ? "#81c784" : "#333");
            VI.rect("lout_byp", AX+500, AY+320, 100, 2, b_act ? "#81c784" : "#333");
            if (b_act) VI.label("byp_note", "(1 TCK latency bypass)", AX+280, AY+315, "#4fc3f7", 10, "sans-serif", "center");

            // IDCODE
            let id_act = shift_dr && inst_idcode;
            VI.rect("r_id", AX+100, AY+360, 400, 40, id_act ? "#0d47a1" : "#202a35", id_act ? "#4fc3f7" : "#555", 1, 4);
            VI.label("rl_id", "IDCODE REG [31:0]", AX+110, AY+373, id_act ? "#fff" : "#8892b0", 12, "sans-serif");
            VI.label("rv_id", hex(idcode, 8), AX+480, AY+373, id_act ? "#4fc3f7" : "#aaa", 14, "monospace", "right");
            VI.rect("lin_id", AX, AY+380, 100, 2, id_act ? "#81c784" : "#333");
            VI.rect("lout_id", AX+500, AY+380, 100, 2, id_act ? "#81c784" : "#333");
            
            // IDCODE Decode Panel
            VI.rect("idc_bg", AX+100, AY+410, 400, 30, "#111", "#444", 1, 4);
            let ver = Number(idcode >> 28n) & 0xF;
            let part = Number(idcode >> 12n) & 0xFFFF;
            let mfr = Number(idcode >> 1n) & 0x7FF;
            VI.label("idc_1", "V[31:28]: " + hex(ver,1),   AX+110, AY+418, "#aaa", 10, "monospace");
            VI.label("idc_2", "P[27:12]: " + hex(part,4),  AX+200, AY+418, "#aaa", 10, "monospace");
            VI.label("idc_3", "M[11:1]: " + hex(mfr,3),    AX+310, AY+418, "#aaa", 10, "monospace");
            VI.label("idc_4", "0[0]: 1",                   AX+420, AY+418, "#aaa", 10, "monospace");

            // TDO MULTIPLEXER
            const MX = AX+580, MY = AY+590;
            VI.rect("mux_b1", MX-20, MY, 40, 10, "#444");
            VI.rect("mux_b2", MX-10, MY+10, 20, 10, "#444");
            VI.rect("mux_sel", MX, MY-50, 2, 50, "#ffbaba");
            VI.label("mux_l", "IR SELECTOR", MX+10, MY-30, "#ffbaba", 10, "sans-serif");
            
            VI.rect("tdo_out", MX, MY+20, 250, 2, shift_ir||shift_dr ? "#ff9800" : "#333");
            VI.rect("tdo_out2", MX+250, MY+20, 2, 45, shift_ir||shift_dr ? "#ff9800" : "#333");
            VI.rect("tdo_out3", MX+250, AY+657, 170, 2, shift_ir||shift_dr ? "#ff9800" : "#333");
            
            VI.label("tdo_note", "Serial daisy-chain architecture: TDO of Device A connects to TDI of Device B.", AX+430, AY+675, "#888", 10, "sans-serif");

            // State Explanation Panel
            VI.rect("exp_bg", AX+20, AY+520, 480, 80, "#111", "#444", 1, 4);
            VI.label("exp_t", "ACTIVE STATE BEHAVIOR: " + STATE_NAMES[state], AX+30, AY+530, "#4fc3f7", 12, "sans-serif");
            VI.label("exp_c", STATE_EXPLANATIONS[state], AX+30, AY+555, "#aaa", 12, "sans-serif");

            // ================================================================
            // TIMING WAVEFORM (Sliding Window)
            // ================================================================
            const PLOT_X = AX+20, PLOT_Y = AY + 730, PLOT_W = AW-40, PLOT_H = 120;
            VI.rect("wv_bg", PLOT_X, PLOT_Y, PLOT_W, PLOT_H, "#050a05", "#33ff33", 1, 2);
            VI.label("wv_t", "LOGIC ANALYZER (TCK Rising Edge Sampling)", PLOT_X+10, PLOT_Y-18, "#33ff33", 11, "sans-serif");
            
            VI.label("wl_tck", "TCK", PLOT_X+10, PLOT_Y+15, "#ffeb3b", 12);
            VI.label("wl_tms", "TMS", PLOT_X+10, PLOT_Y+45, "#4fc3f7", 12);
            VI.label("wl_tdi", "TDI", PLOT_X+10, PLOT_Y+75, "#81c784", 12);
            VI.label("wl_tdo", "TDO", PLOT_X+10, PLOT_Y+105, "#ff9800", 12);

            const CYCLES_TO_SHOW = 20;
            const stepX = (PLOT_W - 80) / CYCLES_TO_SHOW;
            const wv_start = Math.max(wd.startCycle, pane.cyc - 16);

            for (let k = 0; k < CYCLES_TO_SHOW; k++) {
               let c = wv_start + k;
               let x0 = PLOT_X + 60 + k*stepX;
               VI.rect("wv_grid_"+k, x0, PLOT_Y, 1, PLOT_H, "#0d330d");

               let v_tck = getSigAt("TLV|jtag$tck", c, 0);
               let v_tms = getSigAt("TLV|jtag$tms", c, 0);
               let v_tdi = getSigAt("TLV|jtag$tdi", c, 0);
               let v_tdo = getSigAt("TLV|jtag$tdo", c, 0);
               let pv_tck = getSigAt("TLV|jtag$tck", c-1, 0);
               let pv_tms = getSigAt("TLV|jtag$tms", c-1, 0);
               let pv_tdi = getSigAt("TLV|jtag$tdi", c-1, 0);
               let pv_tdo = getSigAt("TLV|jtag$tdo", c-1, 0);

               const drawTrace = (name, val, pval, yBase, color) => {
                  let yHi = yBase, yLo = yBase + 15;
                  let y = val ? yHi : yLo;
                  VI.rect(`tr_${name}_h_${k}`, x0, y, stepX, 2, color);
                  if (val !== pval && k > 0) VI.rect(`tr_${name}_v_${k}`, x0, yHi, 2, 16, color);
               };

               drawTrace("tck", v_tck, pv_tck, PLOT_Y+15, "#ffeb3b");
               drawTrace("tms", v_tms, pv_tms, PLOT_Y+45, "#4fc3f7");
               drawTrace("tdi", v_tdi, pv_tdi, PLOT_Y+75, "#81c784");
               drawTrace("tdo", v_tdo, pv_tdo, PLOT_Y+105, "#ff9800");

               if (c === pane.cyc) {
                  VI.rect("wv_cursor", x0 + stepX/2, PLOT_Y, 2, PLOT_H, "yellow");
               }
            }

            // ================================================================
            // GLOBAL SCRUBBER
            // ================================================================
            const TX = 40, TY = 870, TW = 1440, TH = 20;
            let START = wd.startCycle, END = wd.endCycle;
            VI.rect("scrb_bg", TX, TY, TW, TH, "#222", "#444", 1, 4);
            let headX = TX + (pane.cyc - START) * TW / Math.max(1, END - START);
            VI.rect("scrb_hd", headX - 3, TY - 5, 6, TH + 10, "#4fc3f7", "transparent", 0, 2);
            VI.label("cyc_lbl", "SIMULATION CYCLE: " + pane.cyc, TX, TY - 25, "#8892b0", 12);
            
            VI.onClick("scrb_bg", TX, TY, TW, TH, function(cx, cy) {
               let targetCyc = Math.round(START + (cx - TX) * (END - START) / TW);
               try { pane.session.setCycle(Math.max(START, Math.min(END, targetCyc))); } catch(e) {}
               VI.redraw();
            });

            if (this._firstRender) {
               this._firstRender = false;
               if (pane.content) {
                  pane.content.contentScale = 0.85;
                  pane.content.userFocus = {x: 750, y: 450};
                  pane.content.refreshContentPosition();
               }
            }
         }
\SV
   endmodule

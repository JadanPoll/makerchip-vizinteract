\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // ==============================================================================
   // RAMB36E1: TRUE DUAL-PORT SIMULATION
   // ==============================================================================
   |bram
      @1
         $reset = *reset;
         
         // Synthetic Stimulus
         $wea = (*cyc_cnt[1:0] != 2'b00); 
         $enb = 1'b1;
         
         // Safe 10-bit extensions
         $addra[9:0] = {4'b0, *cyc_cnt[5:0]};
         $addrb[9:0] = (*cyc_cnt[5:0] > 6'd2) ? {4'b0, *cyc_cnt[5:0] - 6'd2} : 10'd0; 
         
         // 36-bit data: [35:32] Parity (DIPA), [31:0] Data (DIA)
         $dia_data[31:0] = {16'hA5A5, *cyc_cnt[15:0]};
         
         // Byte-wise parity generation
         $dia_parity[3:0] = {
            ^$dia_data[31:24], 
            ^$dia_data[23:16], 
            ^$dia_data[15:8], 
            ^$dia_data[7:0]
         }; 
         $dia[35:0] = {$dia_parity, $dia_data};
         `BOGUS_USE($dia_data $dia_parity)
         
      // Base memory array (64 entries mapped to visualization)
      /mem[63:0]
         @1
            // Use [5:0] slice to safely compare against the implicit 6-bit index
            $my_we = |bram$wea && (|bram$addra[5:0] == /mem$index);
            $val[35:0] = |bram$reset ? 36'b0 :
                         $my_we      ? |bram$dia : >>1$val;
            `BOGUS_USE($val)

   *passed = *cyc_cnt > 200;
   *failed = 1'b0;

   // ==============================================================================
   // VISUALIZER
   // ==============================================================================
   /viz
      \viz_js
         box: {width: 1300, height: 900, fill: "#0a0a0a"},
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

            self.writeMode = "READ_FIRST";
            self.dobReg = 0;
            self.portWidth = 36;
            self.memState = new Map(); 
         },

         onTraceData() {},

         render() {
            const VI = this._VI; if (!VI) return;
            VI.clearAll();
            const pane = this._viz.pane;
            const wd = pane.waveData;
            if (!wd) return;

            const hex = (v, pad) => "0x" + (typeof v === "bigint" ? v.toString(16).toUpperCase() : v.toString(16).toUpperCase().padStart(pad||8, "0"));
            let getSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asInt(def); } catch(e) { return def; } };
            let getBigSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asBigInt(def); } catch(e) { return def; } };
            
            let wea = getSigAt("TLV|bram$wea", pane.cyc, 0);
            let enb = getSigAt("TLV|bram$enb", pane.cyc, 0);
            let addra = getSigAt("TLV|bram$addra", pane.cyc, 0);
            let addrb = getSigAt("TLV|bram$addrb", pane.cyc, 0);
            let dia = getBigSigAt("TLV|bram$dia", pane.cyc, 0n);

            self.memState.clear();
            const weaSig = wd.getSignalByName("TLV|bram$wea");
            if (weaSig && weaSig.transitions) {
               let t = weaSig.transitions;
               for (let i = 0; i < t.length; i += 3) {
                  let c_start = t[i];
                  if (c_start >= pane.cyc) break;
                  if (t[i+1] === "1") {
                     let c_end = (i + 3 < t.length) ? t[i+3] : pane.cyc;
                     let limit = Math.min(c_end, pane.cyc);
                     for (let c = c_start; c < limit; c++) {
                        let a = getSigAt("TLV|bram$addra", c, 0);
                        let d = getBigSigAt("TLV|bram$dia", c, 0n);
                        self.memState.set(a, d);
                     }
                  }
               }
            }

            let prev_mem_val = 0n;
            let a_prev = getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc - 1), 0);
            if (self.memState.has(a_prev)) prev_mem_val = self.memState.get(a_prev);

            let collision = (addra === addrb) && wea && enb;
            let current_mem_val = self.memState.has(addrb) ? self.memState.get(addrb) : 0n;
            let dob_output = current_mem_val;

            if (collision) {
               if (self.writeMode === "READ_FIRST") dob_output = current_mem_val;       
               else if (self.writeMode === "WRITE_FIRST") dob_output = dia;             
               else if (self.writeMode === "NO_CHANGE") dob_output = prev_mem_val;      
            }

            let dia_p = Number(dia >> 32n) & 0xF;
            let dia_d = Number(dia & 0xFFFFFFFFn);
            let dob_p = Number(dob_output >> 32n) & 0xF;
            let dob_d = Number(dob_output & 0xFFFFFFFFn);

            // ================================================================
            // PHYSICAL PIN DIAGRAM
            // ================================================================
            const PX = 140, PY = 40, PW = 280, PH = 600;
            VI.rect("chip", PX, PY, PW, PH, "#111", "#444", 2, 8);
            VI.label("c_title", "RAMB36E1 (TDP)", PX+PW/2, PY+20, "#aaa", 18, "sans-serif", "center");
            
            const drawPin = (name, val, y, isRight, color) => {
               let x = isRight ? PX+PW : PX-15;
               VI.rect("p_"+name, x, y, 15, 10, color, "#222", 1);
               
               let lx = isRight ? PX+PW-10 : PX+10;
               let align = isRight ? "right" : "left";
               VI.label("pl_"+name, name, lx, y-3, color, 12, "monospace", align);
               
               // Left pin values pulled far enough out (PX-10 w/ right-align means it expands safely leftward into the 140px margin)
               let vx = isRight ? PX+PW+20 : PX-10;
               let alignV = isRight ? "left" : "right";
               VI.label("pv_"+name, val, vx, y-2, "#fff", 11, "monospace", alignV);
            };

            drawPin("CLKA", "CLK", PY+60, false, "#ccc");
            drawPin("WEA[3:0]", wea?"0xF":"0x0", PY+90, false, "#4fc3f7");
            drawPin("ENA", "1", PY+110, false, "#4fc3f7");
            drawPin("ADDRA[15:0]", hex(addra,4), PY+140, false, "#ffd54f");
            drawPin("DIA[31:0]", hex(dia_d,8), PY+170, false, "#81c784");
            drawPin("DIPA[3:0]", hex(dia_p,1), PY+190, false, "#aed581");
            drawPin("RSTA", "0", PY+230, false, "#f44336");
            drawPin("REGCEA", "1", PY+250, false, "#ff9800");

            VI.rect("casc_out", PX+120, PY+PH, 10, 30, "#ab47bc");
            VI.label("casc_l", "CASCADEOUTA/B ->", PX+140, PY+PH+10, "#ab47bc", 11);
            VI.label("casc_sub", "Zero routing delay to adjacent BRAM tile.", PX+140, PY+PH+25, "#888", 9);

            drawPin("CLKB", "CLK", PY+60, true, "#ccc");
            drawPin("WEB[3:0]", "0x0", PY+90, true, "#4fc3f7");
            drawPin("ENB", enb?"1":"0", PY+110, true, "#4fc3f7");
            drawPin("ADDRB[15:0]", hex(addrb,4), PY+140, true, "#ffd54f");
            drawPin("DOB[31:0]", hex(dob_d,8), PY+170, true, "#81c784");
            drawPin("DOPB[3:0]", hex(dob_p,1), PY+190, true, "#aed581");
            drawPin("RSTB", "0", PY+230, true, "#f44336");
            drawPin("REGCEB", "1", PY+250, true, "#ff9800");

            // ================================================================
            // ARCHITECTURE EXPLORER
            // ================================================================
            const CX = 520, CY = 40, CW = 760, CH = 600;
            VI.rect("arch_bg", CX, CY, CW, CH, "#15181e", "#333", 2, 8);

            VI.label("w_title", "PORT WIDTH CONFIG", CX+20, CY+20, "#4fc3f7", 14, "sans-serif");
            [9, 18, 36].forEach((w, i) => {
               let bx = CX+20 + (i*60);
               let active = self.portWidth === w;
               VI.rect("btn_w"+w, bx, CY+40, 50, 25, active?"#1976d2":"#222", "#555", 1);
               VI.label("lw"+w, "x"+w, bx+25, CY+45, active?"#fff":"#aaa", 12, "sans-serif", "center");
               VI.onClick("btn_w"+w, bx, CY+40, 50, 25, () => { self.portWidth = w; VI.redraw(); });
            });
            let realDepth = (36 / self.portWidth) * 1024;
            let simDepth = 64; 
            VI.label("w_depth", "Logical Depth: " + realDepth + " entries (Visualizing " + simDepth + ")", CX+220, CY+45, "#ccc", 14);

            VI.label("wm_title", "COLLISION WRITE MODE", CX+20, CY+90, "#4fc3f7", 14, "sans-serif");
            ["READ_FIRST", "WRITE_FIRST", "NO_CHANGE"].forEach((m, i) => {
               let bx = CX+20 + (i*110);
               let active = self.writeMode === m;
               VI.rect("btn_m"+m, bx, CY+110, 100, 25, active?"#388e3c":"#222", "#555", 1);
               VI.label("lm"+m, m, bx+50, CY+115, active?"#fff":"#aaa", 10, "sans-serif", "center");
               VI.onClick("btn_m"+m, bx, CY+110, 100, 25, () => { self.writeMode = m; VI.redraw(); });
            });
            VI.label("nc_warn", "(NO_CHANGE requires valid read at T-1 to init non-zero)", CX+20, CY+145, "#777", 10);

            if (collision) {
               VI.rect("col_warn_bg", CX+380, CY+100, 350, 40, "#4d1919", "#f44336", 2, 4);
               VI.label("col_w", "PORT COLLISION DETECTED!", CX+555, CY+105, "#f44336", 12, "sans-serif", "center");
               VI.label("col_w2", self.writeMode + " -> DOB Output: " + hex(dob_d,8), CX+555, CY+120, "#fff", 12, "monospace", "center");
            }

            VI.label("pl_title", "READ PIPELINE DELAY", CX+20, CY+165, "#4fc3f7", 14, "sans-serif");
            VI.rect("btn_reg", CX+20, CY+185, 150, 25, self.dobReg===1?"#ff9800":"#222", "#555", 1);
            VI.label("l_reg", "DOB_REG = " + self.dobReg, CX+95, CY+190, "#fff", 12, "sans-serif", "center");
            VI.onClick("btn_reg", CX+20, CY+185, 150, 25, () => { self.dobReg = self.dobReg===1?0:1; VI.redraw(); });

            const WX = CX+200, WY = 170;
            let a_cur = hex(getSigAt("TLV|bram$addrb", pane.cyc, 0), 2);
            let a_p1  = hex(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-1), 0), 2);
            let a_p2  = hex(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-2), 0), 2);
            
            let array_val_t1 = self.memState.has(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-1), 0)) ? self.memState.get(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-1), 0)) : 0n;
            let array_val_t2 = self.memState.has(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-2), 0)) ? self.memState.get(getSigAt("TLV|bram$addrb", Math.max(wd.startCycle, pane.cyc-2), 0)) : 0n;
            
            VI.label("w_clkh", "Cycle:", WX, WY+15, "#777", 10);
            VI.label("w_clk0", "T=0", WX+50, WY+15, "#ccc", 10);
            VI.label("w_clk1", "T+1", WX+110, WY+15, "#ccc", 10);
            VI.label("w_clk2", "T+2", WX+170, WY+15, "#ccc", 10);
            
            VI.label("w_ah", "ADDRB", WX, WY+30, "#777", 10);
            VI.label("w_a0", a_cur, WX+50, WY+30, "#ffd54f", 10, "monospace");
            VI.label("w_a1", a_p1, WX+110, WY+30, "#999", 10, "monospace");
            VI.label("w_a2", a_p2, WX+170, WY+30, "#555", 10, "monospace");
            
            VI.label("w_dh", "DOB", WX, WY+45, "#777", 10);
            if(self.dobReg === 0) {
               VI.label("w_d1", hex(Number(array_val_t1 & 0xFFFFn), 4), WX+110, WY+45, "#81c784", 10, "monospace");
               VI.rect("hlt_0", WX+105, WY+43, 40, 14, "transparent", "#fff", 1);
            } else {
               VI.label("w_d1", hex(Number(array_val_t1 & 0xFFFFn), 4), WX+110, WY+45, "#555", 10, "monospace");
               VI.label("w_d2", hex(Number(array_val_t2 & 0xFFFFn), 4), WX+170, WY+45, "#81c784", 10, "monospace");
               VI.rect("hlt_1", WX+165, WY+43, 40, 14, "transparent", "#fff", 1);
            }

            VI.label("map_t", "MEMORY SPACE (0 - " + (simDepth-1) + ")", CX+20, CY+240, "#4fc3f7", 14, "sans-serif");
            const MX = CX+20, MY = CY+260, MW = 500, MH = 300;
            VI.rect("map_bg", MX, MY, MW, MH, "#111", "#333", 1);
            
            self.memState.forEach((val, addr) => {
               if(addr < simDepth) {
                  let y = MY + (addr / simDepth) * MH;
                  VI.rect("m_dat_"+addr, MX, y, MW, 2, "#444");
               }
            });

            let ptrA_y = MY + (addra / simDepth) * MH;
            let ptrB_y = MY + (addrb / simDepth) * MH;
            VI.rect("ptrA", MX-10, ptrA_y, MW+10, 2, "#4fc3f7");
            VI.label("ptrA_L", "ADDR_A", MX-15, ptrA_y-5, "#4fc3f7", 10, "sans-serif", "right");
            VI.rect("ptrB", MX, ptrB_y, MW+10, 2, "#ff9800");
            VI.label("ptrB_L", "ADDR_B", MX+MW+15, ptrB_y-5, "#ff9800", 10, "sans-serif", "left");

            // INIT_xx Note Restored
            VI.label("init_note", "INIT_00..INIT_3F: Content pre-loadable at configuration time via bitstream", MX, MY+MH+15, "#555", 9);

            // Global Scrubber
            VI.rect("scrb", 40, 700, 1200, 20, "#222", "#444", 1, 4);
            let hx = 40 + (pane.cyc - wd.startCycle)*1200 / Math.max(1, wd.endCycle - wd.startCycle);
            VI.rect("scrb_h", hx, 695, 4, 30, "#4fc3f7");
            VI.onClick("scrb", 40, 700, 1200, 20, (x, y) => {
               let cyc = Math.round(wd.startCycle + (x-40)*(wd.endCycle-wd.startCycle)/1200);
               try { pane.session.setCycle(Math.max(wd.startCycle, Math.min(wd.endCycle, cyc))); } catch(e){}
               VI.redraw();
            });
         }
\SV
   endmodule

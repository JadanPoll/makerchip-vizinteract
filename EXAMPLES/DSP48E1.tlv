\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // ==============================================================================
   // DSP48E1: SYSTOLIC ARRAY CASCADE SIMULATION
   // ==============================================================================
   
   |dsp0
      @1
         $reset = *reset;
         $alumode[3:0] = 4'b0000;   // P = Z + X + Y + CIN
         $opmode[6:0] = 7'b0000001; // Z=0, X=M
         
         $a_in[24:0] = *cyc_cnt[24:0];
         $b_in[17:0] = 18'd2;
         $d_in[24:0] = 25'd0;
         $c_in[47:0] = 48'd0;
         $pcin[47:0] = 48'd0; 
         
      @2
         $a_reg[24:0] = >>1$a_in;
         $b_reg[17:0] = >>1$b_in;
      @3
         $ad_reg[24:0] = >>2$d_in + >>1$a_reg;
      @4
         $m_reg[42:0]  = >>1$ad_reg * >>2$b_reg;
      @5
         // Explicit retiming prevents implicit cross-stage consumption warnings
         $opmode_r[6:0] = >>4$opmode;
         $z_mux[47:0]  = ($opmode_r[6:4] == 3'b001) ? >>4$pcin : 
                         ($opmode_r[6:4] == 3'b011) ? >>4$c_in : 48'd0;
                         
         $alu_out[47:0] = $z_mux + >>1$m_reg;
         $p_out[47:0]  = >>1$alu_out;
         $pcout[47:0]  = $p_out;
         
         $pattern[47:0] = 48'h00000000001E; // Terminal count mathematically tuned
         $mask[47:0]    = 48'd0;
         $patterndetect = (($p_out & ~$mask) == ($pattern & ~$mask));
         `BOGUS_USE($patterndetect)

   |dsp1
      @1
         $reset = *reset;
         // ===================================================================
         // IDE BRIDGE TARGET: The VizJS regex will rewrite this line
         $alumode[3:0] = 4'b0001;
         // ===================================================================
         $opmode[6:0] = 7'b0010001; // Z=PCIN, X=M
         
         $a_in[24:0] = *cyc_cnt[24:0];
         $b_in[17:0] = 18'd3;
         $d_in[24:0] = 25'd0;
         $c_in[47:0] = 48'd0;
         
      @2
         $a_reg[24:0] = >>1$a_in;
         $b_reg[17:0] = >>1$b_in;
      @3
         $ad_reg[24:0] = >>2$d_in + >>1$a_reg;
      @4
         $m_reg[42:0]  = >>1$ad_reg * >>2$b_reg;
      @6
         // Registered PCOUT -> PCIN cascade crossing cleanly across tiles
         $pcin[47:0]   = >>1|dsp0$pcout;
         $opmode_r[6:0] = >>5$opmode;
         $z_mux[47:0]  = ($opmode_r[6:4] == 3'b001) ? $pcin : 
                         ($opmode_r[6:4] == 3'b011) ? >>5$c_in : 48'd0;
         
         // Hardware responds to ALUMODE (0001 = P-X)
         $alu_out[47:0] = (>>5$alumode == 4'b0001) ? ($z_mux - >>2$m_reg) : ($z_mux + >>2$m_reg);
         $p_out[47:0]  = >>1$alu_out;
         $pcout[47:0]  = $p_out;
         
         // Mathematical trigger tuned to trigger when the tile wraps back (Trigger at N=164)
         $pattern[47:0] = 48'hFFFFFFFFFF4E;
         $mask[47:0]    = 48'd0;
         $patterndetect = (($p_out & ~$mask) == ($pattern & ~$mask));
         `BOGUS_USE($patterndetect)

   *passed = *cyc_cnt > 200;
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

            const canvasEl = fabric.document.querySelector("canvas");
            VI.toCanvasCoords = function(cx, cy) {
               if (!canvasEl) return {x: 0, y: 0};
               const rect = canvasEl.getBoundingClientRect();
               const vpt = self.getCanvas().viewportTransform || [1, 0, 0, 1, 0, 0];
               return { x: Math.round((cx - rect.left - vpt[4])/vpt[0]), y: Math.round((cy - rect.top - vpt[5])/vpt[3]) };
            };
            fabric.document.addEventListener("mouseup", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(z => { if(pos.x>=z.x && pos.x<=z.x+z.w && pos.y>=z.y && pos.y<=z.y+z.h) z.cb(pos.x, pos.y); });
            });

            // ================================================================
            // IDE BRIDGE INTEGRATION
            // ================================================================
            VI.ide = {available: false, _busy: false};
            (function() {
               let ide = null;
               try { if (fabric.window && fabric.window.ide) ide = fabric.window.ide; } catch(e) {}
               if (ide && ide.IDEMethods && typeof ide.IDEMethods.getCode === "function") {
                  VI.ide.available = true; VI.ide._m = ide.IDEMethods;
               }
            })();

            // Safe isolated replacement logic bypassing the 'g' regex trap
            self.patchHardware = function(sigName, newVal) {
               if (!VI.ide.available || VI.ide._busy) return false;
               const r = VI.ide._m.getCode();
               if (!r) return false;
               
               const rx = new RegExp("(\\$" + sigName + "\\s*\\[\\d+:\\d+\\]\\s*=\\s*)[^;]+;");
               const newCode = r.code.replace(rx, "$1" + newVal + ";");
               
               if (newCode === r.code) return false; 
               
               VI.ide._busy = true;
               self._viz.pane.setStatus("working");
               
               try {
                  VI.ide._m.loadProject(newCode); 
                  setTimeout(() => { VI.ide._busy = false; }, 3000);
               } catch(e) {
                  VI.ide._busy = false;
                  self._viz.pane.setStatus("fail");
               }
               return true;
            };

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

            const hex = (v, pad) => "0x" + (typeof v === "bigint" ? v.toString(16).toUpperCase() : v.toString(16).toUpperCase().padStart(pad||2, "0"));
            let getSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asInt(def); } catch(e) { return def; } };
            let getBigSigAt = (name, cyc, def) => { try { return wd.getSignalValueAtCycleByName(name, cyc).asBigInt(def); } catch(e) { return def; } };

            // ================================================================
            // DSP TILE DRAWING FUNCTION
            // ================================================================
            const drawDsp = (idx, DX, DY) => {
               const prefix = "TLV|dsp" + idx;
               
               const a_in = getSigAt(prefix+"$a_in", pane.cyc, 0);       
               const b_in = getSigAt(prefix+"$b_in", pane.cyc, 0); 
               const c_in = getBigSigAt(prefix+"$c_in", pane.cyc, 0n);
               const d_in = getSigAt(prefix+"$d_in", pane.cyc, 0);
               const opmode = getSigAt(prefix+"$opmode", pane.cyc, 0);   
               const alumode = getSigAt(prefix+"$alumode", pane.cyc, 0); 
               const pcin = getBigSigAt(prefix+"$pcin", pane.cyc, 0n);   
               
               const a_reg = getSigAt(prefix+"$a_reg", pane.cyc, 0);     
               const b_reg = getSigAt(prefix+"$b_reg", pane.cyc, 0);     
               const a_old = getSigAt(prefix+"$a_in", Math.max(pane.cyc-1, wd.startCycle), 0);
               const b_old = getSigAt(prefix+"$b_in", Math.max(pane.cyc-1, wd.startCycle), 0);
               
               const ad   = getSigAt(prefix+"$ad_reg", pane.cyc, 0);     
               const m    = getBigSigAt(prefix+"$m_reg", pane.cyc, 0n);  
               const m_old = getBigSigAt(prefix+"$m_reg", Math.max(pane.cyc-1, wd.startCycle), 0n);
               const p    = getBigSigAt(prefix+"$p_out", pane.cyc, 0n);  
               const pat  = getBigSigAt(prefix+"$pattern", pane.cyc, 0n); 
               
               const pat_det = getSigAt(prefix+"$patterndetect", pane.cyc, 0);

               // Main Tile Background
               VI.rect("bg_"+idx, DX, DY, 580, 680, "#15181e", "#444", 2, 8);
               VI.label("t_"+idx, "DSP48E1 TILE " + idx, DX+20, DY+20, "#4fc3f7", 18, "sans-serif");

               // Stage Labels mapping back to TLV source code
               const stg_c = "#ffeb3b";
               VI.label("s1_"+idx, "@1", DX+10, DY+80, stg_c, 10);
               VI.label("s2_"+idx, "@2", DX+10, DY+150, stg_c, 10);
               VI.label("s3_"+idx, "@3", DX+10, DY+220, stg_c, 10);
               VI.label("s4_"+idx, "@4", DX+10, DY+350, stg_c, 10);
               VI.label("s5_"+idx, idx===0?"@5":"@6", DX+10, DY+490, stg_c, 10);

               // Interactive Hardware Toggle Panel (Tile 1 Demo)
               if (idx === 1) {
                  VI.rect("hw_panel", DX+260, DY+15, 300, 50, "#1a1a1a", "#d32f2f", 1, 4);
                  VI.label("hw_lbl", "HW RECOMPILE TRIGGER:", DX+270, DY+22, "#fff", 10, "sans-serif");
                  
                  let isAdd = (alumode === 0);
                  VI.rect("btn_add", DX+270, DY+35, 100, 22, isAdd ? "#388e3c" : "#222", "#555", 1, 3);
                  VI.label("l_add", "ADD (0000)", DX+320, DY+40, isAdd ? "#fff" : "#999", 10, "sans-serif", "center");
                  VI.onClick("btn_add", DX+270, DY+35, 100, 22, () => { this.patchHardware("alumode", "4'b0000"); });

                  let isSub = (alumode === 1);
                  VI.rect("btn_sub", DX+380, DY+35, 100, 22, isSub ? "#d32f2f" : "#222", "#555", 1, 3);
                  VI.label("l_sub", "SUB (0001)", DX+430, DY+40, isSub ? "#fff" : "#999", 10, "sans-serif", "center");
                  VI.onClick("btn_sub", DX+380, DY+35, 100, 22, () => { this.patchHardware("alumode", "4'b0001"); });
               }

               // ==========================================================
               // PHYSICAL PIN MAP TO REGISTER CONNECTIONS
               // ==========================================================
               const drawPin = (name, val, side, offset, color) => {
                  let x, y, w, h, lx, ly, align, valX, valY, valAlign;
                  if (side === "left") {
                     x = DX - 15; y = DY + offset; w = 15; h = 10;
                     lx = DX - 25; ly = y - 3; align = "right";
                     valX = DX - 25; valY = y + 10; valAlign = "right";
                  } else if (side === "right") {
                     x = DX + 580; y = DY + offset; w = 15; h = 10;
                     lx = DX + 600; ly = y - 3; align = "left";
                     valX = DX + 600; valY = y + 10; valAlign = "left";
                  }
                  VI.rect("p_"+idx+"_"+name, x, y, w, h, color, "#222", 1);
                  VI.label("pl_"+idx+"_"+name, name, lx, ly, color, 12, "monospace", align);
                  VI.label("pv_"+idx+"_"+name, val, valX, valY, "#fff", 11, "monospace", valAlign);
               };

               drawPin("CLK", "CLK", "left", 30, "#ccc");
               drawPin("A[24:0]", hex(a_in, 6), "left", 100, "#ffd54f");
               drawPin("B[17:0]", hex(b_in, 5), "left", 160, "#ffd54f");
               drawPin("D[24:0]", hex(d_in, 6), "left", 240, "#ffd54f");
               drawPin("C[47:0]", hex(c_in, 12), "left", 270, "#ffd54f");
               drawPin("OPMODE", hex(opmode, 2), "left", 315, "#b39ddb");
               drawPin("ALUMODE", hex(alumode, 1), "left", 345, "#b39ddb");
               
               drawPin("PCIN[47:0]", hex(pcin, 12), "right", 80, "#ab47bc");
               drawPin("P[47:0]", hex(p, 12), "right", 560, "#81c784");
               drawPin("PCOUT[47:0]", hex(p, 12), "right", 630, "#ab47bc");

               // Pin to Logic Routing Traces accurately flush with Register Boxes
               VI.rect("rp_A_"+idx, DX, DY+100, 40, 2, "#444");
               VI.rect("rp_B_"+idx, DX, DY+160, 160, 2, "#444");
               VI.rect("rp_D_"+idx, DX, DY+240, 40, 2, "#444");
               
               // C-Bypass Routing explicitly drawn bypassing the multiplier block
               VI.rect("rp_C1_"+idx, DX, DY+270, 530, 2, "#444");
               VI.rect("rp_C2_"+idx, DX+530, DY+270, 2, 210, "#444");
               VI.rect("rp_C3_"+idx, DX+490, DY+480, 42, 2, "#444");
               VI.label("clbl_"+idx, "C Bypass (Z=011)", DX+535, DY+350, "#888", 9);
               VI.label("clbl2_"+idx, "Activate via TLV C_IN", DX+535, DY+362, "#555", 9);
               // ==========================================================


               const drawReg = (rid, lbl, x, y, val, prov_lbl, w) => {
                  VI.rect(rid, x, y, w||80, 45, "#202a35", "#555", 1, 4);
                  VI.label(rid+"l", lbl, x+(w||80)/2, y+10, "#8892b0", 12, "sans-serif", "center");
                  VI.label(rid+"v", hex(val), x+(w||80)/2, y+25, "#fff", 11, "monospace", "center");
                  if(prov_lbl) {
                     VI.label(rid+"t", prov_lbl, x+(w||80)+5, y+20, "#9c27b0", 10);
                  }
               };

               // Inputs
               drawReg("rA_"+idx, "A_IN", DX+40, DY+80, a_in);
               drawReg("rB_"+idx, "B_IN", DX+160, DY+80, b_in);

               // Stage 1 Regs (Age provenance tags safely concatenated)
               VI.rect("l_a_"+idx, DX+80, DY+125, 2, 25, "#2a3b4c");
               VI.rect("l_b_"+idx, DX+200, DY+125, 2, 25, "#2a3b4c");
               drawReg("rAr_"+idx, "AREG", DX+40, DY+150, a_reg, "[C-1: " + hex(a_old) + "]");
               drawReg("rBr_"+idx, "BREG", DX+160, DY+150, b_reg, "[C-1: " + hex(b_old) + "]");

               // Stage 2: Pre-Adder
               VI.rect("l_ad_in_"+idx, DX+80, DY+195, 2, 25, "#2a3b4c");
               VI.rect("pa_"+idx, DX+40, DY+220, 100, 40, "#2e1e3b", "#7e57c2", 2, 4);
               VI.label("pal_"+idx, "PRE-ADD (D ± A[24:0])", DX+90, DY+232, "#d1c4e9", 10, "sans-serif", "center");
               drawReg("rAD_"+idx, "ADREG", DX+50, DY+280, ad);
               VI.rect("l_ad_out_"+idx, DX+90, DY+260, 2, 20, "#4fc3f7");

               // Stage 3: Multiplier
               VI.rect("l_m1_"+idx, DX+90, DY+325, 2, 25, "#4fc3f7");
               VI.rect("l_m2_"+idx, DX+200, DY+195, 2, 155, "#2a3b4c");
               VI.rect("mult_"+idx, DX+70, DY+350, 150, 40, "#2e1e3b", "#7e57c2", 2, 4);
               VI.label("ml_"+idx, "MULT (AD*B)", DX+145, DY+362, "#d1c4e9", 12, "sans-serif", "center");
               drawReg("rM_"+idx, "MREG", DX+105, DY+410, m);
               VI.rect("l_m_out_"+idx, DX+145, DY+390, 2, 20, "#4fc3f7");

               // ALU DECODER PANEL (Resolving fabric.Text newline limitation via distinct offsets)
               let z = (opmode >> 4) & 0x7;
               let x = opmode & 0x3;
               let op_expr = "P = ";
               op_expr += (z===1) ? "PCIN " : (z===2) ? "P " : (z===3) ? "C " : "0 ";
               op_expr += (alumode===0) ? "+ " : (alumode===1) ? "- " : (alumode===3) ? "-(P+X) " : "+ ";
               op_expr += (x===1) ? "M" : (x===2) ? "P" : "0";

               VI.rect("dec_"+idx, DX+280, DY+220, 240, 95, "#111", "#555", 1, 4);
               VI.label("dl1_"+idx, "ALUMODE/OPMODE DECODE", DX+400, DY+230, "#aaa", 10, "sans-serif", "center");
               VI.label("dl2_"+idx, op_expr, DX+400, DY+250, "#ffd54f", 16, "monospace", "center");
               
               VI.label("alum_r1_"+idx, "ALUMODE: 0000=Z+(W+X+Y+CIN)", DX+400, DY+275, "#888", 9, "sans-serif", "center");
               VI.label("alum_r2_"+idx, "0001=Z-(W+X+Y+CIN)", DX+400, DY+285, "#888", 9, "sans-serif", "center");
               VI.label("alum_r3_"+idx, "0011=-(Z+(W+X+Y+CIN))", DX+400, DY+295, "#888", 9, "sans-serif", "center");

               // Stage 4: ALU
               VI.rect("l_alu1_"+idx, DX+145, DY+455, 2, 35, "#4fc3f7");
               
               // PCIN routing from the right pin natively flush to DY+80
               VI.rect("l_alu2_"+idx, DX+470, DY+80, 110, 2, "#ab47bc"); 
               VI.rect("l_alu3_"+idx, DX+470, DY+80, 2, 410, "#ab47bc"); 
               
               VI.rect("alu_"+idx, DX+120, DY+490, 370, 50, "#2e1e3b", "#7e57c2", 2, 4);
               VI.label("alul_"+idx, "POST-ADDER / ALU", DX+305, DY+508, "#d1c4e9", 14, "sans-serif", "center");
               drawReg("rP_"+idx, "PREG", DX+265, DY+560, p, "[MREG: " + hex(m_old) + "]", 100);
               
               // Wrap notation for subtracting pipeline
               if(idx === 1) VI.label("u_wrap", "(wraps: 48-bit unsigned)", DX+315, DY+615, "#f44336", 9, "sans-serif", "center");
               
               VI.rect("l_p_out_"+idx, DX+305, DY+540, 2, 20, "#4fc3f7");

               // Pattern Detector showing actual live mathematical bounds
               VI.rect("pat_"+idx, DX+380, DY+620, 190, 45, "#4d1919", "#f44336", 1, 4);
               VI.label("patl_"+idx, "PATTERN DETECTOR", DX+475, DY+625, "#ffbaba", 10, "sans-serif", "center");
               VI.label("patm_"+idx, pat_det ? "MATCH" : "NO MATCH", DX+475, DY+640, pat_det ? "#0f0" : "#888", 12, "sans-serif", "center");
               VI.label("patv_"+idx, "P=" + hex(p,12) + " vs " + hex(pat), DX+475, DY+652, "#ffbaba", 9, "sans-serif", "center");

               // Visual internal anchor for PCOUT to trace flush to the right pin
               VI.rect("l_pcout_"+idx, DX+315, DY+605, 2, 25, "#4fc3f7");
               VI.rect("rp_pcout_"+idx, DX+315, DY+630, 265, 2, "#ab47bc");
            };

            drawDsp(0, 100, 40);
            drawDsp(1, 740, 40);

            // Cascading Visuals: Correctly aligned from Right Pin Edge to Right Pin Edge (X > 1335)
            // Tile 0 PCOUT pin right edge is DX+580+15 = 100+595 = 695
            // Tile 1 PCIN pin right edge is DX+580+15 = 740+595 = 1335
            VI.rect("casc1", 695, 670, 655, 4, "#ab47bc");   // Horiz out of Tile 0
            VI.rect("casc2", 1350, 120, 4, 550, "#ab47bc");  // Up the side
            VI.rect("casc3", 1335, 120, 15, 4, "#ab47bc");   // Horiz back into Tile 1's PCIN pin right edge
            VI.rect("casc_arr1", 1335, 118, 6, 8, "#ab47bc"); // Clean block terminator
            
            VI.label("casc_l", "ZERO-DELAY CASCADE CHAIN (PCOUT -> PCIN)", 1490, 400, "#ab47bc", 14, "sans-serif", "right");

            // Global Scrubber bounded cleanly at 1360
            VI.rect("scrb", 40, 800, 1360, 20, "#222", "#444", 1, 4);
            let hx = 40 + (pane.cyc - wd.startCycle)*1360 / Math.max(1, wd.endCycle - wd.startCycle);
            VI.rect("scrb_h", hx, 795, 4, 30, "#4fc3f7");
            VI.label("scrb_l", "CYCLE: " + pane.cyc, 40, 780, "#8892b0", 12);
            VI.onClick("scrb", 40, 800, 1360, 20, (x, y) => {
               let cyc = Math.round(wd.startCycle + (x-40)*(wd.endCycle-wd.startCycle)/1360);
               try { pane.session.setCycle(Math.max(wd.startCycle, Math.min(wd.endCycle, cyc))); } catch(e){}
               VI.redraw();
            });

            // ================================================================
            // CAMERA AUTO-CENTERING
            // ================================================================
            if (this._firstRender) {
               this._firstRender = false;
               if (pane.content) {
                  pane.content.contentScale = 0.85;
                  pane.content.userFocus = {x: 750, y: 475};
                  pane.content.refreshContentPosition();
               }
            }
         }
\SV
   endmodule

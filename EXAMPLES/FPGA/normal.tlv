\m4_TLV_version 1d: tl-x.org
\SV
   // Using good old M4 to fetch your SystemVerilog files
   m4_sv_get_url(['https://raw.githubusercontent.com/JadanPoll/makerchip-vizinteract/refs/heads/main/EXAMPLES/FPGA/vga_controller.sv'])
   m4_sv_get_url(['https://raw.githubusercontent.com/JadanPoll/makerchip-vizinteract/refs/heads/main/EXAMPLES/FPGA/font_rom.sv'])

   m4_makerchip_module

   // --- SV BRIDGE WIRES ---
   // These bypass TL-Verilog hierarchy scoping to broadcast into the VRAM array
   logic        axi_wr_pulse_sv;
   logic [11:0] axi_awaddr_sv;
   logic [31:0] axi_wdata_sv;

\TLV
   // ============================================================
   // HDMI TEXT CONTROLLER — Makerchip Simulation
   // ECE 385 Lab 7.1 accurate model
   //
   // Memory map (byte addresses):
   //   0x000 - 0x95F : VRAM  (600 x 32-bit words = 2400 chars, 80x30)
   //   0x960         : COLOR register (slv_regs[600])
   //                   [31:28] unused
   //                   [27:24] fg_red   [23:20] fg_green  [19:16] fg_blue
   //                   [15:12] unused
   //                   [11:8]  bg_red   [7:4]   bg_green  [3:0]   bg_blue
   //   0x964 (r/o)   : FRAME_COUNTER (slv_regs[601])
   //   0x968 (r/o)   : DRAW_X        (slv_regs[602])
   //   0x96C (r/o)   : DRAW_Y        (slv_regs[603])
   //
   // Character encoding (each byte in VRAM):
   //   bit[7]   = invert bit (swap fg/bg for this char)
   //   bit[6:0] = ASCII code
   //
   // Pixel pipeline (verbatim from lab top-level):
   //   char_x    = drawX[9:3]          (divide by 8)
   //   char_y    = drawY[9:4]          (divide by 16)
   //   lin_idx   = char_y*80 + char_x  (12-bit)
   //   word_addr = lin_idx[11:2]       (which 32-bit VRAM word)
   //   byte_sel  = lin_idx[1:0]        (which byte within word)
   //   font_addr = {char[6:0], row}    (11-bit, row = drawY[3:0])
   //   pixel     = font_data[7-drawX[2:0]]
   //   draw_fg   = pixel ^ char[7]     (invert bit XOR)
   //
   // Clock modeling:
   //   System clock = 1 Makerchip cycle
   //   pixel_clk_en pulses every 4 cycles (models 25MHz from 100MHz)
   //   AXI writes happen at full clock rate
   //   VGA counters advance on pixel_clk_en
   // ============================================================

   // -------------------------------------------------------------------
   // PIPELINE 1: AXI4-Lite Stimulus
   // Mimics the testbench axi_write task and the C driver hdmiTestWeek1()
   // Writes: COLOR register, then fills VRAM words 0-599 with test data
   // -------------------------------------------------------------------
   |axi
      @1
         $reset = *reset;

         // AXI write state machine
         // Phase encoding (driven by cyc_cnt):
         //   cyc 0-3   : reset
         //   cyc 4-7   : write COLOR register (addr=0x960, data=fg WHITE | bg BLACK)
         //   cyc 8+    : write VRAM words sequentially, one per 4 cycles
         //
         // Each AXI write takes ~4 cycles (matches testbench #3 delay + handshake)

         $cyc[31:0] = *cyc_cnt;

         // Which VRAM word are we writing? (0 to 599)
         // After COLOR write (cyc 4-7), VRAM writes start at cyc 8
         $vram_wr_idx[9:0] = ($cyc >= 32'd8) ? (($cyc - 32'd8) >> 2) : 10'd0;

         $doing_color_wr  = ($cyc >= 32'd4) && ($cyc < 32'd8);
         $doing_vram_wr   = ($cyc >= 32'd8) && ($vram_wr_idx < 10'd600);
         $doing_any_wr    = $doing_color_wr || $doing_vram_wr;

         // Pulse valid signals on the first cycle of each 4-cycle window
         $wr_phase[1:0]   = $cyc[1:0];
         $wr_pulse        = ($wr_phase == 2'b00) && $doing_any_wr;

         // AXI write address
         // COLOR register: byte address 0x960 = word 600 * 4
         // VRAM word N: byte address N * 4
         $awaddr[11:0] = $doing_color_wr ? 12'h960 :
                         {$vram_wr_idx, 2'b00};

         // AXI write data
         // COLOR register: fg=WHITE(0xFFF) upper, bg=BLACK(0x000) lower
         //   [27:24]=F [23:20]=F [19:16]=F  [11:8]=0 [7:4]=0 [3:0]=0
         //   = 32'h0FFF_0000
         // VRAM: pack 4 ASCII chars per 32-bit word
         //   Pattern: fill each char slot with ASCII of (word_idx % 95 + 32)
         //   so we get printable characters cycling through the ASCII table.

         // FIX 1: Use full 10-bit $vram_wr_idx for modulo, not just bits [6:0].
         //        Original used $vram_wr_idx[6:0] (range 0-127), which produced
         //        wrong character sequencing for word indices 95-599.
         $char_base[6:0] = ($vram_wr_idx % 10'd95) + 7'd32;

         $char_a[7:0] = {1'b0, $char_base};

         // FIX 2: Promote all char offset overflow guards to 8-bit arithmetic.
         //        Original used 7-bit arithmetic, causing truncation for offsets
         //        >= 2: e.g. $char_base=126, 7'd2 added in 7-bit context gives 0,
         //        so 0 >= 127 is false and the wrap-around is skipped, producing
         //        char code 0 (NUL) instead of the correctly wrapped value.
         $char_b[7:0] = ({1'b0, $char_base} + 8'd1 >= 8'd127)
                           ? {1'b0, $char_base - 7'd94}
                           : {1'b0, $char_base + 7'd1};
         $char_c[7:0] = ({1'b0, $char_base} + 8'd2 >= 8'd127)
                           ? {1'b0, $char_base - 7'd93}
                           : {1'b0, $char_base + 7'd2};
         $char_d[7:0] = ({1'b0, $char_base} + 8'd3 >= 8'd127)
                           ? {1'b0, $char_base - 7'd92}
                           : {1'b0, $char_base + 7'd3};

         $wdata[31:0] = $doing_color_wr ? 32'h0FFF_0000 :
                        {$char_d, $char_c, $char_b, $char_a};

         // AXI handshake signals (simplified: assert valid on wr_pulse, hold 2 cycles)
         $awvalid = $wr_pulse || >>1$wr_pulse;
         $wvalid  = $wr_pulse || >>1$wr_pulse;
         $wstrb[3:0] = 4'hF;

         // Pass the AXI signals to the global SV bridge wires for the VRAM array
         *axi_wr_pulse_sv = $wr_pulse;
         *axi_awaddr_sv   = $awaddr;
         *axi_wdata_sv    = $wdata;

         `BOGUS_USE($reset $awvalid $wvalid $wstrb $awaddr $wdata $doing_any_wr)

   // -------------------------------------------------------------------
   // PIPELINE 2: VRAM — 600 x 32-bit words
   // Replicated hierarchy: /vram[599:0], each holds one 32-bit word
   // Write port: driven by AXI stimulus pipeline
   // Read port: driven by VGA display pipeline (word_addr)
   // -------------------------------------------------------------------
   |vga
      @1
         $reset = *reset;

         // -------------------------------------------------------
         // Pixel clock enable: pulse every 4 system cycles
         // Models 25MHz pixel clock from 100MHz system clock
         // -------------------------------------------------------
         $cyc[31:0]   = *cyc_cnt;
         $pclk_en     = ($cyc[1:0] == 2'b11);

         // -------------------------------------------------------
         // VGA horizontal counter (hc): 0 to 799
         // VGA vertical counter (vc): 0 to 524
         // Both advance only when pclk_en is asserted
         // -------------------------------------------------------
         $hc[9:0] = $reset                         ? 10'd0 :
                    !$pclk_en                      ? >>1$hc :
                    (>>1$hc == 10'd799)            ? 10'd0 :
                                                     >>1$hc + 10'd1;

         $vc[9:0] = $reset                         ? 10'd0 :
                    !$pclk_en                      ? >>1$vc :
                    (>>1$hc != 10'd799)            ? >>1$vc :
                    (>>1$vc == 10'd524)            ? 10'd0 :
                                                     >>1$vc + 10'd1;

         $drawX[9:0] = $hc;
         $drawY[9:0] = $vc;

         // -------------------------------------------------------
         // Sync signals (registered, matching VGA controller)
         // hsync active low: pixels 656-751
         // vsync active low: lines 490-491
         // -------------------------------------------------------
         $hsync = !(($hc >= 10'd656) && ($hc < 10'd752));
         $vsync = !(($vc == 10'd490) || ($vc == 10'd491));
         $active = !($hc >= 10'd640 || $vc >= 10'd480);

         // -------------------------------------------------------
         // Frame counter: increment on rising edge of vsync
         // -------------------------------------------------------
         $vsync_rose  = $vsync && !>>1$vsync;
         $frame_cnt[31:0] = $reset       ? 32'd0 :
                            $vsync_rose  ? >>1$frame_cnt + 32'd1 :
                                           >>1$frame_cnt;

         // -------------------------------------------------------
         // Character address calculation (combinational, exact from lab)
         // char_x = drawX[9:3]  (column 0-79)
         // char_y = drawY[9:4]  (row 0-29)
         // lin_idx = char_y * 80 + char_x  (0-2399)
         // word_addr = lin_idx[11:2]  (0-599, which 32-bit VRAM word)
         // byte_sel = lin_idx[1:0]   (which byte within word)
         //
         // lin_idx intermediate operands are zero-padded to 12 bits
         // to prevent truncation in strict synthesis tools:
         //   {1'b0,$char_y,6'b0} = char_y*64  (12-bit)
         //   {3'b0,$char_y,4'b0} = char_y*16  (12-bit)
         //   {5'b0,$char_x}      = char_x      (12-bit)
         // -------------------------------------------------------
         $char_x[6:0]  = $drawX[9:3];
         $char_y[4:0]  = $drawY[9:4];
         $lin_idx[11:0] = {1'b0, $char_y, 6'b0}   // char_y * 64
                        + {3'b0, $char_y, 4'b0}    // char_y * 16
                        + {5'b0, $char_x};          // char_x
         $word_addr[9:0] = $lin_idx[11:2];
         $byte_sel[1:0]  = $lin_idx[1:0];

         // -------------------------------------------------------
         // VRAM read: current_vram_word comes from /vram hierarchy
         // byte extraction (exact mux from lab)
         // -------------------------------------------------------
         $current_vram_word[31:0] = /vram[$word_addr]$word_data;

         $exact_char[7:0] =
            ($byte_sel == 2'b00) ? $current_vram_word[7:0]   :
            ($byte_sel == 2'b01) ? $current_vram_word[15:8]  :
            ($byte_sel == 2'b10) ? $current_vram_word[23:16] :
                                   $current_vram_word[31:24] ;

         // -------------------------------------------------------
         // Font ROM lookup
         // font_addr = {char[6:0], drawY[3:0]}  (11-bit)
         // Combinational ROM — no latency
         // -------------------------------------------------------
         $font_addr[10:0] = {$exact_char[6:0], $drawY[3:0]};

         logic [7:0] font_data_sv;
         font_rom font_rom_inst (.addr($font_addr), .data(font_data_sv));
         $font_data[7:0] = font_data_sv;

         // FIX 3: Removed the erroneous $pixel_value line.
         //        Original: $pixel_value = $font_data[7] >> $drawX[2:0]
         //        Bug: $font_data[7] selects only the single MSB bit (1-bit),
         //        not the full 8-bit byte. Shifting a 1-bit value by any non-zero
         //        amount produces 0. The correct pixel selection is $pv below.

         // Select the correct font pixel for the current column within the cell.
         // Font convention: bit 7 = leftmost pixel (column 0), bit 0 = rightmost.
         $pv = ($drawX[2:0] == 3'd0) ? $font_data[7] :
               ($drawX[2:0] == 3'd1) ? $font_data[6] :
               ($drawX[2:0] == 3'd2) ? $font_data[5] :
               ($drawX[2:0] == 3'd3) ? $font_data[4] :
               ($drawX[2:0] == 3'd4) ? $font_data[3] :
               ($drawX[2:0] == 3'd5) ? $font_data[2] :
               ($drawX[2:0] == 3'd6) ? $font_data[1] :
                                       $font_data[0] ;

         $inverse_bit  = $exact_char[7];
         $draw_fg      = $pv ^ $inverse_bit;

         // -------------------------------------------------------
         // Color register (from AXI word 600)
         // COLOR[27:24]=fg_r, [23:20]=fg_g, [19:16]=fg_b
         // COLOR[11:8]=bg_r,  [7:4]=bg_g,   [3:0]=bg_b
         // -------------------------------------------------------
         $color_reg[31:0] = /vram[10'd600]$word_data;

         $fg_r[3:0] = $color_reg[27:24];
         $fg_g[3:0] = $color_reg[23:20];
         $fg_b[3:0] = $color_reg[19:16];
         $bg_r[3:0] = $color_reg[11:8];
         $bg_g[3:0] = $color_reg[7:4];
         $bg_b[3:0] = $color_reg[3:0];

         $red[3:0]   = ($active && $draw_fg)  ? $fg_r :
                       ($active && !$draw_fg) ? $bg_r : 4'h0;
         $green[3:0] = ($active && $draw_fg)  ? $fg_g :
                       ($active && !$draw_fg) ? $bg_g : 4'h0;
         $blue[3:0]  = ($active && $draw_fg)  ? $fg_b :
                       ($active && !$draw_fg) ? $bg_b : 4'h0;

         `BOGUS_USE($hsync $vsync $red $green $blue $frame_cnt $pv)

      // -------------------------------------------------------
      // VRAM hierarchy: 601 words (600 VRAM + 1 COLOR register)
      // Indices 0-599: character data (4 chars per 32-bit word)
      // Index  600:    COLOR register [27:24]=fg_r [23:20]=fg_g
      //                               [19:16]=fg_b [11:8]=bg_r
      //                               [7:4]=bg_g   [3:0]=bg_b
      // -------------------------------------------------------
      /vram[600:0]
         @1
            $index[9:0] = #vram;
            $reset = *reset;

            // AXI write decode: word address = byte address / 4 = awaddr[11:2]
            // COLOR register at 0x960 → word index 0x960/4 = 600 → matches slot 600
            $my_we = *axi_wr_pulse_sv && (*axi_awaddr_sv[11:2] == $index[9:0]);

            $word_data[31:0] = $reset ? 32'h0 :
                               $my_we ? *axi_wdata_sv :
                                        >>1$word_data;

         @2
            `BOGUS_USE($word_data)

   // Simulation terminates after all 601 AXI writes complete with margin.
   // COLOR write:   cyc 4-7   (1 word)
   // VRAM writes:   cyc 8 + 600*4 = cyc 2408 (last pulse at cyc 2408)
   // Total: 2412 cycles + margin → 3200 is sufficient.
   *passed = *cyc_cnt > 32'd3200;
   *failed = 1'b0;

   // -------------------------------------------------------------------
   // VIZ: Virtual HDMI Monitor + Signal Inspector
   // Dark phosphor theme, EEPROM-style layout
   // -------------------------------------------------------------------
   /viz
      \viz_js
         box: {width: 1280, height: 800, fill: "#0d0d0d"},

         init() {
            const self = this;
            const VI   = {};
            this._VI   = VI;

            VI._labels      = {};
            VI._objects     = {};
            VI._hotkeys     = {};
            VI._clickZones  = [];
            VI._hoverZones  = {};
            VI._lastHovered = {};

            VI.redraw = function() {
               if (self._viz && self._viz.pane) {
                  const pane = self._viz.pane;
                  if (typeof pane.unrender === "function") pane.unrender();
                  if (typeof pane.render   === "function") pane.render();
               }
               self.getCanvas().renderAll();
            };

            VI.clearAll = function() {
               const c = self.getCanvas();
               c.clear();
               c.selection  = false;
               VI._labels     = {};
               VI._objects    = {};
               VI._clickZones = [];
               VI._hoverZones = {};
            };

            const canvasEl    = fabric.document.querySelector("canvas");
            const focusTarget = canvasEl ? canvasEl.closest("div") : null;
            if (focusTarget) {
               focusTarget.setAttribute("tabindex", "0");
               setTimeout(function() { focusTarget.focus(); }, 500);
            }

            const _editorHasFocus = function() {
               const active = fabric.document.activeElement;
               const tag    = active ? active.tagName.toLowerCase() : "none";
               return tag === "textarea" || tag === "input" || (active && active.isContentEditable);
            };

            VI.toCanvasCoords = function(clientX, clientY) {
               if (!canvasEl) return {x: 0, y: 0};
               const rect = canvasEl.getBoundingClientRect();
               const c    = self.getCanvas();
               const vpt  = c.viewportTransform || [1, 0, 0, 1, 0, 0];
               return {
                  x: Math.round((clientX - rect.left - vpt[4]) / vpt[0]),
                  y: Math.round((clientY - rect.top  - vpt[5]) / vpt[3])
               };
            };

            VI.label = function(id, text, x, y, color, fontSize, fontFam) {
               const c = self.getCanvas();
               if (!VI._labels[id]) {
                  const obj = new fabric.Text(String(text), {
                     left: x, top: y,
                     fontSize: fontSize || 12,
                     fill: color || "#33ff33",
                     selectable: false, evented: false,
                     hasControls: false, hasBorders: false,
                     fontFamily: fontFam || "monospace"
                  });
                  c.add(obj);
                  VI._labels[id] = obj;
               } else {
                  VI._labels[id].set("text", String(text));
                  VI._labels[id].set("left", x);
                  VI._labels[id].set("top",  y);
                  if (color)    VI._labels[id].set("fill",     color);
                  if (fontSize) VI._labels[id].set("fontSize", fontSize);
               }
               return VI._labels[id];
            };

            VI.rect = function(id, x, y, w, h, fill, stroke, sw, rx) {
               sw = (sw === undefined) ? 0 : sw;
               rx = (rx === undefined) ? 0 : rx;
               const c = self.getCanvas();
               if (!VI._objects[id]) {
                  const obj = new fabric.Rect({
                     left: x, top: y, width: w, height: h,
                     fill: fill || "#1a1a1a",
                     stroke: stroke || "transparent",
                     strokeWidth: sw, rx: rx, ry: rx,
                     selectable: false, evented: false,
                     hasControls: false, hasBorders: false
                  });
                  c.add(obj);
                  VI._objects[id] = obj;
               } else {
                  VI._objects[id].set({left: x, top: y, width: w, height: h,
                     fill: fill || VI._objects[id].fill,
                     stroke: stroke || VI._objects[id].stroke,
                     strokeWidth: sw});
               }
               return VI._objects[id];
            };

            VI.onClick = function(id, x, y, w, h, callback) {
               VI._clickZones = VI._clickZones.filter(z => z.id !== id);
               VI._clickZones.push({id, x, y, w, h, cb: callback});
            };
            VI.onKey = function(key, cb) { VI._hotkeys[key] = cb; };

            const _hit = (z, cx, cy) => cx >= z.x && cx <= z.x+z.w && cy >= z.y && cy <= z.y+z.h;

            fabric.document.addEventListener("mousedown", () => { if (focusTarget) focusTarget.focus(); });
            fabric.document.addEventListener("mouseup", function(e) {
               if (_editorHasFocus()) return;
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(z => { if (_hit(z, pos.x, pos.y)) z.cb(pos.x, pos.y); });
            });
            fabric.window.addEventListener("keydown", function(e) {
               if (_editorHasFocus()) return;
               if (VI._hotkeys[e.key]) VI._hotkeys[e.key](e);
            });

            // FIX 4: Added VI.ide initialization block (ported from Week 2).
            //        Original scrubber used session.setCycle() which may not exist
            //        in all Makerchip environments. VI.ide.setCycle() is guarded
            //        and fails gracefully.
            VI.ide = {available: false, _busy: false, _lastGen: null};
            (function() {
               let ide = null;
               try {
                  if (fabric.window && fabric.window.ide) ide = fabric.window.ide;
                  else if (fabric.document.defaultView && fabric.document.defaultView.ide) ide = fabric.document.defaultView.ide;
                  else if (self._viz.pane.ide) ide = self._viz.pane.ide;
               } catch(e) {}
               if (ide && ide.IDEMethods &&
                   typeof ide.IDEMethods.getCode     === "function" &&
                   typeof ide.IDEMethods.loadProject === "function") {
                  VI.ide.available = true;
                  VI.ide._ide = ide;
                  VI.ide._m   = ide.IDEMethods;
               }
            })();
            VI.ide.setCycle = function(n) {
               try {
                  if (VI.ide.available && VI.ide._ide.viz &&
                      typeof VI.ide._ide.viz.setCycle === "function") {
                     VI.ide._ide.viz.setCycle(n); return true;
                  }
               } catch(e) {}
               return false;
            };

            // State
            self.selCell   = 0;   // selected VRAM word (0-599)
            self.selRow    = 0;   // selected screen row (0-29)
            self.viewMode  = 0;   // 0=screen, 1=raw VRAM

            // Font ROM — mirrors the hardware font ROM exactly.
            // Index: charCode * 16 + row → 8-bit row bitmap.
            // Covers 0x20 (space) through 0x7F (DEL), 96 chars * 16 rows = 1536 entries.
            // Control chars 0x00-0x1F remain 0 (blank glyphs).
            self.fontROM = new Uint8Array(128 * 16);
            const FONT_DATA = [
               // 0x20 space
               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x21 !
               0,0,0x18,0x3C,0x3C,0x3C,0x18,0x18,0,0x18,0x18,0,0,0,0,0,
               // 0x22 "
               0,0x66,0x66,0x66,0x24,0,0,0,0,0,0,0,0,0,0,0,
               // 0x23 #
               0,0,0,0x6C,0x6C,0xFE,0x6C,0x6C,0x6C,0xFE,0x6C,0x6C,0,0,0,0,
               // 0x24 $
               0x18,0x18,0x7C,0xC6,0xC2,0xC0,0x7C,0x06,0x06,0x86,0xC6,0x7C,0x18,0x18,0,0,
               // 0x25 %
               0,0,0,0,0xC2,0xC6,0x0C,0x18,0x30,0x66,0xC6,0,0,0,0,0,
               // 0x26 &
               0,0,0x38,0x6C,0x6C,0x38,0x76,0xDC,0xCC,0xCC,0xCC,0x76,0,0,0,0,
               // 0x27 '
               0,0x30,0x30,0x30,0x60,0,0,0,0,0,0,0,0,0,0,0,
               // 0x28 (
               0,0,0x0C,0x18,0x30,0x30,0x30,0x30,0x30,0x30,0x18,0x0C,0,0,0,0,
               // 0x29 )
               0,0,0x30,0x18,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x18,0x30,0,0,0,0,
               // 0x2A *
               0,0,0,0,0,0x6E,0x3C,0xFF,0x3C,0x6E,0,0,0,0,0,0,
               // 0x2B +
               0,0,0,0,0,0x18,0x18,0x7E,0x18,0x18,0,0,0,0,0,0,
               // 0x2C ,
               0,0,0,0,0,0,0,0,0,0x18,0x18,0x18,0x30,0,0,0,
               // 0x2D -
               0,0,0,0,0,0,0,0xFE,0,0,0,0,0,0,0,0,
               // 0x2E .
               0,0,0,0,0,0,0,0,0,0,0x18,0x18,0,0,0,0,
               // 0x2F /
               0,0,0,0x06,0x06,0x0C,0x18,0x30,0x60,0xC0,0xC0,0,0,0,0,0,
               // 0x30 0
               0,0,0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x31 1
               0,0,0x18,0x38,0x78,0x18,0x18,0x18,0x18,0x18,0x7E,0,0,0,0,0,
               // 0x32 2
               0,0,0x7C,0xC6,0x06,0x0C,0x18,0x30,0x60,0xC0,0xFE,0,0,0,0,0,
               // 0x33 3
               0,0,0x7C,0xC6,0x06,0x06,0x3C,0x06,0x06,0xC6,0x7C,0,0,0,0,0,
               // 0x34 4
               0,0,0x0C,0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x0C,0x1E,0,0,0,0,0,
               // 0x35 5
               0,0,0xFE,0xC0,0xC0,0xC0,0xFC,0x06,0x06,0xC6,0x7C,0,0,0,0,0,
               // 0x36 6
               0,0,0x3C,0x60,0xC0,0xC0,0xFC,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x37 7
               0,0,0xFE,0xC6,0x06,0x06,0x0C,0x18,0x30,0x30,0x30,0,0,0,0,0,
               // 0x38 8
               0,0,0x7C,0xC6,0xC6,0xC6,0x7C,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x39 9
               0,0,0x7C,0xC6,0xC6,0xC6,0x7E,0x06,0x06,0x0C,0x78,0,0,0,0,0,
               // 0x3A :
               0,0,0,0x18,0x18,0,0,0x18,0x18,0,0,0,0,0,0,0,
               // 0x3B ;
               0,0,0,0x18,0x18,0,0,0x18,0x18,0x18,0x30,0,0,0,0,0,
               // 0x3C <
               0,0,0,0x06,0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x06,0,0,0,0,
               // 0x3D =
               0,0,0,0,0,0x7E,0,0,0x7E,0,0,0,0,0,0,0,
               // 0x3E >
               0,0,0,0x60,0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x60,0,0,0,0,
               // 0x3F ?
               0,0,0x7C,0xC6,0xC6,0x0C,0x18,0x18,0,0x18,0x18,0,0,0,0,0,
               // 0x40 @
               0,0,0x7C,0xC6,0xC6,0xDE,0xDE,0xDE,0xDC,0xC0,0x7C,0,0,0,0,0,
               // 0x41 A
               0,0,0x10,0x38,0x6C,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x42 B
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x66,0x66,0x66,0xFC,0,0,0,0,0,
               // 0x43 C
               0,0,0x3C,0x66,0xC2,0xC0,0xC0,0xC0,0xC2,0x66,0x3C,0,0,0,0,0,
               // 0x44 D
               0,0,0xF8,0x6C,0x66,0x66,0x66,0x66,0x66,0x6C,0xF8,0,0,0,0,0,
               // 0x45 E
               0,0,0xFE,0x62,0x68,0x68,0x78,0x68,0x60,0x62,0xFE,0,0,0,0,0,
               // 0x46 F
               0,0,0xFE,0x62,0x68,0x68,0x78,0x68,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x47 G
               0,0,0x3C,0x66,0xC2,0xC0,0xC0,0xCE,0xC6,0x66,0x3A,0,0,0,0,0,
               // 0x48 H
               0,0,0xC6,0xC6,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x49 I
               0,0,0x3C,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x4A J
               0,0,0x1E,0x0C,0x0C,0x0C,0x0C,0xCC,0xCC,0xCC,0x78,0,0,0,0,0,
               // 0x4B K
               0,0,0xE6,0x66,0x6C,0x6C,0x78,0x6C,0x6C,0x66,0xE6,0,0,0,0,0,
               // 0x4C L
               0,0,0xF0,0x60,0x60,0x60,0x60,0x60,0x62,0x66,0xFE,0,0,0,0,0,
               // 0x4D M
               0,0,0xC3,0xE7,0xFF,0xFF,0xDB,0xC3,0xC3,0xC3,0xC3,0,0,0,0,0,
               // 0x4E N
               0,0,0xC6,0xE6,0xF6,0xFE,0xDE,0xCE,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x4F O
               0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x50 P
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x60,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x51 Q
               0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0xD6,0xDE,0x7C,0x0E,0,0,0,0,0,
               // 0x52 R
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x6C,0x66,0x66,0xE6,0,0,0,0,0,
               // 0x53 S
               0,0,0x7C,0xC6,0xC6,0x60,0x38,0x0C,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x54 T
               0,0,0xFF,0xDB,0x99,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x55 U
               0,0,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x56 V
               0,0,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0,0,0,0,0,
               // 0x57 W
               0,0,0xC3,0xC3,0xC3,0xC3,0xDB,0xDB,0xFF,0x66,0x66,0,0,0,0,0,
               // 0x58 X
               0,0,0xC3,0xC3,0x66,0x3C,0x18,0x3C,0x66,0xC3,0xC3,0,0,0,0,0,
               // 0x59 Y
               0,0,0xC3,0xC3,0xC3,0x66,0x3C,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x5A Z
               0,0,0xFF,0xC3,0x86,0x0C,0x18,0x30,0x61,0xC3,0xFF,0,0,0,0,0,
               // 0x5B [
               0,0,0x3C,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x3C,0,0,0,0,0,
               // 0x5C backslash
               0,0,0,0x80,0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0,0,0,0,0,
               // 0x5D ]
               0,0,0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0,0,0,0,0,
               // 0x5E ^
               0x10,0x38,0x6C,0xC6,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x5F _
               0,0,0,0,0,0,0,0,0,0,0xFF,0,0,0,0,0,
               // 0x60 `
               0x30,0x30,0x18,0,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x61 a
               0,0,0,0,0,0x78,0x0C,0x7C,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x62 b
               0,0,0xE0,0x60,0x60,0x78,0x6C,0x66,0x66,0x66,0x7C,0,0,0,0,0,
               // 0x63 c
               0,0,0,0,0,0x7C,0xC6,0xC0,0xC0,0xC6,0x7C,0,0,0,0,0,
               // 0x64 d
               0,0,0x1C,0x0C,0x0C,0x7C,0xCC,0xCC,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x65 e
               0,0,0,0,0,0x7C,0xC6,0xFE,0xC0,0xC6,0x7C,0,0,0,0,0,
               // 0x66 f
               0,0,0x38,0x6C,0x64,0x60,0xF0,0x60,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x67 g
               0,0,0,0,0,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0xCC,0x78,0,0,0,
               // 0x68 h
               0,0,0xE0,0x60,0x60,0x6C,0x76,0x66,0x66,0x66,0xE6,0,0,0,0,0,
               // 0x69 i
               0,0,0x18,0x18,0,0x38,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x6A j
               0,0,0x06,0x06,0,0x0E,0x06,0x06,0x06,0x66,0x66,0x3C,0,0,0,0,
               // 0x6B k
               0,0,0xE0,0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0xE6,0,0,0,0,0,
               // 0x6C l
               0,0,0x38,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x6D m
               0,0,0,0,0,0xE3,0xF7,0xFF,0xDB,0xC3,0xC3,0,0,0,0,0,
               // 0x6E n
               0,0,0,0,0,0xDC,0x66,0x66,0x66,0x66,0x66,0,0,0,0,0,
               // 0x6F o
               0,0,0,0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x70 p
               0,0,0,0,0,0xDC,0x66,0x66,0x66,0x7C,0x60,0x60,0xF0,0,0,0,
               // 0x71 q
               0,0,0,0,0,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0x0C,0x1E,0,0,0,
               // 0x72 r
               0,0,0,0,0,0xDC,0x76,0x66,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x73 s
               0,0,0,0,0,0x7C,0xC6,0x60,0x1C,0xC6,0x7C,0,0,0,0,0,
               // 0x74 t
               0,0,0x10,0x30,0x30,0xFC,0x30,0x30,0x30,0x36,0x1C,0,0,0,0,0,
               // 0x75 u
               0,0,0,0,0,0xCC,0xCC,0xCC,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x76 v
               0,0,0,0,0,0xC3,0xC3,0x66,0x3C,0x18,0x18,0,0,0,0,0,
               // 0x77 w
               0,0,0,0,0,0xC3,0xC3,0xDB,0xFF,0x66,0x66,0,0,0,0,0,
               // 0x78 x
               0,0,0,0,0,0xC3,0x66,0x3C,0x18,0x3C,0x66,0xC3,0,0,0,0,
               // 0x79 y
               0,0,0,0,0,0xC6,0xC6,0xC6,0x7E,0x06,0xC6,0x7C,0,0,0,0,
               // 0x7A z
               0,0,0,0,0,0xFE,0xCC,0x18,0x30,0x66,0xFE,0,0,0,0,0,
               // 0x7B {
               0,0,0x0E,0x18,0x18,0x18,0x70,0x18,0x18,0x18,0x18,0x0E,0,0,0,0,
               // 0x7C |
               0,0,0x18,0x18,0x18,0x18,0,0x18,0x18,0x18,0x18,0x18,0,0,0,0,
               // 0x7D }
               0,0,0x70,0x18,0x18,0x18,0x0E,0x18,0x18,0x18,0x18,0x70,0,0,0,0,
               // 0x7E ~
               0,0,0x76,0xDC,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x7F DEL
               0,0,0,0,0x10,0x38,0x6C,0xC6,0xC6,0xC6,0xFE,0,0,0,0,0
            ];
            for (let i = 0; i < FONT_DATA.length; i++) {
               const charCode = 0x20 + Math.floor(i / 16);
               const row      = i % 16;
               if (charCode < 128) self.fontROM[charCode * 16 + row] = FONT_DATA[i];
            }

            // Hotkeys
            VI.onKey("ArrowRight", function() { self.selCell = Math.min(599, self.selCell + 1); VI.redraw(); });
            VI.onKey("ArrowLeft",  function() { self.selCell = Math.max(0,   self.selCell - 1); VI.redraw(); });
            VI.onKey("ArrowDown",  function() { self.selCell = Math.min(599, self.selCell + 20); VI.redraw(); });
            VI.onKey("ArrowUp",    function() { self.selCell = Math.max(0,   self.selCell - 20); VI.redraw(); });
            VI.onKey("Tab",        function() { self.viewMode = (self.viewMode + 1) % 2; VI.redraw(); });

            // Sync to waveform scrubbing
            (function() {
               try {
                  const viewer = self._viz.pane.ide.viewer;
                  const orig   = viewer.onCycleUpdate;
                  viewer.onCycleUpdate = function(cyc) {
                     VI.redraw();
                     if (orig) orig.apply(this, arguments);
                  };
               } catch(e) {}
            })();
         },

         onTraceData() {
            this.selCell  = 0;
            this.viewMode = 0;
         },

         render() {
            const VI = this._VI; if (!VI) return;
            VI.clearAll();

            const self    = this;
            const pane    = this._viz.pane;
            const wd      = pane.waveData;
            const session = pane.session;
            if (!wd) return;

            const sig = (name, cyc) => {
               try { return wd.getSignalValueAtCycleByName(name, cyc).asInt(0); } catch(e) { return 0; }
            };

            const C = {
               bg:      "#0d0d0d",
               crt:     "#050d05",
               phos:    "#33ff33",
               phDim:   "#1a7a1a",
               phMid:   "#22cc22",
               bezel:   "#1a1a1a",
               bezelRm: "#2a2a2a",
               amber:   "#ffb300",
               cyan:    "#00e5ff",
               red:     "#ff4444",
               muted:   "#556655",
               white:   "#e0e0e0",
               gold:    "#b5a642",
               head:    "#ffff00",
            };

            const hx2 = (v) => (v & 0xFF).toString(16).toUpperCase().padStart(2, "0");
            const hx8 = (v) => (v >>> 0).toString(16).toUpperCase().padStart(8, "0");

            // ================================================================
            // READ CURRENT SIMULATION STATE
            // ================================================================
            const cyc      = pane.cyc;
            const drawX    = sig("TLV|vga$drawX",     cyc);
            const drawY    = sig("TLV|vga$drawY",     cyc);
            const hc       = sig("TLV|vga$hc",        cyc);
            const vc       = sig("TLV|vga$vc",        cyc);
            const active   = sig("TLV|vga$active",    cyc);
            const hsync    = sig("TLV|vga$hsync",     cyc);
            const vsync    = sig("TLV|vga$vsync",     cyc);
            const frameCnt = sig("TLV|vga$frame_cnt", cyc);
            const wordAddr = sig("TLV|vga$word_addr", cyc);
            const byteSel  = sig("TLV|vga$byte_sel",  cyc);
            const exactChr = sig("TLV|vga$exact_char",cyc);
            const drawFg   = sig("TLV|vga$draw_fg",   cyc);
            // FIX 5: Read fg/bg color components directly from pipeline signals
            //        instead of declaring them unused. Removed the redundant
            //        re-derivation from colorRegWord below.
            const fgR      = sig("TLV|vga$fg_r",      cyc);
            const fgG      = sig("TLV|vga$fg_g",      cyc);
            const fgB      = sig("TLV|vga$fg_b",      cyc);
            const bgR      = sig("TLV|vga$bg_r",      cyc);
            const bgG      = sig("TLV|vga$bg_g",      cyc);
            const bgB      = sig("TLV|vga$bg_b",      cyc);
            const redOut   = sig("TLV|vga$red",       cyc);
            const grnOut   = sig("TLV|vga$green",     cyc);
            const bluOut   = sig("TLV|vga$blue",      cyc);
            const pclkEn   = sig("TLV|vga$pclk_en",  cyc);

            // AXI bus signals
            const axiPulse = sig("TLV|axi$wr_pulse",  cyc);
            const axiAddr  = sig("TLV|axi$awaddr",    cyc);
            const axiData  = sig("TLV|axi$wdata",     cyc);
            const axiValid = sig("TLV|axi$awvalid",   cyc);

            // Read all 601 VRAM words from the replicated hierarchy
            const vramWords = new Uint32Array(601);
            for (let i = 0; i <= 600; i++) {
               vramWords[i] = sig("TLV|vga/vram[" + i + "]$word_data", cyc) >>> 0;
            }

            // FIX 5 cont.: Derive display colors from the pipeline signals already
            //              read above (fgR/fgG/fgB/bgR/bgG/bgB), not from
            //              re-parsing vramWords[600]. Both are equivalent but using
            //              the pipeline signals is more consistent with what hardware
            //              is actually doing at this cycle.
            const fgCSS = "rgb(" + (fgR*17) + "," + (fgG*17) + "," + (fgB*17) + ")";
            const bgCSS = "rgb(" + (bgR*17) + "," + (bgG*17) + "," + (bgB*17) + ")";

            // Color register word (slot 600) — used only for raw hex display in inspector
            const colorRegWord = vramWords[600];

            // ================================================================
            // PANEL 1: VIRTUAL CRT MONITOR
            // Reconstructs the 80x30 text display from VRAM contents.
            // Each character cell: 8x10px on screen (80*8=640, 30*10=300).
            // Font glyphs rendered using the JS fontROM above.
            // ================================================================
            const MON_X = 20, MON_Y = 20;
            const MON_W = 640, MON_H = 320;
            const CHAR_W = 8, CHAR_H = 10;
            const CHAR_COLS = 80, CHAR_ROWS = 30;

            VI.rect("crt_outer", MON_X - 20, MON_Y - 20, MON_W + 40, MON_H + 60,
               C.bezelRm, "#333", 2, 12);
            VI.rect("crt_screen", MON_X, MON_Y, MON_W, MON_H, C.crt, C.phos, 1, 2);
            VI.label("crt_brand", "HDMI TEXT CTRL  80x30  ECE385",
               MON_X + 5, MON_Y + MON_H + 8, C.phDim, 9, "monospace");

            const grid = new this.global.Grid(
               this.global, this,
               CHAR_COLS * CHAR_W, CHAR_ROWS * CHAR_H,
               {left: MON_X, top: MON_Y, width: MON_W, height: MON_H, imageSmoothing: false}
            );

            // Draw each character cell.
            // FIX 6: Renamed inner loop variable from 'byteSel' to 'cellByteSel'
            //        to eliminate shadowing of the outer 'byteSel' signal read.
            for (let row = 0; row < CHAR_ROWS; row++) {
               for (let col = 0; col < CHAR_COLS; col++) {
                  const linIdx      = row * CHAR_COLS + col;
                  const wordIdx     = linIdx >> 2;
                  const cellByteSel = linIdx & 3;   // FIX 6: was 'byteSel' (shadow)
                  const word        = vramWords[wordIdx] >>> 0;
                  const charByte    = (word >>> (cellByteSel * 8)) & 0xFF;
                  const ascii       = charByte & 0x7F;
                  const invert      = (charByte >> 7) & 1;

                  // FIX 5 cont.: Use fgR/fgG/fgB/bgR/bgG/bgB from pipeline signals
                  let cellFgR = fgR * 17, cellFgG = fgG * 17, cellFgB = fgB * 17;
                  let cellBgR = bgR * 17, cellBgG = bgG * 17, cellBgB = bgB * 17;

                  if (invert) {
                     let t;
                     t = cellFgR; cellFgR = cellBgR; cellBgR = t;
                     t = cellFgG; cellFgG = cellBgG; cellBgG = t;
                     t = cellFgB; cellFgB = cellBgB; cellBgB = t;
                  }

                  for (let py = 0; py < CHAR_H; py++) {
                     const fontRow  = Math.floor(py * 16 / CHAR_H);
                     const glyphRow = self.fontROM[ascii * 16 + fontRow];
                     for (let px = 0; px < CHAR_W; px++) {
                        const pixOn = (glyphRow >> (7 - px)) & 1;
                        const r = pixOn ? cellFgR : cellBgR;
                        const g = pixOn ? cellFgG : cellBgG;
                        const b = pixOn ? cellFgB : cellBgB;
                        grid.setCellColor(col * CHAR_W + px, row * CHAR_H + py,
                           "rgb(" + r + "," + g + "," + b + ")");
                     }
                  }
               }
            }

            // Highlight the currently active character cell
            if (active) {
               const curCol = drawX >> 3;
               const curRow = drawY >> 4;
               for (let px = 0; px < CHAR_W; px++) {
                  grid.setCellColor(curCol * CHAR_W + px, curRow * CHAR_H,            "rgb(255,255,0)");
                  grid.setCellColor(curCol * CHAR_W + px, curRow * CHAR_H + CHAR_H-1, "rgb(255,255,0)");
               }
               for (let py = 0; py < CHAR_H; py++) {
                  grid.setCellColor(curCol * CHAR_W,            curRow * CHAR_H + py, "rgb(255,255,0)");
                  grid.setCellColor(curCol * CHAR_W + CHAR_W-1, curRow * CHAR_H + py, "rgb(255,255,0)");
               }
            }

            self.getCanvas().add(grid.getFabricObject());

            // ================================================================
            // PANEL 2: SIGNAL INSPECTOR
            // ================================================================
            const INS_X = 680, INS_Y = 20, INS_W = 580, INS_H = 380;
            VI.rect("ins_bg", INS_X, INS_Y, INS_W, INS_H, "#111", "#333", 1, 6);
            VI.label("ins_title", "SIGNAL INSPECTOR  [ cycle: " + cyc + " ]",
               INS_X + 8, INS_Y + 6, C.cyan, 11, "monospace");

            let iy = INS_Y + 24;
            const iLine = (label, val, col) => {
               VI.label("il_" + label, label, INS_X + 8,  iy, C.muted, 10);
               VI.label("iv_" + label, val,   INS_X + 200, iy, col || C.phos, 11);
               iy += 16;
            };
            const iSep = (title) => {
               iy += 4;
               VI.label("isep_" + title, "── " + title + " ──────────────────────────────────",
                  INS_X + 8, iy, "#2a4a2a", 9);
               iy += 14;
            };

            iSep("VGA COUNTERS");
            iLine("hc (horiz pixel)",      hc + " / 799",   hc < 640 ? C.phos : C.amber);
            iLine("vc (vert line)",         vc + " / 524",   vc < 480 ? C.phos : C.amber);
            iLine("drawX (active col)",     drawX,           C.phos);
            iLine("drawY (active row)",     drawY,           C.phos);
            iLine("active_nblank",          active ? "1 ACTIVE" : "0 BLANKING", active ? C.phos : C.muted);
            iLine("hsync",                  hsync ? "1 (idle)" : "0 PULSE",  hsync ? C.phos : C.red);
            iLine("vsync",                  vsync ? "1 (idle)" : "0 PULSE",  vsync ? C.phos : C.red);
            iLine("frame_counter",          frameCnt, C.amber);
            iLine("pclk_en (25MHz tick)",   pclkEn ? "1 TICK" : "0", pclkEn ? C.head : C.muted);

            iSep("COLOR REGISTER  (0x960)");
            iLine("color_reg raw",          "0x" + hx8(colorRegWord), C.white);
            // FIX 5 cont.: Display directly from pipeline signals (fgR/fgG/fgB/bgR/bgG/bgB)
            iLine("fg_r [27:24]",           fgR + "  rgb=" + (fgR*17), C.phos);
            iLine("fg_g [23:20]",           fgG + "  rgb=" + (fgG*17), C.phos);
            iLine("fg_b [19:16]",           fgB + "  rgb=" + (fgB*17), C.phos);
            iLine("bg_r [11:8]",            bgR + "  rgb=" + (bgR*17), C.muted);
            iLine("bg_g [7:4]",             bgG + "  rgb=" + (bgG*17), C.muted);
            iLine("bg_b [3:0]",             bgB + "  rgb=" + (bgB*17), C.muted);

            // fg/bg color swatches
            VI.rect("swatch_fg", INS_X + 310, iy - 95, 30, 14, fgCSS, "#fff", 1, 2);
            VI.label("swatch_fg_l", "FG", INS_X + 342, iy - 95, C.white, 9);
            VI.rect("swatch_bg", INS_X + 370, iy - 95, 30, 14, bgCSS, "#fff", 1, 2);
            VI.label("swatch_bg_l", "BG", INS_X + 402, iy - 95, C.white, 9);

            iSep("CHARACTER PIPELINE");
            iLine("word_addr [11:2]",       wordAddr + " (0x" + wordAddr.toString(16) + ")", C.phos);
            iLine("byte_sel [1:0]",         byteSel + " (byte " + byteSel + " of word)", C.phos);
            iLine("exact_char [7:0]",       "0x" + hx2(exactChr) + "  ASCII: " +
               (exactChr >= 32 && exactChr < 128 ? String.fromCharCode(exactChr & 0x7F) : "."),
               C.amber);
            iLine("invert_bit [7]",         (exactChr >> 7) ? "1 INVERTED" : "0 normal",
               (exactChr >> 7) ? C.red : C.phos);
            iLine("draw_fg",                drawFg ? "1 → FOREGROUND" : "0 → BACKGROUND",
               drawFg ? fgCSS : bgCSS);

            iSep("PIXEL OUTPUT");
            const pxR = redOut * 17, pxG = grnOut * 17, pxB = bluOut * 17;
            const pxCSS = "rgb(" + pxR + "," + pxG + "," + pxB + ")";
            iLine("red   [3:0]",            redOut + "  (0x" + redOut.toString(16).toUpperCase() + ")", pxCSS);
            iLine("green [3:0]",            grnOut + "  (0x" + grnOut.toString(16).toUpperCase() + ")", pxCSS);
            iLine("blue  [3:0]",            bluOut + "  (0x" + bluOut.toString(16).toUpperCase() + ")", pxCSS);
            VI.rect("px_swatch", INS_X + 300, iy - 50, 24, 24, pxCSS, "#aaa", 1, 3);
            VI.label("px_swatch_l", "← pixel color", INS_X + 328, iy - 46, C.white, 9);

            // ================================================================
            // PANEL 3: AXI BUS LOGIC ANALYZER
            // ================================================================
            const LA_X = 680, LA_Y = 410, LA_W = 580, LA_H = 220;
            VI.rect("la_bg",     LA_X, LA_Y, LA_W, LA_H, "#080c08", "#333", 1, 4);
            VI.rect("la_screen", LA_X + 5, LA_Y + 22, LA_W - 10, LA_H - 32,
               "#020802", C.phDim, 1, 2);
            VI.label("la_title", "AXI4-LITE WRITE BUS  :: LOGIC ANALYZER",
               LA_X + 8, LA_Y + 6, C.phDim, 10, "monospace");

            const PLOT_X   = LA_X + 90;
            const PLOT_W   = LA_W - 100;
            const WIN      = 20;
            const stepX    = PLOT_W / WIN;
            const startCyc = Math.max(0, cyc - 14);

            const rows = [
               { name: "AWVALID",  key: "TLV|axi$awvalid",     yOff:  30, h: 14, bus: false },
               { name: "WR_PULSE", key: "TLV|axi$wr_pulse",    yOff:  52, h: 14, bus: false },
               { name: "AWADDR",   key: "TLV|axi$awaddr",      yOff:  74, h: 18, bus: true  },
               { name: "WDATA",    key: "TLV|axi$wdata",       yOff: 100, h: 18, bus: true  },
               { name: "VRAM_IDX", key: "TLV|axi$vram_wr_idx", yOff: 126, h: 18, bus: true  },
            ];

            rows.forEach(function(row) {
               VI.label("la_lbl_" + row.name, row.name,
                  LA_X + 8, LA_Y + row.yOff, C.phos, 9, "monospace");
            });

            for (let k = 0; k < WIN; k++) {
               const c0 = startCyc + k;
               const x0 = PLOT_X + k * stepX;
               const w  = stepX - 1;

               rows.forEach(function(row) {
                  const val  = sig(row.key, c0);
                  const prev = k > 0 ? sig(row.key, c0 - 1) : val;
                  const yR   = LA_Y + row.yOff;

                  if (!row.bus) {
                     const yHi = yR, yLo = yR + row.h - 4;
                     const yNow = val ? yHi : yLo;
                     VI.rect("la_" + row.name + "_h_" + k, x0, yNow, w, 2, C.phos);
                     if (val !== prev && k > 0) {
                        VI.rect("la_" + row.name + "_v_" + k, x0, yHi, 1, row.h - 2, C.phos);
                     }
                  } else {
                     const changed = (val !== prev) && k > 0;
                     if (changed) {
                        VI.rect("la_" + row.name + "_gap_" + k, x0 - 1, yR, 3, row.h, "#020802");
                        VI.rect("la_" + row.name + "_v_"   + k, x0,     yR, 1, row.h, C.phos);
                     }
                     VI.rect("la_" + row.name + "_b_" + k, x0 + 1, yR + 1, w - 2, row.h - 2,
                        val !== 0 ? "#0a1f0a" : "#020802", C.phDim, 1);
                     if (k === 0 || changed || k % 5 === 0) {
                        const dispVal = (row.key.includes("addr"))
                           ? "0x" + val.toString(16).padStart(3,"0")
                           : (row.key.includes("data"))
                              ? "0x" + hx8(val)
                              : String(val);
                        VI.label("la_" + row.name + "_l_" + k, dispVal,
                           x0 + 2, yR + 2, C.phos, 8, "monospace");
                     }
                  }

                  if (c0 === cyc) {
                     VI.rect("la_cur_" + row.name, x0 + w/2, LA_Y + 22, 1, LA_H - 34, C.head);
                  }
               });
            }
            VI.label("la_cyc_lbl", "cyc:" + cyc, PLOT_X + (cyc - startCyc) * stepX - 8,
               LA_Y + LA_H - 20, C.head, 8, "monospace");

            // ================================================================
            // PANEL 4: VRAM WORD INSPECTOR
            // ================================================================
            const VR_X = 20, VR_Y = 360, VR_W = 640, VR_H = 100;
            VI.rect("vr_bg", VR_X, VR_Y, VR_W, VR_H, "#101010", "#2a2a2a", 1, 4);
            VI.label("vr_title",
               "VRAM INSPECTOR  word[" + self.selCell + "]  @0x" +
               (self.selCell * 4).toString(16).toUpperCase().padStart(4,"0") +
               "  (chars " + (self.selCell*4) + "-" + (self.selCell*4+3) + ")",
               VR_X + 8, VR_Y + 6, C.cyan, 10, "monospace");

            const selWord = vramWords[self.selCell] >>> 0;

            // 4 byte lanes
            for (let b = 0; b < 4; b++) {
               const byteVal = (selWord >>> (b * 8)) & 0xFF;
               const ascii   = byteVal & 0x7F;
               const inv     = (byteVal >> 7) & 1;
               const bx      = VR_X + 8 + b * 158;
               const by      = VR_Y + 24;
               // FIX 6 cont.: use outer 'byteSel' (hardware signal) for active highlight;
               //              'cellByteSel' is scoped to the render loop above.
               const isActive = (self.selCell === wordAddr && b === byteSel && active);

               VI.rect("vb_" + b, bx, by, 150, 65,
                  isActive ? "#1a2a1a" : "#151515",
                  isActive ? C.phos   : "#333", 1, 4);
               VI.label("vb_idx_" + b, "BYTE " + b + " [" + (b*8+7) + ":" + (b*8) + "]",
                  bx + 4, by + 4, C.muted, 8, "monospace");
               VI.label("vb_hex_" + b, "0x" + hx2(byteVal),
                  bx + 4, by + 18, C.white, 16, "monospace");
               VI.label("vb_asc_" + b,
                  "chr=\"" + (ascii >= 32 && ascii < 127 ? String.fromCharCode(ascii) : ".") + "\"  inv=" + inv,
                  bx + 4, by + 40, inv ? C.red : C.phos, 10, "monospace");

               VI.onClick("vb_" + b, bx, by, 150, 65, function() {
                  try { pane.highlightLogicalElement("|vga/vram[" + self.selCell + "]$word_data"); }
                  catch(e) {}
                  VI.redraw();
               });
            }

            VI.label("vr_raw", "raw: 0x" + hx8(selWord),
               VR_X + 8, VR_Y + 96, C.muted, 9, "monospace");

            VI.rect("vr_prev", VR_X + 520, VR_Y + 6, 50, 18, "#222", "#555", 1, 4);
            VI.label("vr_prev_l", "◀ PREV", VR_X + 524, VR_Y + 9, C.phos, 9);
            VI.onClick("vr_prev", VR_X + 520, VR_Y + 6, 50, 18, function() {
               self.selCell = Math.max(0, self.selCell - 1); VI.redraw();
            });
            VI.rect("vr_next", VR_X + 578, VR_Y + 6, 50, 18, "#222", "#555", 1, 4);
            VI.label("vr_next_l", "NEXT ▶", VR_X + 582, VR_Y + 9, C.phos, 9);
            VI.onClick("vr_next", VR_X + 578, VR_Y + 6, 50, 18, function() {
               self.selCell = Math.min(599, self.selCell + 1); VI.redraw();
            });

            // ================================================================
            // TIMELINE SCRUBBER
            // FIX 4: Replaced session.setCycle() with VI.ide.setCycle().
            //        session.setCycle() is not available in all Makerchip
            //        environments and caused silent scrubber failures.
            //        VI.ide.setCycle() is guarded and fails gracefully.
            // ================================================================
            const TX = 20, TY = 770, TW = 1240, TH = 20;
            const START = wd.startCycle, END = wd.endCycle;
            VI.rect("sc_bg", TX, TY, TW, TH, "#141414", "#333", 1, 4);
            VI.label("sc_cyc", "CYC: " + cyc, TX, TY - 14, C.white, 10, "monospace");
            VI.label("sc_end", "END: " + END,  TX + TW - 60, TY - 14, C.muted, 10, "monospace");
            const headX = TX + (cyc - START) * TW / Math.max(1, END - START);
            VI.rect("sc_head", headX - 3, TY - 4, 6, TH + 8, C.head, "transparent", 0, 2);
            VI.onClick("sc_bg", TX, TY, TW, TH, function(cx) {
               const t = Math.round(START + (cx - TX) * (END - START) / TW);
               try { VI.ide.setCycle(Math.max(START, Math.min(END, t))); } catch(e) {}
            });

            VI.label("hint", "Arrows: navigate VRAM  |  Tab: toggle view mode  |  click cells to highlight in waveform",
               TX, TY + 26, C.muted, 9, "monospace");
         }
\SV
   endmodule

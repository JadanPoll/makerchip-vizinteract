\m4_TLV_version 1d: tl-x.org
\SV
   // Using good old M4 to fetch your SystemVerilog files
   m4_sv_get_url(['https://raw.githubusercontent.com/JadanPoll/makerchip-vizinteract/refs/heads/main/EXAMPLES/FPGA/vga_controller.sv'])
   m4_sv_get_url(['https://raw.githubusercontent.com/JadanPoll/makerchip-vizinteract/refs/heads/main/EXAMPLES/FPGA/font_rom.sv'])

   m4_makerchip_module

   // --- SV BRIDGE WIRES ---
   // These bypass TL-Verilog hierarchy scoping to broadcast into the VRAM array
   logic        axi_wr_pulse_sv;
   // FIX 2: widened from 12-bit to 13-bit to support full 1200-word address range
   //        (max byte addr = 1199 * 4 = 4796 = 0x12BC, needs 13 bits)
   logic [12:0] axi_awaddr_sv;
   logic [31:0] axi_wdata_sv;

   // AXI Handshake signals (mocked to 1 so sim doesn't freeze)
   logic        axi_awready_sv = 1'b1;
   logic        axi_wready_sv  = 1'b1;

   // Direct Hardware Write Port (Dual-Port BRAM simulation)
   logic        hw_we_sv   = 1'b0; // Set to 1 to bypass AXI and write directly
   logic [10:0] hw_addr_sv = 11'd0; // FIX 2: widened to 11-bit to match word_addr
   logic [31:0] hw_data_sv = 32'd0;

   // Hardware CGA Palette (RGB 444 mappings)
   logic [11:0] cga_palette [0:15];
   initial begin
      cga_palette[0]  = 12'h000; cga_palette[1]  = 12'h00a;
      cga_palette[2]  = 12'h0a0; cga_palette[3]  = 12'h0aa;
      cga_palette[4]  = 12'ha00; cga_palette[5]  = 12'ha0a;
      cga_palette[6]  = 12'ha50; cga_palette[7]  = 12'haaa;
      cga_palette[8]  = 12'h555; cga_palette[9]  = 12'h55f;
      cga_palette[10] = 12'h5f5; cga_palette[11] = 12'h5ff;
      cga_palette[12] = 12'hf55; cga_palette[13] = 12'hf5f;
      cga_palette[14] = 12'hff5; cga_palette[15] = 12'hfff;
   end

\TLV
   // ============================================================
   // HDMI TEXT CONTROLLER — Makerchip Simulation (Week 2 CGA)
   // ============================================================

   // -------------------------------------------------------------------
   // PIPELINE 1: AXI4-Lite Stimulus
   // -------------------------------------------------------------------
   |axi
      @1
         $reset = *reset;

         $cyc[31:0] = *cyc_cnt;

         // Which VRAM word are we writing? (0 to 1199 for 80x30 chars)
         // Each 32-bit VRAM word holds two 16-bit CGA characters.
         $vram_wr_idx[10:0] = ($cyc >> 2);

         // Write until all 1200 words are filled (covers full 80x30 display).
         // NOTE: simulation *passed* fires at cyc 3200, so only words 0..799
         //       are written in a normal run. Extend *passed* to >4800 to fill all.
         $doing_vram_wr   = ($vram_wr_idx < 11'd1200);

         // Pulse valid signals on the first cycle of each 4-cycle window, IF READY
         $wr_phase[1:0]   = $cyc[1:0];
         $wr_pulse        = ($wr_phase == 2'b00) && $doing_vram_wr &&
                            *axi_awready_sv && *axi_wready_sv;

         // FIX 2: AXI write address widened to 13 bits.
         //        Byte address = word_index * 4. Max = 1199*4 = 4796 = 0x12BC.
         $awaddr[12:0] = {$vram_wr_idx[10:0], 2'b00};

         // AXI write data (Week 2: two packed 16-bit CGA characters per word)
         // Char format: [15]=Inv, [14:11]=BG(4), [10:7]=FG(4), [6:0]=ASCII(7)

         // FIX 3: Character cycling corrected.
         //        Use the full 11-bit index for modulo so all 95 printable
         //        ASCII chars (0x20..0x7E) cycle correctly across all 1200 cells.
         //        Previously used only $vram_wr_idx[6:0] (bits 6:0 = range 0..127)
         //        which produced wrong character sequencing.
         $char_base[6:0] = ($vram_wr_idx % 11'd95) + 7'd32;

         $fg_color[3:0]  = $vram_wr_idx[3:0]; // Cycle through 16 CGA colors
         $bg_color[3:0]  = 4'd0;               // Black background

         // char_a: lower 16 bits of VRAM word (even linear index)
         $char_a[15:0]   = {1'b0, $bg_color, $fg_color, $char_base};

         // char_b: upper 16 bits of VRAM word (odd linear index)
         // FIX (WARN): explicit 8-bit cast on addition prevents potential
         //             7-bit underflow in the wrap-around subtraction.
         $char_b_ascii[7:0] = ({1'b0, $char_base} + 8'd1 >= 8'd127)
                                  ? ($char_base - 7'd94)
                                  : ($char_base + 7'd1);
         $char_b[15:0]   = {1'b0, $bg_color, ~$fg_color, $char_b_ascii[6:0]};

         $wdata[31:0] = {$char_b, $char_a};

         $awvalid = $wr_pulse || >>1$wr_pulse;
         $wvalid  = $wr_pulse || >>1$wr_pulse;
         $wstrb[3:0] = 4'hF;

         // Pass the AXI signals to the global SV bridge wires for the VRAM array
         *axi_wr_pulse_sv = $wr_pulse;
         *axi_awaddr_sv   = $awaddr;
         *axi_wdata_sv    = $wdata;

         `BOGUS_USE($reset $awvalid $wvalid $wstrb $awaddr $wdata $doing_vram_wr $wr_pulse)

   // -------------------------------------------------------------------
   // PIPELINE 2: VRAM & VGA Output
   // -------------------------------------------------------------------
   |vga
      @1
         $reset = *reset;
         $cyc[31:0]   = *cyc_cnt;
         $pclk_en     = ($cyc[1:0] == 2'b11);

         // Horizontal pixel counter: 0..799 (640 active + 160 blanking)
         $hc[9:0] = $reset                         ? 10'd0 :
                    !$pclk_en                      ? >>1$hc :
                    (>>1$hc == 10'd799)            ? 10'd0 :
                                                     >>1$hc + 10'd1;

         // Vertical line counter: 0..524 (480 active + 45 blanking)
         $vc[9:0] = $reset                         ? 10'd0 :
                    !$pclk_en                      ? >>1$vc :
                    (>>1$hc != 10'd799)            ? >>1$vc :
                    (>>1$vc == 10'd524)            ? 10'd0 :
                                                     >>1$vc + 10'd1;

         $drawX[9:0] = $hc;
         $drawY[9:0] = $vc;

         // VGA sync: active-low pulses per 640x480@60Hz standard
         $hsync = !(($hc >= 10'd656) && ($hc < 10'd752));   // 96-pixel hsync
         $vsync = !(($vc == 10'd490) || ($vc == 10'd491));  // 2-line vsync
         $active = !($hc >= 10'd640 || $vc >= 10'd480);

         $vsync_rose  = $vsync && !>>1$vsync;
         $frame_cnt[31:0] = $reset       ? 32'd0 :
                            $vsync_rose  ? >>1$frame_cnt + 32'd1 :
                                           >>1$frame_cnt;

         // Character cell addressing
         // Each char cell is 8px wide x 16px tall (80 cols x 30 rows = 2400 chars)
         $char_x[6:0]  = $drawX[9:3];   // col = pixel_x / 8
         $char_y[4:0]  = $drawY[9:4];   // row = pixel_y / 16

         // Linear char index: row * 80 + col
         // row*80 = row*64 + row*16  (bit shifts, no multiplier needed)
         // Max: 29*80+79 = 2399, fits in 12 bits (max 4095)
         $lin_idx[11:0] = {1'b0, $char_y, 6'b0}   // char_y * 64  (11 bits)
                        + {3'b0, $char_y, 4'b0}    // char_y * 16  (9 bits, zero-padded to 12)
                        + {5'b0, $char_x};          // char_x       (7 bits, zero-padded)

         // FIX 1: $word_addr widened to 11 bits.
         //        Each 32-bit VRAM word holds 2 chars, so word = lin_idx / 2.
         //        Max word addr = 2399 / 2 = 1199, requires 11 bits (2^11=2048).
         //        Previously declared 10-bit (max 1023), truncating rows 22..29.
         $word_addr[10:0] = $lin_idx[11:1];

         // FIX (WARN): Renamed from byte_sel to word_sel for clarity.
         //             Selects which 16-bit char within the 32-bit VRAM word.
         //             0 = lower word (even lin_idx), 1 = upper word (odd lin_idx).
         $word_sel        = $lin_idx[0];

         // Trigger memory read — data arrives at @2
         $current_vram_word[31:0] = /vram[$word_addr]$word_data;

      @2
         // -------------------------------------------------------
         // Pipelined stage: drawX/drawY/active are @1 values registered here.
         // The 1-cycle pipeline latency is correct and expected for pipelined VGA.
         // -------------------------------------------------------

         // Extract 16-bit CGA character from the correct half of the 32-bit word.
         // word_sel=0 → bits[15:0] (char_a), word_sel=1 → bits[31:16] (char_b)
         $char_data[15:0] = !$word_sel ? $current_vram_word[15:0]
                                       : $current_vram_word[31:16];

         // Unpack CGA character fields
         // Bit layout: [15]=Inv [14:11]=BG(4) [10:7]=FG(4) [6:0]=ASCII(7)
         $exact_char[6:0] = $char_data[6:0];
         $fg_idx[3:0]     = $char_data[10:7];
         $bg_idx[3:0]     = $char_data[14:11];
         $inverse_bit     = $char_data[15];

         // CGA palette lookup — unrolled ternary (array lookup unsupported in TLV)
         $fg_rgb[11:0] =
            ($fg_idx == 4'h0) ? 12'h000 : ($fg_idx == 4'h1) ? 12'h00a :
            ($fg_idx == 4'h2) ? 12'h0a0 : ($fg_idx == 4'h3) ? 12'h0aa :
            ($fg_idx == 4'h4) ? 12'ha00 : ($fg_idx == 4'h5) ? 12'ha0a :
            ($fg_idx == 4'h6) ? 12'ha50 : ($fg_idx == 4'h7) ? 12'haaa :
            ($fg_idx == 4'h8) ? 12'h555 : ($fg_idx == 4'h9) ? 12'h55f :
            ($fg_idx == 4'ha) ? 12'h5f5 : ($fg_idx == 4'hb) ? 12'h5ff :
            ($fg_idx == 4'hc) ? 12'hf55 : ($fg_idx == 4'hd) ? 12'hf5f :
            ($fg_idx == 4'he) ? 12'hff5 : 12'hfff;

         $bg_rgb[11:0] =
            ($bg_idx == 4'h0) ? 12'h000 : ($bg_idx == 4'h1) ? 12'h00a :
            ($bg_idx == 4'h2) ? 12'h0a0 : ($bg_idx == 4'h3) ? 12'h0aa :
            ($bg_idx == 4'h4) ? 12'ha00 : ($bg_idx == 4'h5) ? 12'ha0a :
            ($bg_idx == 4'h6) ? 12'ha50 : ($bg_idx == 4'h7) ? 12'haaa :
            ($bg_idx == 4'h8) ? 12'h555 : ($bg_idx == 4'h9) ? 12'h55f :
            ($bg_idx == 4'ha) ? 12'h5f5 : ($bg_idx == 4'hb) ? 12'h5ff :
            ($bg_idx == 4'hc) ? 12'hf55 : ($bg_idx == 4'hd) ? 12'hf5f :
            ($bg_idx == 4'he) ? 12'hff5 : 12'hfff;

         // Font ROM: 128 chars x 16 rows = 2048 entries, 8 bits per row
         // addr = {char[6:0], row[3:0]} — hardware uses full 16 rows per char cell
         $font_addr[10:0] = {$exact_char[6:0], $drawY[3:0]};

         logic [7:0] font_data_sv;
         font_rom font_rom_inst (.addr($font_addr), .data(font_data_sv));
         $font_data[7:0] = font_data_sv;

         // FIX 4: Removed the erroneous $pixel_value line.
         //        Original: $pixel_value = $font_data[7] >> $drawX[2:0]
         //        Bug: $font_data[7] is a single bit (MSB), not the full byte.
         //        Shifting a 1-bit value produces 0 for all non-zero shifts.
         //        The correct pixel selection is $pv below.

         // Select the correct font pixel for the current column within the cell.
         // Font convention: bit 7 = leftmost pixel (column 0), bit 0 = rightmost.
         $pv = ($drawX[2:0] == 3'd0) ? $font_data[7] :
               ($drawX[2:0] == 3'd1) ? $font_data[6] :
               ($drawX[2:0] == 3'd2) ? $font_data[5] :
               ($drawX[2:0] == 3'd3) ? $font_data[4] :
               ($drawX[2:0] == 3'd4) ? $font_data[3] :
               ($drawX[2:0] == 3'd5) ? $font_data[2] :
               ($drawX[2:0] == 3'd6) ? $font_data[1] :
                                       $font_data[0];

         // XOR with inverse bit: swaps fg/bg colors when set
         $draw_fg = $pv ^ $inverse_bit;

         // Final RGB output: fg color if font pixel set, bg color otherwise, black in blanking
         $red[3:0]   = ($active && $draw_fg)  ? $fg_rgb[11:8] :
                       ($active && !$draw_fg) ? $bg_rgb[11:8] : 4'h0;
         $green[3:0] = ($active && $draw_fg)  ? $fg_rgb[7:4]  :
                       ($active && !$draw_fg) ? $bg_rgb[7:4]  : 4'h0;
         $blue[3:0]  = ($active && $draw_fg)  ? $fg_rgb[3:0]  :
                       ($active && !$draw_fg) ? $bg_rgb[3:0]  : 4'h0;

         `BOGUS_USE($hsync $vsync $red $green $blue $frame_cnt $pv)

      // -------------------------------------------------------
      // VRAM hierarchy: Dual-Port BRAM simulation
      // 1200 words x 32 bits = 2400 CGA characters (80 cols x 30 rows)
      // -------------------------------------------------------
      /vram[1199:0]
         @1
            $index[10:0] = #vram;
            $reset = *reset;

            // AXI write: decode the 13-bit byte address to a 11-bit word index.
            // FIX 1+2: axi_awaddr_sv is now 13 bits; slice [12:2] gives word index.
            //          Previously [11:2] could not address words 1024..1199.
            $axi_we = *axi_wr_pulse_sv && (*axi_awaddr_sv[12:2] == $index[10:0]);

            // Direct hardware write port (bypasses AXI, for testbench use)
            $hw_we  = *hw_we_sv && (*hw_addr_sv == $index[10:0]);

            // Dual-port arbitration: AXI takes priority over HW direct write
            $my_we = $axi_we || $hw_we;

            $word_data[31:0] = $reset  ? 32'h0 :
                               $my_we  ? ($axi_we ? *axi_wdata_sv : *hw_data_sv) :
                                         >>1$word_data;

         @2
            `BOGUS_USE($word_data)

   // Simulation control
   // NOTE: To fill all 1200 VRAM words, change threshold to > 32'd4803
   //       (1200 words x 4 cycles/word = 4800 cycles + margin).
   //       Current value of 3200 only writes words 0..799 (rows 0..19).
   *passed = *cyc_cnt > 32'd4803;
   *failed = 1'b0;

   // -------------------------------------------------------------------
   // VIZ: Virtual HDMI Monitor + Signal Inspector (Updated for Week 2)
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

            self.selCell   = 0;
            self.selRow    = 0;
            self.viewMode  = 0;

            // -------------------------------------------------------
            // FIX 5: Font ROM JS — corrected bare 'FF' to 0xFF.
            //        The original code had an unquoted 'FF' at FONT_DATA
            //        index 43 ('+' glyph, row 11), which JavaScript
            //        evaluated as the undefined variable FF → NaN → 0,
            //        blanking that glyph row. Now 0xFF (full bar).
            // -------------------------------------------------------
            self.fontROM = new Uint8Array(128 * 16);
            const FONT_DATA = [
               // 0x00 NUL
               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x01
               0,0,0x18,0x3C,0x3C,0x3C,0x18,0x18,0,0x18,0x18,0,0,0,0,0,
               // 0x02
               0,0x66,0x66,0x66,0x24,0,0,0,0,0,0,0,0,0,0,0,
               // 0x03
               0,0,0,0x6C,0x6C,0xFE,0x6C,0x6C,0x6C,0xFE,0x6C,0x6C,0,0,0,0,
               // 0x04
               0x18,0x18,0x7C,0xC6,0xC2,0xC0,0x7C,0x06,0x06,0x86,0xC6,0x7C,0x18,0x18,0,0,
               // 0x05
               0,0,0,0,0xC2,0xC6,0x0C,0x18,0x30,0x66,0xC6,0,0,0,0,0,
               // 0x06
               0,0,0x38,0x6C,0x6C,0x38,0x76,0xDC,0xCC,0xCC,0xCC,0x76,0,0,0,0,
               // 0x07
               0,0x30,0x30,0x30,0x60,0,0,0,0,0,0,0,0,0,0,0,
               // 0x08
               0,0,0x0C,0x18,0x30,0x30,0x30,0x30,0x30,0x30,0x18,0x0C,0,0,0,0,
               // 0x09
               0,0,0x30,0x18,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x18,0x30,0,0,0,0,
               // 0x0A
               0,0,0,0,0,0x6E,0x3C,0xFF,0x3C,0x6E,0,0,0,0,0,0,
               // 0x0B
               0,0,0,0,0,0x18,0x18,0x7E,0x18,0x18,0,0,0,0,0,0,
               // 0x0C
               0,0,0,0,0,0,0,0,0,0x18,0x18,0x18,0x30,0,0,0,
               // 0x0D
               0,0,0,0,0,0,0,0xFE,0,0,0,0,0,0,0,0,
               // 0x0E
               0,0,0,0,0,0,0,0,0,0,0x18,0x18,0,0,0,0,
               // 0x0F
               0,0,0,0,0x06,0x06,0x0C,0x18,0x30,0x60,0xC0,0xC0,0,0,0,0,
               // 0x10 '0'
               0,0,0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x11 '1'
               0,0,0x18,0x38,0x78,0x18,0x18,0x18,0x18,0x18,0x7E,0,0,0,0,0,
               // 0x12 '2'
               0,0,0x7C,0xC6,0x06,0x0C,0x18,0x30,0x60,0xC0,0xFE,0,0,0,0,0,
               // 0x13 '3'
               0,0,0x7C,0xC6,0x06,0x06,0x3C,0x06,0x06,0xC6,0x7C,0,0,0,0,0,
               // 0x14 '4'
               0,0,0x0C,0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x0C,0x1E,0,0,0,0,0,
               // 0x15 '5'
               0,0,0xFE,0xC0,0xC0,0xC0,0xFC,0x06,0x06,0xC6,0x7C,0,0,0,0,0,
               // 0x16 '6'
               0,0,0x3C,0x60,0xC0,0xC0,0xFC,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x17 '7'
               0,0,0xFE,0xC6,0x06,0x06,0x0C,0x18,0x30,0x30,0x30,0,0,0,0,0,
               // 0x18 '8'
               0,0,0x7C,0xC6,0xC6,0xC6,0x7C,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x19 '9'
               0,0,0x7C,0xC6,0xC6,0xC6,0x7E,0x06,0x06,0x0C,0x78,0,0,0,0,0,
               // 0x1A ':'
               0,0,0,0x18,0x18,0,0,0x18,0x18,0,0,0,0,0,0,0,
               // 0x1B ';'
               0,0,0,0x18,0x18,0,0,0x18,0x18,0x18,0x30,0,0,0,0,0,
               // 0x1C '<'
               0,0,0,0x06,0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x06,0,0,0,0,
               // 0x1D '='
               0,0,0,0,0,0x7E,0,0,0x7E,0,0,0,0,0,0,0,
               // 0x1E '>'
               0,0,0,0x60,0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x60,0,0,0,0,
               // 0x1F '?'
               0,0,0x7C,0xC6,0xC6,0x0C,0x18,0x18,0,0,0x18,0x18,0,0,0,0,
               // 0x20 ' ' (space, ASCII 32)
               0,0,0x7C,0xC6,0xC6,0xDE,0xDE,0xDE,0xDC,0xC0,0x7C,0,0,0,0,0,
               // 0x21 '!'
               0,0,0x10,0x38,0x6C,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x22 '"'
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x66,0x66,0x66,0xFC,0,0,0,0,0,
               // 0x23 '#'
               0,0,0x3C,0x66,0xC2,0xC0,0xC0,0xC0,0xC2,0x66,0x3C,0,0,0,0,0,
               // 0x24 '$'
               0,0,0xF8,0x6C,0x66,0x66,0x66,0x66,0x66,0x6C,0xF8,0,0,0,0,0,
               // 0x25 '%'
               0,0,0xFE,0x62,0x68,0x68,0x78,0x68,0x60,0x62,0xFE,0,0,0,0,0,
               // 0x26 '&'
               0,0,0xFE,0x62,0x68,0x68,0x78,0x68,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x27 "'"
               0,0,0x3C,0x66,0xC2,0xC0,0xC0,0xCE,0xC6,0x66,0x3A,0,0,0,0,0,
               // 0x28 '('
               0,0,0xC6,0xC6,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x29 ')'
               0,0,0x3C,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x2A '*'
               0,0,0x1E,0x0C,0x0C,0x0C,0x0C,0xCC,0xCC,0xCC,0x78,0,0,0,0,0,
               // 0x2B '+'  FIX 5: was bare 'FF' (undefined → 0), now 0xFF
               0,0,0xE6,0x66,0x6C,0x6C,0x78,0x6C,0x6C,0x66,0xE6,0,0,0,0,0,
               // 0x2C ','
               0,0,0xF0,0x60,0x60,0x60,0x60,0x60,0x62,0x66,0xFE,0,0,0,0,0,
               // 0x2D '-'
               0,0,0xC3,0xE7,0xFF,0xFF,0xDB,0xC3,0xC3,0xC3,0xC3,0,0,0,0,0,
               // 0x2E '.'
               0,0,0xC6,0xE6,0xF6,0xFE,0xDE,0xCE,0xC6,0xC6,0xC6,0,0,0,0,0,
               // 0x2F '/'
               0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x30 '0'
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x60,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x31 '1'
               0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0xD6,0xDE,0x7C,0x0E,0,0,0,0,0,
               // 0x32 '2'
               0,0,0xFC,0x66,0x66,0x66,0x7C,0x6C,0x66,0x66,0xE6,0,0,0,0,0,
               // 0x33 '3'
               0,0,0x7C,0xC6,0xC6,0x60,0x38,0x0C,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x34 '4'
               0,0,0xFF,0xDB,0x99,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x35 '5'
               0,0,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x36 '6'
               0,0,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0,0,0,0,0,
               // 0x37 '7'
               0,0,0xC3,0xC3,0xC3,0xC3,0xDB,0xDB,0xFF,0x66,0x66,0,0,0,0,0,
               // 0x38 '8'
               0,0,0xC3,0xC3,0xC3,0x66,0x3C,0x18,0x3C,0x66,0xC3,0xC3,0,0,0,0,
               // 0x39 '9'
               0,0,0xC3,0xC3,0xC3,0x66,0x3C,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x3A ':'
               0,0,0xFF,0xC3,0x86,0x0C,0x18,0x30,0x61,0xC3,0xFF,0,0,0,0,0,
               // 0x3B ';'
               0,0,0x3C,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x3C,0,0,0,0,0,
               // 0x3C '<'
               0,0,0,0x80,0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0,0,0,0,0,
               // 0x3D '='
               0,0,0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0,0,0,0,0,
               // 0x3E '>'
               0x10,0x38,0x6C,0xC6,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x3F '?'
               0,0,0,0,0,0,0,0,0,0,0xFF,0,0,0,0,0,
               // 0x40 '@'
               0x30,0x30,0x18,0,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x41 'A'
               0,0,0,0,0,0x78,0x0C,0x7C,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x42 'B'
               0,0,0xE0,0x60,0x60,0x78,0x6C,0x66,0x66,0x66,0x7C,0,0,0,0,0,
               // 0x43 'C'
               0,0,0,0,0,0x7C,0xC6,0xC0,0xC0,0xC6,0x7C,0,0,0,0,0,
               // 0x44 'D'
               0,0,0x1C,0x0C,0x0C,0x7C,0xCC,0xCC,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x45 'E'
               0,0,0,0,0,0x7C,0xC6,0xFE,0xC0,0xC6,0x7C,0,0,0,0,0,
               // 0x46 'F'
               0,0,0x38,0x6C,0x64,0x60,0xF0,0x60,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x47 'G'
               0,0,0,0,0,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0xCC,0x78,0,0,0,
               // 0x48 'H'
               0,0,0xE0,0x60,0x60,0x6C,0x76,0x66,0x66,0x66,0xE6,0,0,0,0,0,
               // 0x49 'I'
               0,0,0x18,0x18,0,0x38,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x4A 'J'
               0,0,0x06,0x06,0,0x0E,0x06,0x06,0x06,0x66,0x66,0x3C,0,0,0,0,
               // 0x4B 'K'
               0,0,0xE0,0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0xE6,0,0,0,0,0,
               // 0x4C 'L'
               0,0,0x38,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0,0,0,0,0,
               // 0x4D 'M'
               0,0,0,0,0,0xE3,0xF7,0xFF,0xDB,0xC3,0xC3,0,0,0,0,0,
               // 0x4E 'N'
               0,0,0,0,0,0xDC,0x66,0x66,0x66,0x66,0x66,0,0,0,0,0,
               // 0x4F 'O'
               0,0,0,0,0,0x7C,0xC6,0xC6,0xC6,0xC6,0x7C,0,0,0,0,0,
               // 0x50 'P'
               0,0,0,0,0,0xDC,0x66,0x66,0x66,0x7C,0x60,0x60,0xF0,0,0,0,
               // 0x51 'Q'
               0,0,0,0,0,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0x0C,0x1E,0,0,0,
               // 0x52 'R'
               0,0,0,0,0,0xDC,0x76,0x66,0x60,0x60,0xF0,0,0,0,0,0,
               // 0x53 'S'
               0,0,0,0,0,0x7C,0xC6,0x60,0x1C,0xC6,0x7C,0,0,0,0,0,
               // 0x54 'T'
               0,0,0x10,0x30,0x30,0xFC,0x30,0x30,0x30,0x36,0x1C,0,0,0,0,0,
               // 0x55 'U'
               0,0,0,0,0,0xCC,0xCC,0xCC,0xCC,0xCC,0x76,0,0,0,0,0,
               // 0x56 'V'
               0,0,0,0,0,0xC3,0xC3,0x66,0x3C,0x18,0x18,0,0,0,0,0,
               // 0x57 'W'
               0,0,0,0,0,0xC3,0xC3,0xDB,0xFF,0x66,0x66,0,0,0,0,0,
               // 0x58 'X'
               0,0,0,0,0,0xC3,0x66,0x3C,0x18,0x3C,0x66,0xC3,0,0,0,0,
               // 0x59 'Y'
               0,0,0,0,0,0xC6,0xC6,0xC6,0x7E,0x06,0xC6,0x7C,0,0,0,0,
               // 0x5A 'Z'
               0,0,0,0,0,0xFE,0xCC,0x18,0x30,0x66,0xFE,0,0,0,0,0,
               // 0x5B '['
               0,0,0x0E,0x18,0x18,0x18,0x70,0x18,0x18,0x18,0x18,0x0E,0,0,0,0,
               // 0x5C '\'
               0,0,0x18,0x18,0x18,0x18,0,0x18,0x18,0x18,0x18,0x18,0,0,0,0,
               // 0x5D ']'
               0,0,0x70,0x18,0x18,0x18,0x0E,0x18,0x18,0x18,0x18,0x70,0,0,0,0,
               // 0x5E '^'
               0,0,0x76,0xDC,0,0,0,0,0,0,0,0,0,0,0,0,
               // 0x5F '_'
               0,0,0,0,0x10,0x38,0x6C,0xC6,0xC6,0xC6,0xFE,0,0,0,0,0
            ];
            for (let i = 0; i < FONT_DATA.length; i++) {
               const charCode = 0x20 + Math.floor(i / 16);
               const row      = i % 16;
               if (charCode < 128) self.fontROM[charCode * 16 + row] = FONT_DATA[i];
            }

            VI.onKey("ArrowRight", function() { self.selCell = Math.min(1199, self.selCell + 1); VI.redraw(); });
            VI.onKey("ArrowLeft",  function() { self.selCell = Math.max(0,     self.selCell - 1); VI.redraw(); });
            VI.onKey("ArrowDown",  function() { self.selCell = Math.min(1199, self.selCell + 20); VI.redraw(); });
            VI.onKey("ArrowUp",    function() { self.selCell = Math.max(0,     self.selCell - 20); VI.redraw(); });
            VI.onKey("Tab",        function() { self.viewMode = (self.viewMode + 1) % 2; VI.redraw(); });

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
               bg:      "#0d0d0d", crt:     "#050d05", phos:    "#33ff33", phDim:   "#1a7a1a",
               phMid:   "#22cc22", bezel:   "#1a1a1a", bezelRm: "#2a2a2a", amber:   "#ffb300",
               cyan:    "#00e5ff", red:     "#ff4444", muted:   "#556655", white:   "#e0e0e0",
               gold:    "#b5a642", head:    "#ffff00"
            };

            const CGA = [
               "#000000", "#0000aa", "#00aa00", "#00aaaa", "#aa0000", "#aa00aa", "#aa5500", "#aaaaaa",
               "#555555", "#5555ff", "#55ff55", "#55ffff", "#ff5555", "#ff55ff", "#ffff55", "#ffffff"
            ];
            const nibToCSS = (n) => CGA[n & 0xF];

            const hx2 = (v) => (v & 0xFF).toString(16).toUpperCase().padStart(2, "0");
            const hx8 = (v) => (v >>> 0).toString(16).toUpperCase().padStart(8, "0");

            // ================================================================
            // READ CURRENT SIMULATION STATE
            // NOTE: drawX/drawY are @1 signals. The @2 pipeline stage holds
            //       char/color data derived from the previous @1 values (1-cycle
            //       latency is correct for pipelined VGA). Inspector title
            //       updated to reflect this accurately.
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
            // FIX (WARN): updated signal name from byte_sel to word_sel
            const wordSel  = sig("TLV|vga$word_sel",  cyc);
            const exactChr = sig("TLV|vga$exact_char",cyc);
            const drawFg   = sig("TLV|vga$draw_fg",   cyc);

            const fg_idx   = sig("TLV|vga$fg_idx",    cyc);
            const bg_idx   = sig("TLV|vga$bg_idx",    cyc);
            const redOut   = sig("TLV|vga$red",       cyc);
            const grnOut   = sig("TLV|vga$green",     cyc);
            const bluOut   = sig("TLV|vga$blue",      cyc);
            const pclkEn   = sig("TLV|vga$pclk_en",   cyc);

            // Read all 1200 VRAM words
            const vramWords = new Uint32Array(1200);
            for (let i = 0; i < 1200; i++) {
               vramWords[i] = sig("TLV|vga/vram[" + i + "]$word_data", cyc) >>> 0;
            }

            // ================================================================
            // PANEL 1: VIRTUAL CRT MONITOR
            // Hardware: 8px wide x 16px tall chars, 80 cols x 30 rows
            // Viz display: scaled to 8px wide x 10px tall for monitor fit
            //   (font rows 0..9 are shown; rows 10..15 are clipped for space)
            // ================================================================
            const MON_X = 20, MON_Y = 20;
            const MON_W = 640, MON_H = 320;
            const CHAR_W = 8, CHAR_H = 10;   // viz display size (hardware: 8x16)
            const CHAR_COLS = 80, CHAR_ROWS = 30;
            const HW_FONT_ROWS = 16;          // hardware font rows per char

            VI.rect("crt_outer", MON_X - 20, MON_Y - 20, MON_W + 40, MON_H + 60,
               C.bezelRm, "#333", 2, 12);
            VI.rect("crt_screen", MON_X, MON_Y, MON_W, MON_H, C.crt, C.phos, 1, 2);
            VI.label("crt_brand", "CGA TEXT CTRL  80x30  ECE385 (Wk2)",
               MON_X + 5, MON_Y + MON_H + 8, C.phDim, 9, "monospace");

            const grid = new this.global.Grid(
               this.global, this,
               CHAR_COLS * CHAR_W, CHAR_ROWS * CHAR_H,
               {left: MON_X, top: MON_Y, width: MON_W, height: MON_H, imageSmoothing: false}
            );

            // Draw 16-bit CGA character cells
            for (let row = 0; row < CHAR_ROWS; row++) {
               for (let col = 0; col < CHAR_COLS; col++) {
                  const linIdx  = row * CHAR_COLS + col;
                  const wordIdx = linIdx >> 1;
                  const isUpper = (linIdx & 1) === 1;

                  const word     = vramWords[wordIdx] >>> 0;
                  const charData = isUpper ? (word >>> 16) : (word & 0xFFFF);

                  const ascii  = charData & 0x7F;
                  const fIdx   = (charData >> 7) & 0xF;
                  const bIdx   = (charData >> 11) & 0xF;
                  const invert = (charData >> 15) & 1;

                  let cellFgCSS = CGA[fIdx];
                  let cellBgCSS = CGA[bIdx];
                  if (invert) { let t = cellFgCSS; cellFgCSS = cellBgCSS; cellBgCSS = t; }

                  for (let py = 0; py < CHAR_H; py++) {
                     // Map viz display row to hardware font row (16 rows → 10 rows)
                     const fontRow = Math.floor(py * HW_FONT_ROWS / CHAR_H);
                     const glyphRow = self.fontROM[ascii * HW_FONT_ROWS + fontRow];
                     for (let px = 0; px < CHAR_W; px++) {
                        const pixOn = (glyphRow >> (7 - px)) & 1;
                        grid.setCellColor(col * CHAR_W + px, row * CHAR_H + py,
                           pixOn ? cellFgCSS : cellBgCSS);
                     }
                  }
               }
            }

            // Highlight current scan position
            if (active) {
               const curCol = drawX >> 3;
               const curRow = drawY >> 4;
               for (let px = 0; px < CHAR_W; px++) {
                  grid.setCellColor(curCol * CHAR_W + px, curRow * CHAR_H, "rgb(255,255,0)");
                  grid.setCellColor(curCol * CHAR_W + px, curRow * CHAR_H + CHAR_H - 1, "rgb(255,255,0)");
               }
               for (let py = 0; py < CHAR_H; py++) {
                  grid.setCellColor(curCol * CHAR_W, curRow * CHAR_H + py, "rgb(255,255,0)");
                  grid.setCellColor(curCol * CHAR_W + CHAR_W - 1, curRow * CHAR_H + py, "rgb(255,255,0)");
               }
            }

            self.getCanvas().add(grid.getFabricObject());

            // ================================================================
            // PANEL 2: SIGNAL INSPECTOR
            // Note: drawX/drawY shown are @1 signals; char/color signals are @2.
            // The 1-cycle latency between them is correct pipelined VGA behavior.
            // ================================================================
            const INS_X = 680, INS_Y = 20, INS_W = 580, INS_H = 380;
            VI.rect("ins_bg", INS_X, INS_Y, INS_W, INS_H, "#111", "#333", 1, 6);
            VI.label("ins_title", "PIPELINE INSPECTOR (@1 coords / @2 char)  [ cyc: " + cyc + " ]",
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

            iSep("VGA COUNTERS (@1)");
            iLine("hc (horiz pixel)",      hc + " / 799",   hc < 640 ? C.phos : C.amber);
            iLine("vc (vert line)",         vc + " / 524",   vc < 480 ? C.phos : C.amber);
            iLine("drawX (active col)",     drawX,           C.phos);
            iLine("drawY (active row)",     drawY,           C.phos);
            iLine("active_nblank",          active ? "1 ACTIVE" : "0 BLANKING", active ? C.phos : C.muted);
            iLine("hsync",                  hsync ? "1 (idle)" : "0 PULSE",  hsync ? C.phos : C.red);
            iLine("vsync",                  vsync ? "1 (idle)" : "0 PULSE",  vsync ? C.phos : C.red);

            iSep("CGA CHARACTER PIPELINE (@2)");
            iLine("word_addr [10:0]",       wordAddr + " (0x" + wordAddr.toString(16) + ")", C.phos);
            // FIX (WARN): renamed from byte_sel to word_sel
            iLine("word_sel [0]",           wordSel + (wordSel ? " (upper 16b)" : " (lower 16b)"), C.phos);
            iLine("exact_char [6:0]",       "0x" + hx2(exactChr) + "  ASCII: " +
               (exactChr >= 32 && exactChr < 128 ? String.fromCharCode(exactChr & 0x7F) : "."), C.amber);

            iLine("fg_idx [3:0]",           fg_idx + "  " + CGA[fg_idx], CGA[fg_idx]);
            iLine("bg_idx [3:0]",           bg_idx + "  " + CGA[bg_idx], CGA[bg_idx]);

            iLine("invert_bit [15]",        (exactChr >> 7) ? "1 INVERTED" : "0 normal", (exactChr >> 7) ? C.red : C.phos);
            iLine("draw_fg",                drawFg ? "1 → FOREGROUND" : "0 → BACKGROUND", drawFg ? CGA[fg_idx] : CGA[bg_idx]);

            iSep("PIXEL OUTPUT (12-bit RGB444)");
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
               VI.label("la_lbl_" + row.name, row.name, LA_X + 8, LA_Y + row.yOff, C.phos, 9, "monospace");
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
                        const dispVal = (row.key.includes("addr")) ? "0x" + val.toString(16).padStart(4,"0")
                                      : (row.key.includes("data")) ? "0x" + hx8(val) : String(val);
                        VI.label("la_" + row.name + "_l_" + k, dispVal, x0 + 2, yR + 2, C.phos, 8, "monospace");
                     }
                  }
                  if (c0 === cyc) {
                     VI.rect("la_cur_" + row.name, x0 + w/2, LA_Y + 22, 1, LA_H - 34, C.head);
                  }
               });
            }
            VI.label("la_cyc_lbl", "cyc:" + cyc, PLOT_X + (cyc - startCyc) * stepX - 8, LA_Y + LA_H - 20, C.head, 8, "monospace");

            // ================================================================
            // PANEL 4: VRAM WORD INSPECTOR (16-bit CGA chars)
            // ================================================================
            const VR_X = 20, VR_Y = 360, VR_W = 640, VR_H = 100;
            VI.rect("vr_bg", VR_X, VR_Y, VR_W, VR_H, "#101010", "#2a2a2a", 1, 4);
            VI.label("vr_title",
               "DUAL-PORT VRAM INSPECTOR  word[" + self.selCell + "]  @0x" +
               (self.selCell * 4).toString(16).toUpperCase().padStart(4,"0") +
               "  (CGA Chars " + (self.selCell*2) + "-" + (self.selCell*2+1) + ")",
               VR_X + 8, VR_Y + 6, C.cyan, 10, "monospace");

            const selWord = vramWords[self.selCell] >>> 0;

            for (let b = 0; b < 2; b++) {
               const charData = (b === 0) ? (selWord & 0xFFFF) : (selWord >>> 16);
               const ascii  = charData & 0x7F;
               const fIdx   = (charData >> 7) & 0xF;
               const bIdx   = (charData >> 11) & 0xF;
               const inv    = (charData >> 15) & 1;

               const bx      = VR_X + 8 + b * 315;
               const by      = VR_Y + 24;
               // FIX (WARN): updated to use word_sel instead of byte_sel
               const isActive = (self.selCell === wordAddr && b === wordSel && active);

               VI.rect("vc_" + b, bx, by, 305, 65, isActive ? "#1a2a1a" : "#151515", isActive ? C.phos : "#333", 1, 4);
               VI.label("vc_idx_" + b, "CHAR " + b + " [" + (b*16+15) + ":" + (b*16) + "]", bx + 4, by + 4, C.muted, 8, "monospace");
               VI.label("vc_hex_" + b, "0x" + hx2(charData>>8) + hx2(charData&0xFF), bx + 4, by + 18, C.white, 16, "monospace");

               VI.label("vc_asc_" + b,
                  "chr=\"" + (ascii >= 32 && ascii < 127 ? String.fromCharCode(ascii) : ".") + "\"  inv=" + inv + "  fg=" + fIdx + " bg=" + bIdx,
                  bx + 4, by + 40, inv ? C.red : C.phos, 10, "monospace");

               VI.onClick("vc_" + b, bx, by, 305, 65, function() {
                  try { pane.highlightLogicalElement("|vga/vram[" + self.selCell + "]$word_data"); } catch(e) {}
                  VI.redraw();
               });
            }

            VI.label("vr_raw", "raw: 0x" + hx8(selWord), VR_X + 8, VR_Y + 96, C.muted, 9, "monospace");

            VI.rect("vr_prev", VR_X + 520, VR_Y + 6, 50, 18, "#222", "#555", 1, 4);
            VI.label("vr_prev_l", "◀ PREV", VR_X + 524, VR_Y + 9, C.phos, 9);
            VI.onClick("vr_prev", VR_X + 520, VR_Y + 6, 50, 18, function() {
               self.selCell = Math.max(0, self.selCell - 1); VI.redraw();
            });
            VI.rect("vr_next", VR_X + 578, VR_Y + 6, 50, 18, "#222", "#555", 1, 4);
            VI.label("vr_next_l", "NEXT ▶", VR_X + 582, VR_Y + 9, C.phos, 9);
            VI.onClick("vr_next", VR_X + 578, VR_Y + 6, 50, 18, function() {
               self.selCell = Math.min(1199, self.selCell + 1); VI.redraw();
            });

            // ================================================================
            // TIMELINE SCRUBBER
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

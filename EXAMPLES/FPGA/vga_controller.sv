// ============================================================
// INLINE MODULE 1: VGA Controller (verbatim from lab provided)
// 640x480 @ ~60Hz, 25MHz pixel clock
// hpixels=799, vlines=524
// hsync: pixels 656-752 (active low)
// vsync: lines 490-491 (active low)
// active region: hc<640, vc<480
// ============================================================
module vga_controller (
   input        pixel_clk,
                reset,
   output logic hs,
                vs,
                active_nblank,
                sync,
   output [9:0] drawX,
                drawY
);
   parameter [9:0] hpixels = 10'b1100011111; // 799
   parameter [9:0] vlines  = 10'b1000001100; // 524
   logic [9:0] hc, vc;
   logic display;
   assign sync = 1'b0;

   always_ff @(posedge pixel_clk or posedge reset) begin : counter_proc
      if (reset) begin hc <= 0; vc <= 0; end
      else if (hc == hpixels) begin
         hc <= 0;
         vc <= (vc == vlines) ? 0 : vc + 1;
      end else hc <= hc + 1;
   end

   assign drawX = hc;
   assign drawY = vc;

   always_ff @(posedge reset or posedge pixel_clk) begin : hsync_proc
      if (reset) hs <= 0;
      else hs <= !((hc+1 >= 10'd656) && (hc+1 < 10'd752));
   end

   always_ff @(posedge reset or posedge pixel_clk) begin : vsync_proc
      if (reset) vs <= 0;
      else vs <= !((vc+1 == 10'd490) || (vc+1 == 10'd491));
   end

   always_comb begin
      display = !((hc >= 10'd640) || (vc >= 10'd480));
   end
   assign active_nblank = display;
endmodule

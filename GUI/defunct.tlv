\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   $reset = *reset;

   // =================================================================
   // WORKLOAD — change signals here to test the Auto-Builder
   // Signals with "out" / "res" / "tx" / "data" in the name → right side
   // Everything else → left side
   // =================================================================
   |chip
      @1
         $in_a   = $reset ? 1'b0 : ~>>1$in_a;
         $in_b   = *cyc_cnt[2];
         $enable = 1'b1;

         $out_y          = ($in_a ^ $in_b) & $enable;
         $status_data_out = $in_a & $in_b;

   *passed = *cyc_cnt > 100;
   *failed = 1'b0;

   // =================================================================
   // SCRATCH FOR TLV — HYPER-MODULAR MVC ENGINE
   // =================================================================
   //
   //  ┌──────────────────────────────────────────────────────────────┐
   //  │  ARCHITECTURE OVERVIEW                                       │
   //  │                                                              │
   //  │  Controller  init()         — persistent brain, runs once   │
   //  │    ├─ State                 — probe positions / UI flags     │
   //  │    ├─ Lib                   — Fabric drawing primitives      │
   //  │    ├─ Events                — click / hover / key zones      │
   //  │    └─ Platform bridges      — Makerchip hooks, IDE bridge    │
   //  │                                                              │
   //  │  Model       onTraceData()  — runs once per compile         │
   //  │    ├─ Signal scanner        — reads sigHier (flat fallback)  │
   //  │    ├─ Semantic sorter       — L/R classification            │
   //  │    ├─ Layout engine         — computes pin geometry         │
   //  │    └─ Manifest writer       — outputs shared data contract  │
   //  │                          ↓ this.Manifest                    │
   //  │  View        render()       — dumb renderer, runs per cycle  │
   //  │    ├─ L1 Router             — bus routing + anti-collision   │
   //  │    ├─ L2 Chip               — package body + pins           │
   //  │    ├─ L3 Scope              — oscilloscope + waveforms      │
   //  │    └─ L4 Probes             — heads + badges + rename       │
   //  │                                                              │
   //  │  EXTENSION POINTS                                           │
   //  │    • New chip type  → add to MODEL.ChipConfigs              │
   //  │    • New heuristic  → edit MODEL.sorter regex               │
   //  │    • New view layer → add L5+ block inside render()         │
   //  │    • New bridge     → wire into Controller init()           │
   //  └──────────────────────────────────────────────────────────────┘
   //
   /viz
      \viz_js
         box: {width: 1100, height: 600, fill: "#0a0a0c"},

         // ============================================================
         // CONTROLLER — init()
         // Persistent state that survives re-renders and recompiles.
         // NEVER read signals here. NEVER touch Fabric canvas here.
         // ============================================================
         init() {
            const self = this;

            // ----------------------------------------------------------
            // MODULE: State
            // Single source of truth for all interactive UI state.
            // To add new state: add a property here, consume it in render().
            // ----------------------------------------------------------
            self.State = {
               showXRay:   false,
               probeColors: ["#ffeb3b", "#00e5ff", "#ff5252", "#69f0ae", "#ff9800", "#e040fb"],
               probes:      [],
               dragTarget:  null,

               addProbe: function() {
                  if (this.probes.length < 6) {
                     const n = this.probes.length;
                     this.probes.push({
                        id:     "p" + Date.now(),
                        name:   "CH" + (n + 1),
                        x:      580,
                        y:      150 + n * 50,
                        color:  this.probeColors[n],
                        target: null
                     });
                  }
               },
               removeProbe: function() {
                  if (this.probes.length > 1) this.probes.pop();
               }
            };

            // ----------------------------------------------------------
            // MODULE: Probe Persistence
            // Saves/restores probe layout across page reloads via
            // localStorage. Falls back to two default probes if nothing
            // is saved yet.
            // ----------------------------------------------------------
            const PROBE_KEY = "autortl.probes";
            (function() {
               let restored = false;
               try {
                  const saved = JSON.parse(
                     fabric.window.localStorage.getItem(PROBE_KEY) || "null"
                  );
                  if (saved && Array.isArray(saved) && saved.length > 0) {
                     saved.forEach(function(p, i) {
                        self.State.probes.push({
                           id:     p.id    || ("p" + Date.now() + i),
                           name:   p.name  || ("CH" + (i + 1)),
                           x:      p.x     || 580,
                           y:      p.y     || (150 + i * 50),
                           color:  p.color || self.State.probeColors[i % 6],
                           target: null   // re-snap on next render
                        });
                     });
                     restored = true;
                  }
               } catch(e) {}
               if (!restored) {
                  self.State.addProbe();
                  self.State.addProbe();
               }
            })();

            self._saveProbeState = function() {
               try {
                  const data = self.State.probes.map(function(p) {
                     return {id: p.id, name: p.name, x: p.x, y: p.y, color: p.color};
                  });
                  fabric.window.localStorage.setItem(PROBE_KEY, JSON.stringify(data));
               } catch(e) {}
            };

            // ----------------------------------------------------------
            // MODULE: Lib
            // Fabric drawing primitives. Thin wrappers that handle
            // create-or-update and z-ordering for you.
            //
            // UPGRADE NOTES:
            //   • To add new primitive types (circle, path, image):
            //     copy the rect() pattern, adjust fabric constructor.
            //   • To add animation: extend poly() with a thenAnimate() chain.
            //   • To change rendering quality: add strokeLineCap/Join options.
            // ----------------------------------------------------------
            self.Lib = {
               _objects: {},
               _labels:  {},

               rect: function(c, id, x, y, w, h, fill, stroke, sw, rx) {
                  if (!this._objects[id]) {
                     const obj = new fabric.Rect({
                        left: x, top: y, width: w, height: h,
                        fill:        fill   || "#444",
                        stroke:      stroke || "transparent",
                        strokeWidth: sw     || 0,
                        rx: rx || 0, ry: rx || 0,
                        selectable: false, evented: false
                     });
                     c.add(obj);
                     this._objects[id] = obj;
                  } else {
                     this._objects[id].set({ left: x, top: y, width: w, height: h, fill, stroke });
                     c.bringToFront(this._objects[id]);
                  }
               },

               label: function(c, id, text, x, y, color, size, weight) {
                  if (!this._labels[id]) {
                     const obj = new fabric.Text(String(text), {
                        left: x, top: y,
                        fontSize:   size   || 16,
                        fill:       color  || "#fff",
                        fontFamily: "monospace",
                        fontWeight: weight || "normal",
                        selectable: false, evented: false
                     });
                     c.add(obj);
                     this._labels[id] = obj;
                  } else {
                     this._labels[id].set({ text: String(text), left: x, top: y, fill: color });
                     c.bringToFront(this._labels[id]);
                  }
               },

               // Rounded-corner PCB trace. Recreated each frame for geometry updates.
               poly: function(c, id, pts, color, sw, isShadow) {
                  if (this._objects[id]) c.remove(this._objects[id]);
                  const obj = new fabric.Polyline(
                     pts.map(p => ({ x: p[0], y: p[1] })),
                     {
                        fill:           "transparent",
                        stroke:         color,
                        strokeWidth:    sw || 2,
                        strokeLineJoin: "round",
                        strokeLineCap:  "round",
                        selectable: false, evented: false
                     }
                  );
                  c.add(obj);
                  this._objects[id] = obj;
                  if (isShadow) obj.sendToBack();
               }
            };

            // ----------------------------------------------------------
            // MODULE: Events
            // Hit-zone registry for clicks and hover regions.
            // Zones are rebuilt every render() call via E.clear().
            // ----------------------------------------------------------
            self.Events = {
               zones: [],
               add:   (x, y, w, h, cb) => { self.Events.zones.push({ x, y, w, h, cb }); },
               clear: ()               => { self.Events.zones = []; },
               check: (pos)            => {
                  let hit = false;
                  self.Events.zones.forEach(z => {
                     if (pos.x >= z.x && pos.x <= z.x + z.w &&
                         pos.y >= z.y && pos.y <= z.y + z.h) {
                        z.cb(); hit = true;
                     }
                  });
                  return hit;
               }
            };

            // ----------------------------------------------------------
            // MODULE: Input controller
            // Mouse drag handling + coordinate transform (unified via
            // getCoords so there is a single transform path).
            // Snap-to-pin logic fires on mouse:up and uses Manifest.
            // On snap: saves probe state to localStorage.
            // ----------------------------------------------------------
            const cvs      = self.getCanvas();
            const canvasEl = fabric.document.querySelector("canvas");

            const getCoords = (e) => {
               if (!canvasEl) return { x: 0, y: 0 };
               const rect = canvasEl.getBoundingClientRect();
               const vpt  = cvs.viewportTransform || [1, 0, 0, 1, 0, 0];
               return {
                  x: Math.round((e.clientX - rect.left - vpt[4]) / vpt[0]),
                  y: Math.round((e.clientY - rect.top  - vpt[5]) / vpt[3])
               };
            };

            cvs.on("mouse:down", (opt) => {
               const pos = getCoords(opt.e);
               if (self.Events.check(pos)) { opt.e.stopPropagation(); return; }
               for (let i = self.State.probes.length - 1; i >= 0; i--) {
                  const p = self.State.probes[i];
                  if (Math.abs(pos.x - p.x) < 25 && Math.abs(pos.y - p.y) < 25) {
                     self.State.dragTarget = p;
                     break;
                  }
               }
               if (self.State.dragTarget) opt.e.stopPropagation();
            });

            cvs.on("mouse:move", (opt) => {
               if (!self.State.dragTarget) return;
               opt.e.stopPropagation();
               const pos = getCoords(opt.e);
               self.State.dragTarget.x = pos.x;
               self.State.dragTarget.y = pos.y;
               self.redraw();
            });

            cvs.on("mouse:up", () => {
               if (!self.State.dragTarget || !self.Manifest) return;
               let snapped = false;
               self.Manifest.pins.forEach(p => {
                  const absX = self.Manifest.chipX + p.dx;
                  const absY = self.Manifest.chipY + p.dy;
                  if (Math.abs(self.State.dragTarget.x - absX) < 30 &&
                      Math.abs(self.State.dragTarget.y - absY) < 30) {
                     self.State.dragTarget.x      = absX;
                     self.State.dragTarget.y      = absY;
                     self.State.dragTarget.target = p;
                     snapped = true;
                  }
               });
               if (!snapped) self.State.dragTarget.target = null;
               self.State.dragTarget = null;
               self._saveProbeState();
               self.redraw();
            });

            // ----------------------------------------------------------
            // MODULE: Platform bridges
            // Makerchip-specific hooks. Isolated here so all platform
            // coupling is in one place — easy to mock or replace.
            // ----------------------------------------------------------
            self.redraw = () => {
               const pane = self._viz.pane;
               if (pane) {
                  if (typeof pane.unrender === "function") pane.unrender();
                  if (typeof pane.render   === "function") pane.render();
               }
               cvs.renderAll();
            };

            // Sync to timeline scrubbing
            (function() {
               try {
                  const viewer = self._viz.pane.ide.viewer;
                  const orig   = viewer.onCycleUpdate;
                  viewer.onCycleUpdate = function(cyc) {
                     self.redraw();
                     if (orig) orig.apply(this, arguments);
                  };
               } catch(e) {}
            })();
         },

         // ============================================================
         // MODEL — onTraceData()
         // Runs ONCE per compile, after WaveData is ready.
         // Input:  this._viz.pane.waveData
         // Output: this.Manifest  (shared data contract for render())
         //
         // UPGRADE NOTES:
         //   • Signal scanner:   sigHier walk is primary; flat scan is
         //                       fallback. Change pipeline filter there.
         //   • Semantic sorter:  expand the isOut regex to recognise more
         //                       signal name patterns.
         //   • Layout engine:    change pinSpacing or add multi-column layout
         //   • Manifest writer:  add new fields (e.g. busWidth, clockDomain)
         // ============================================================
         onTraceData() {
            const wd = this._viz.pane.waveData;
            if (!wd) return;

            // ── Signal scanner ──────────────────────────────────────
            // Primary: walks sigHier for hierarchy-aware discovery and
            // accurate bit-width metadata.
            // Fallback: flat Object.keys() filter if sigHier unavailable.
            const rawSigs = [];   // waveData fullName strings
            const sigMap  = {};   // fullName → Variable (for metadata)

            try {
               const tlvNode = wd.sigHier &&
                               wd.sigHier.children &&
                               wd.sigHier.children["TLV"];
               if (tlvNode && tlvNode.children) {
                  Object.keys(tlvNode.children).forEach(function(pipelineKey) {
                     const pipeNode = tlvNode.children[pipelineKey];
                     if (!pipeNode || !pipeNode.sigs) return;
                     const fullScope = (typeof pipeNode.getFullScope === "function")
                        ? pipeNode.getFullScope()
                        : ("TLV" + pipelineKey);
                     Object.keys(pipeNode.sigs).forEach(function(sigKey) {
                        const sig      = pipeNode.sigs[sigKey];
                        const shortName = (sig.notFullName)
                           ? sig.notFullName
                           : (sigKey.startsWith("$") ? sigKey : "$" + sigKey);
                        const fullPath = fullScope + shortName;
                        rawSigs.push(fullPath);
                        sigMap[fullPath] = sig;
                     });
                  });
               }
            } catch(e) {}

            // Flat fallback
            if (rawSigs.length === 0) {
               try {
                  Object.keys(wd.signals)
                     .filter(k => k.startsWith("TLV|"))
                     .forEach(function(path) {
                        rawSigs.push(path);
                        sigMap[path] = wd.signals[path];
                     });
               } catch(e) {}
            }

            // ── Semantic sorter ─────────────────────────────────────
            // Expanded keyword set covers common RTL output conventions.
            // sigWidth is read from Variable metadata when available.
            const outputs = [];
            const inputs  = [];
            rawSigs.forEach(function(path) {
               const sig  = sigMap[path] || wd.signals[path];
               if (!sig) return;
               const raw  = sig.notFullName || path.split("$").pop() || "";
               const name = raw.replace("$", "");
               const isOut = /out|res|tx|data|status|valid|done|rdy/i.test(name);
               const entry = {
                  name:     name.toUpperCase(),
                  path:     path,
                  sigWidth: (sig.width !== undefined ? sig.width : 1)
               };
               (isOut ? outputs : inputs).push(entry);
            });

            // ── Layout engine ───────────────────────────────────────
            const pinSpacing = 60;
            const maxPins    = Math.max(inputs.length, outputs.length) + 1;
            const chipHeight = Math.max(180, maxPins * pinSpacing + 40);
            const chipWidth  = 100;

            // ── Manifest writer ─────────────────────────────────────
            this.Manifest = {
               chipX:    860,
               chipY:    100,
               width:    chipWidth,
               height:   chipHeight,
               chipName: "AUTO-RTL",
               pins:     []
            };

            const M = this.Manifest;

            // Left-side inputs
            inputs.forEach((p, i) => {
               M.pins.push({
                  id:       "L" + i,
                  name:     p.name.substring(0, 6),
                  dx:       0,
                  dy:       40 + i * pinSpacing,
                  side:     "L",
                  path:     p.path,
                  type:     "sig",
                  sigWidth: p.sigWidth
               });
            });
            // Auto GND (bottom-left)
            M.pins.push({ id: "GND", name: "GND", dx: 0, dy: chipHeight - 40,
                          side: "L", path: null, type: "gnd", sigWidth: 1 });

            // Auto VCC (top-right)
            M.pins.push({ id: "VCC", name: "VCC", dx: chipWidth, dy: 40,
                          side: "R", path: null, type: "vcc", sigWidth: 1 });
            // Right-side outputs
            outputs.forEach((p, i) => {
               M.pins.push({
                  id:       "R" + i,
                  name:     p.name.substring(0, 6),
                  dx:       chipWidth,
                  dy:       40 + (i + 1) * pinSpacing,
                  side:     "R",
                  path:     p.path,
                  type:     "sig",
                  sigWidth: p.sigWidth
               });
            });
         },

         // ============================================================
         // VIEW — render()
         // "Dumb" renderer. Reads Manifest + State. Writes Fabric only.
         // Runs on every cycle change — keep it fast.
         //
         // Four isolated layers in strict z-order:
         //   L1 Router  — PCB traces (bottom, behind everything)
         //   L2 Chip    — package body + pins
         //   L3 Scope   — oscilloscope + waveforms
         //   L4 Probes  — probe heads (top, always in front)
         //
         // UPGRADE NOTES:
         //   • Add L5+ blocks following the same pattern as L1-L4
         //   • Each layer is fully isolated: bug in L3 → L4 still works
         //   • To move a layer in z-order: reorder the blocks below
         // ============================================================
         render() {
            const self = this;
            const cvs  = self.getCanvas();
            const D    = self.Lib;
            const E    = self.Events;
            const M    = self.Manifest;
            const S    = self.State;
            const wd   = this._viz.pane.waveData;

            // Clear canvas + re-register click zones every frame
            cvs.clear();
            E.clear();
            if (!D._objects) { D._objects = {}; D._labels = {}; }
            D._objects = {};
            D._labels  = {};

            if (!M || !wd) return;

            const CYC = this._viz.pane.cyc;

            // Signal reader — handles sig / vcc / gnd / nc types
            const getVal = (p, c) => {
               try { return wd.getSignalValueAtCycleByName(p, c).asInt(0); } catch(e) { return 0; }
            };
            const resolveSignal = (target, c) => {
               if (!target || target.type === "nc")  return -1;
               if (target.type === "vcc")             return 1;
               if (target.type === "gnd")             return 0;
               return getVal(target.path, c) & 1;
            };

            // ── LAYOUT CONSTANTS ──────────────────────────────────────
            const SCOPE = { x: 40,             y: 40, w: 480, h: 420 };
            const PLOT  = { x: SCOPE.x + 20,   y: SCOPE.y + 40,
                            w: SCOPE.w - 40,   h: SCOPE.h - 60 };
            const chH   = PLOT.h / S.probes.length;

            // ── L1 — ROUTER ───────────────────────────────────────────
            S.probes.forEach((probe, idx) => {
               const entryY = PLOT.y + (idx + 0.5) * chH;
               const busX   = SCOPE.x + SCOPE.w + 20 + (idx * 15);

               const isBehindScope = (probe.x < busX + 10)   &&
                                     (probe.y > SCOPE.y - 20) &&
                                     (probe.y < SCOPE.y + SCOPE.h + 20);
               const isBehindChip  = (probe.x > M.chipX + 10) &&
                                     (probe.y > M.chipY - 20)  &&
                                     (probe.y < M.chipY + M.height + 20);

               let pts;
               if (isBehindScope) {
                  const safeY  = probe.y < (SCOPE.y + SCOPE.h / 2)
                                    ? (SCOPE.y - 25 - idx * 8)
                                    : (SCOPE.y + SCOPE.h + 25 + idx * 8);
                  const leftX  = Math.min(probe.x - 20, SCOPE.x - 25 - idx * 8);
                  pts = [
                     [SCOPE.x + SCOPE.w, entryY],
                     [busX,   entryY],
                     [busX,   safeY],
                     [leftX,  safeY],
                     [leftX,  probe.y],
                     [probe.x, probe.y]
                  ];
               } else if (isBehindChip) {
                  const safeY   = probe.y < (M.chipY + M.height / 2)
                                     ? (M.chipY - 25 - idx * 8)
                                     : (M.chipY + M.height + 25 + idx * 8);
                  const rightX  = Math.max(probe.x + 20, M.chipX + M.width + 25 + idx * 8);
                  pts = [
                     [SCOPE.x + SCOPE.w, entryY],
                     [busX,    entryY],
                     [busX,    safeY],
                     [rightX,  safeY],
                     [rightX,  probe.y],
                     [probe.x, probe.y]
                  ];
               } else {
                  pts = [
                     [SCOPE.x + SCOPE.w, entryY],
                     [busX,    entryY],
                     [busX,    probe.y],
                     [probe.x, probe.y]
                  ];
               }

               D.poly(cvs, "sh" + probe.id, pts.map(p => [p[0]+2, p[1]+2]), "rgba(0,0,0,0.4)", 4, true);
               D.poly(cvs, "w"  + probe.id, pts, probe.color, 2, false);
            });

            // ── L2 — CHIP ─────────────────────────────────────────────
            E.add(M.chipX, M.chipY, M.width, M.height, () => {
               S.showXRay = !S.showXRay;
               self.redraw();
            });

            M.pins.forEach(p => {
               const ax = M.chipX + p.dx;
               const ay = M.chipY + p.dy;
               D.rect(cvs, "p" + p.id,
                  (p.side === "L" ? ax - 20 : ax), ay - 10,
                  20, 20,
                  "#b5a642", "#887010", 1, 2
               );
               D.label(cvs, "pl" + p.id, p.name,
                  (p.side === "L" ? ax - 72 : ax + 28), ay - 8,
                  "#888", 11
               );
            });

            D.rect(cvs, "pkg",
               M.chipX, M.chipY, M.width, M.height,
               S.showXRay ? "rgba(20,20,25,0.3)" : "#181a1f",
               "#000", 2, 4
            );
            D.rect(cvs, "dot", M.chipX + 12, M.chipY + 12, 8, 8,
               S.showXRay ? "rgba(255,255,255,0.1)" : "#222",
               "transparent", 0, 4
            );

            if (!S.showXRay) {
               D.label(cvs, "silk", M.chipName,
                  M.chipX + 14, M.chipY + M.height / 2 - 8,
                  "#555", 13, "bold"
               );
            } else {
               D.label(cvs, "die_txt", "RTL DIE VIEW",
                  M.chipX + 8, M.chipY + M.height / 2 - 8,
                  "#1a3d1a", 11
               );
            }

            D.label(cvs, "hint_chip", "[CLICK CHIP: X-RAY]",
               M.chipX - 10, M.chipY - 22, "#444", 11);

            // ── L3 — SCOPE ────────────────────────────────────────────
            D.rect(cvs, "sc_bg",
               SCOPE.x, SCOPE.y, SCOPE.w, SCOPE.h,
               "#111318", "#2c313c", 2, 8
            );
            D.label(cvs, "sc_t", "DUAL-BEAM ANALYZER",
               SCOPE.x + 14, SCOPE.y + 12, "#aaa", 12, "bold");

            D.rect(cvs, "b_add", SCOPE.x + 400, SCOPE.y + 10, 25, 20, "#222", "#4fc3f7", 1, 4);
            D.label(cvs, "l_add", "+", SCOPE.x + 408, SCOPE.y + 12, "#4fc3f7", 14);
            E.add(SCOPE.x + 400, SCOPE.y + 10, 25, 20, () => { S.addProbe(); self.redraw(); });

            D.rect(cvs, "b_rm",  SCOPE.x + 435, SCOPE.y + 10, 25, 20, "#222", "#ff5252", 1, 4);
            D.label(cvs, "l_rm", "-", SCOPE.x + 444, SCOPE.y + 12, "#ff5252", 14);
            E.add(SCOPE.x + 435, SCOPE.y + 10, 25, 20, () => { S.removeProbe(); self.redraw(); });

            D.rect(cvs, "plot", PLOT.x, PLOT.y, PLOT.w, PLOT.h, "#050805", "#1a2a1a", 1);

            const CYCLES    = 16;
            const stepX     = PLOT.w / CYCLES;
            const startCyc  = Math.max(wd.startCycle, CYC - 8);

            for (let g = 0; g <= CYCLES; g += 2)
               D.rect(cvs, "gv" + g, PLOT.x + g * stepX, PLOT.y, 1, PLOT.h, "#0b1e15");
            for (let p = 1; p < S.probes.length; p++)
               D.rect(cvs, "gh" + p, PLOT.x, PLOT.y + p * chH, PLOT.w, 1, "#0b1e15");
            if (CYC >= startCyc && CYC <= startCyc + CYCLES)
               D.rect(cvs, "cur",
                  PLOT.x + (CYC - startCyc) * stepX + stepX / 2,
                  PLOT.y, 2, PLOT.h, "#444"
               );

            S.probes.forEach((probe, idx) => {
               const yBase = PLOT.y + (idx + 1) * chH - (chH * 0.2);
               const amp   = chH * 0.5;

               D.label(cvs, "pn" + probe.id, probe.name,
                  PLOT.x + 8, yBase - amp - 14, probe.color, 11, "bold");
               D.label(cvs, "pt" + probe.id,
                  "PIN: " + (probe.target ? probe.target.name : "DISC"),
                  PLOT.x + 44, yBase - amp - 14, "#666", 10);

               for (let k = 0; k < CYCLES; k++) {
                  const c  = startCyc + k;
                  const v  = resolveSignal(probe.target, c);
                  const vp = resolveSignal(probe.target, c - 1);
                  const x0 = PLOT.x + k * stepX;

                  if (v === -1) {
                     D.rect(cvs, "tn" + probe.id + k, x0, yBase - amp / 2, stepX, 2, "#333");
                  } else {
                     D.rect(cvs, "th" + probe.id + k, x0, v ? (yBase - amp) : yBase, stepX, 2, probe.color);
                     if (v !== vp && vp !== -1 && k > 0)
                        D.rect(cvs, "tv" + probe.id + k, x0,
                           Math.min(v ? (yBase - amp) : yBase, vp ? (yBase - amp) : yBase),
                           2, amp, probe.color
                        );
                  }
               }
            });

            // ── L4 — PROBE HEADS ──────────────────────────────────────
            S.probes.forEach(probe => {
               D.rect(cvs, "ha" + probe.id,
                  probe.x - 12, probe.y - 12, 24, 24,
                  "transparent", probe.color, 1, 12
               );
               D.rect(cvs, "bo" + probe.id,
                  probe.x - 6, probe.y - 6, 12, 12,
                  "#000", probe.color, 2, 6
               );
               D.rect(cvs, "bg" + probe.id,
                  probe.x - 18, probe.y - 32, 36, 16,
                  "#111", "#444", 1, 4
               );
               D.label(cvs, "lb" + probe.id,
                  probe.name, probe.x - 14, probe.y - 30,
                  probe.color, 11, "bold"
               );
               E.add(probe.x - 18, probe.y - 32, 36, 16, () => {
                  const n = prompt("Rename probe (max 4 chars):", probe.name);
                  if (n !== null) {
                     probe.name = n.substring(0, 4).toUpperCase() || probe.name;
                     self._saveProbeState();
                     self.redraw();
                  }
               });
            });

            // ── FOOTER HINTS ──────────────────────────────────────────
            D.label(cvs, "hint_main",
               "[DRAG PROBES]  [CLICK NAME TO RENAME]  [CLICK CHIP FOR X-RAY]",
               SCOPE.x, SCOPE.y + SCOPE.h + 15,
               "#444", 11
            );
         }
\SV
   endmodule

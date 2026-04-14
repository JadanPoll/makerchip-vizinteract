\m5_TLV_version 1d: tl-x.org

\m5

   use(m5-1.0)

\SV

   m5_makerchip_module

\TLV

   $reset = *reset;

   // =================================================================

   // WORKLOAD — Modify signals here to test the Auto-Builder.

   // The viz will auto-detect signal names and classify them L/R.

   // Heuristic: names matching /out|res|tx|data|status|valid|done|rdy/

   // go to the right (outputs); everything else goes left (inputs).

   // =================================================================

   |chip

      @1

         $in_a = $reset ? 1'b0 : ~>>1$in_a;

         $in_b = *cyc_cnt[2];

         $enable = 1'b1;

         $out_y = ($in_a ^ $in_b) & $enable;

         $status_data_out = $in_a & $in_b;

   *passed = *cyc_cnt > 100;

   *failed = 1'b0;

   // =================================================================

   // AUTO-BUILDER VIZ — Supercharged MVC Edition

   //

   // ARCHITECTURE:

   //   Controller  init()         — state, input, bridges (runs once)

   //   Model       onTraceData()  — signal scan + Manifest (per compile)

   //   View        render()       — dumb renderer (per cycle)

   //

   // HOTKEYS:  x=X-ray  t=Table  p=Params  h=Highlight

   //           z/Z=WFM zoom  f=WFM fit  +/-=Probes  Arrows=Step cycle

   // =================================================================

   /viz

      \viz_js

         box: {width: 1200, height: 680, fill: "#0a0a0c"},



         // ============================================================

         // CONTROLLER — init()

         // Persistent. Survives re-renders and recompiles.

         // RULE: Never read waveData signals here.

         // RULE: Never touch the Fabric canvas here.

         // EXTENSION: Add new modules at the bottom of init().

         // ============================================================

         init() {

            const self = this;



            // ----------------------------------------------------------

            // MODULE 0: VizInteract v2.0 Core

            // Official Makerchip drawing + input layer.

            // SOURCE: Makerchip VizJS Internal Cookbook §1 (April 2026)

            // VERIFIED: All APIs in this block.

            // To upgrade: replace this block with a newer version wholesale.

            // ----------------------------------------------------------

            const VI = {};

            this._VI = VI;

            VI._labels   = {};

            VI._objects  = {};

            VI._hotkeys  = {};

            VI._clickZones  = [];

            VI._hoverZones  = {};

            VI._lastHovered = {};



            // VI.redraw() — declarative full repaint

            // VERIFIED: Cookbook §1, unrender + render + renderAll chain

            VI.redraw = function() {

               if (self._viz && self._viz.pane) {

                  const pane = self._viz.pane;

                  if (typeof pane.unrender === "function") pane.unrender();

                  if (typeof pane.render  === "function") pane.render();

               }

               self.getCanvas().renderAll();

            };



            // Focus + editor-detection (suppress hotkeys when typing)

            const canvasEl   = fabric.document.querySelector("canvas");

            const focusTarget = canvasEl ? canvasEl.closest("div") : null;

            if (focusTarget) {

               focusTarget.setAttribute("tabindex", "0");

               setTimeout(function() { focusTarget.focus(); }, 500);

            }

            const _editorHasFocus = function() {

               const active = fabric.document.activeElement;

               const tag    = active ? active.tagName.toLowerCase() : "none";

               return tag === "textarea" || tag === "input" ||

                      (active && active.isContentEditable);

            };



            // VI.toCanvasCoords — client → canvas coordinate transform

            // VERIFIED: Cookbook §1

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



            // VI.label — create-or-update text object

            // EXTENDED: added fontWeight param beyond v2.0 base

            VI.label = function(id, text, x, y, color, size, weight) {

               const c = self.getCanvas();

               if (!VI._labels[id]) {

                  const obj = new fabric.Text(String(text), {

                     left: x, top: y,

                     fontSize: size || 13,

                     fill: color || "#e0e0e0",

                     fontFamily: "monospace",

                     fontWeight: weight || "normal",

                     selectable: false, evented: false,

                     hasControls: false, hasBorders: false

                  });

                  c.add(obj);

                  VI._labels[id] = obj;

               } else {

                  VI._labels[id].set({text: String(text)});

                  if (color)  VI._labels[id].set("fill",     color);

                  if (size)   VI._labels[id].set("fontSize", size);

                  if (weight) VI._labels[id].set("fontWeight", weight);

               }

               return VI._labels[id];

            };



            // VI.rect — create-or-update rectangle

            // EXTENDED: strokeWidth (sw) and corner radius (rx) params

            VI.rect = function(id, x, y, w, h, fill, stroke, sw, rx) {

               const c = self.getCanvas();

               if (!VI._objects[id]) {

                  const obj = new fabric.Rect({

                     left: x, top: y, width: w, height: h,

                     fill:        fill   || "#444",

                     stroke:      stroke || "transparent",

                     strokeWidth: sw     || 0,

                     rx: rx || 0, ry: rx || 0,

                     selectable: false, evented: false,

                     hasControls: false, hasBorders: false

                  });

                  c.add(obj);

                  VI._objects[id] = obj;

               } else {

                  VI._objects[id].set({left: x, top: y, fill: fill, stroke: stroke});

               }

               return VI._objects[id];

            };



            // VI.poly — polyline, recreated each frame (cleared by clearAll)

            // EXTENSION beyond v2.0 base — PCB trace routing

            VI.poly = function(id, pts, color, sw, sendBack) {

               const c = self.getCanvas();

               if (VI._objects[id]) c.remove(VI._objects[id]);

               const obj = new fabric.Polyline(

                  pts.map(function(p) { return {x: p[0], y: p[1]}; }),

                  {

                     fill: "transparent", stroke: color,

                     strokeWidth:    sw || 2,

                     strokeLineJoin: "round",

                     strokeLineCap:  "round",

                     selectable: false, evented: false

                  }

               );

               c.add(obj);

               VI._objects[id] = obj;

               if (sendBack) c.sendToBack(obj);

               return obj;

            };



            // Hit-zone registration

            VI.onClick = function(id, x, y, w, h, cb) {

               VI._clickZones = VI._clickZones.filter(function(z) { return z.id !== id; });

               VI._clickZones.push({id: id, x: x, y: y, w: w, h: h, cb: cb});

            };

            VI.onHover = function(id, x, y, w, h, onEnter, onLeave) {

               VI._hoverZones[id] = {x: x, y: y, w: w, h: h, enter: onEnter, leave: onLeave};

            };

            VI.onKey = function(key, cb) { VI._hotkeys[key] = cb; };



            // VI.clearAll — wipe canvas + all caches for clean render()

            // VERIFIED: Cookbook §1 — must be called at top of render()

            VI.clearAll = function() {

               const c = self.getCanvas();

               c.clear();

               c.selection    = false;

               VI._labels     = {};

               VI._objects    = {};

               VI._clickZones = [];

               VI._hoverZones = {};

            };



            // Hit test helper

            const _hit = function(z, cx, cy) {

               return cx >= z.x && cx <= z.x + z.w && cy >= z.y && cy <= z.y + z.h;

            };



            // Global mouse + keyboard listeners

            fabric.document.addEventListener("mouseup", function(e) {

               if (_editorHasFocus()) return;

               const pos = VI.toCanvasCoords(e.clientX, e.clientY);

               VI._clickZones.forEach(function(z) {

                  if (_hit(z, pos.x, pos.y)) z.cb(pos.x, pos.y);

               });

            });

            fabric.document.addEventListener("mousemove", function(e) {

               if (_editorHasFocus()) return;

               const pos = VI.toCanvasCoords(e.clientX, e.clientY);

               Object.keys(VI._hoverZones).forEach(function(id) {

                  const z   = VI._hoverZones[id];

                  const in_ = _hit(z, pos.x, pos.y);

                  const was = VI._lastHovered[id];

                  if (in_ && !was) { VI._lastHovered[id] = true;  if (z.enter) z.enter(pos.x, pos.y); }

                  if (!in_ && was) { VI._lastHovered[id] = false; if (z.leave) z.leave(pos.x, pos.y); }

               });

            });

            fabric.window.addEventListener("keydown", function(e) {

               if (_editorHasFocus()) return;

               if (VI._hotkeys[e.key]) VI._hotkeys[e.key](e);

            });



            // Camera module — VERIFIED: Cookbook §16

            VI.camera = {

               getScale: function()    { return self._viz.pane.content.contentScale; },

               setScale: function(n)   { self._viz.pane.content.contentScale = n; },

               setFocus: function(x,y) { self._viz.pane.content.userFocus = {x: x, y: y}; },

               apply:    function()    { self._viz.pane.content.refreshContentPosition(); },

               zoomBy:   function(exp) { self._viz.pane.content.zoomContentBy(exp); },

               center:   function()    { self._viz.pane.content.centerContent(); },

               focusOn:  function(x,y) { self._viz.pane.content.focusContentOn(x, y); }

            };



            // IDE bridge — VERIFIED: Cookbook §14

            // RULE: patch/recompile ONLY from event handlers, never from init/render.

            VI.ide = {available: false, _busy: false};

            (function() {

               let ide = null;

               try { ide = self._viz.pane.ide; } catch(e) {}

               if (ide && ide.IDEMethods &&

                   typeof ide.IDEMethods.getCode     === "function" &&

                   typeof ide.IDEMethods.loadProject === "function") {

                  VI.ide.available = true;

                  VI.ide._m = ide.IDEMethods;

               }

            })();

            VI.ide.getCode = function() {

               if (!VI.ide.available) return null;

               try { return VI.ide._m.getCode(); } catch(e) { return null; }

            };

            // VI.ide.patch — replaces $name[x:y] = ...; with new value

            // VERIFIED: Cookbook §14 — safe only in event handlers

            VI.ide.patch = function(name, value) {

               if (!VI.ide.available || VI.ide._busy) return false;

               const r = VI.ide.getCode();

               if (!r) return false;

               const rx = new RegExp("\\$" + name + "\\s*\\[\\d+:\\d+\\]\\s*=\\s*[^;]+;", "g");

               if (!rx.test(r.code)) return false;

               const newCode = r.code.replace(rx, "$$" + name + "[7:0] = " + value + ";");

               if (newCode === r.code) return false;

               VI.ide._busy = true;

               VI.ide._m.loadProject(newCode);

               setTimeout(function() { VI.ide._busy = false; }, 3000);

               return true;

            };

            // END VizInteract v2.0 + extensions



            // ----------------------------------------------------------

            // MODULE 1: State

            // Single source of truth for all interactive UI state.

            // EXTENSION: Add new fields here. Consume in render() only.

            // ----------------------------------------------------------

            self.State = {

               // Probe configuration

               probeColors: ["#ffeb3b", "#00e5ff", "#ff5252", "#69f0ae", "#ff9800", "#e040fb"],

               probes:      [],

               dragTarget:  null,



               // View mode toggles

               showXRay:        false,

               showSignalTable: false,

               showParamSliders: false,



               // Cached Yosys SVG from session.on("graph")

               // VERIFIED: session.on("graph") fires with SVG string — Cookbook §21

               graphSvg:      null,

               _svgFabricImg: null,   // fabric.Image object (persists across clearAll)



               // Live parameter sliders — populate to expose ide.patch controls

               // EXTENSION: Push {name, min, max, value, label} entries here.

               // Example: self.State.paramSliders.push({name:"threshold",min:0,max:255,value:5,label:"THRESH"});

               paramSliders: [],



               // Probe management

               addProbe: function() {

                  if (this.probes.length < 6) {

                     const n = this.probes.length;

                     this.probes.push({

                        id:     "p" + Date.now(),

                        name:   "CH" + (n + 1),

                        x:      600,

                        y:      165 + n * 55,

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

            // MODULE 2: Probe Persistence

            // Saves/restores probe layout across page reloads.

            // VERIFIED: fabric.window.localStorage — Cookbook §23

            // ----------------------------------------------------------

            const PROBE_KEY = "autortl.probes";

            (function() {

               let restored = false;

               try {

                  const saved = JSON.parse(fabric.window.localStorage.getItem(PROBE_KEY) || "null");

                  if (saved && Array.isArray(saved) && saved.length > 0) {

                     saved.forEach(function(p, i) {

                        self.State.probes.push({

                           id:     p.id    || ("p" + Date.now() + i),

                           name:   p.name  || ("CH" + (i + 1)),

                           x:      p.x     || 600,

                           y:      p.y     || (165 + i * 55),

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

            // MODULE 3: Graph SVG Cache

            // Subscribes to Yosys-generated schematic SVG once per compile.

            // On X-ray toggle, this SVG is embedded inside the chip body.

            // VERIFIED: session.on("graph") — Cookbook §21

            // GOTCHA: session.on() listeners accumulate. Guard with try/catch

            //         on self._viz check to silently drop stale instance calls.

            // ----------------------------------------------------------

            try {

               const session = self._viz.pane.session;

               session.on("graph", function(svgString) {

                  try {

                     if (!self._viz || !self._viz.pane) return; // stale instance guard

                     if (typeof svgString === "string" && svgString.length > 100) {

                        self.State.graphSvg      = svgString;

                        self.State._svgFabricImg = null; // force fabric.Image reload

                        VI.redraw();

                     }

                  } catch(e) {}

               });

            } catch(e) {}



            // ----------------------------------------------------------

            // MODULE 4: Input Controller

            // Probe drag + snap using VizInteract v2.0 coord system.

            // On snap: broadcasts cross-pane highlight to schematic + NavTLV.

            // VERIFIED: pane.highlightLogicalElement — Cookbook §8, §13

            // VERIFIED: VI.toCanvasCoords — Cookbook §1

            // EXTENSION: Add new snap targets by adding pins to Manifest.

            // ----------------------------------------------------------

            fabric.document.addEventListener("mousedown", function(e) {

               if (_editorHasFocus()) return;

               const pos = VI.toCanvasCoords(e.clientX, e.clientY);

               for (let i = self.State.probes.length - 1; i >= 0; i--) {

                  const p = self.State.probes[i];

                  if (Math.abs(pos.x - p.x) < 26 && Math.abs(pos.y - p.y) < 26) {

                     self.State.dragTarget = p;

                     break;

                  }

               }

            });



            fabric.document.addEventListener("mousemove", function(e) {

               if (!self.State.dragTarget) return;

               const pos = VI.toCanvasCoords(e.clientX, e.clientY);

               self.State.dragTarget.x = pos.x;

               self.State.dragTarget.y = pos.y;

               VI.redraw();

            });



            fabric.document.addEventListener("mouseup", function(e) {

               if (!self.State.dragTarget || !self.Manifest) return;

               const probe = self.State.dragTarget;

               let snapped = false;

               self.Manifest.pins.forEach(function(p) {

                  if (snapped) return;

                  const ax = self.Manifest.chipX + p.dx;

                  const ay = self.Manifest.chipY + p.dy;

                  if (Math.abs(probe.x - ax) < 32 && Math.abs(probe.y - ay) < 32) {

                     probe.x = ax;

                     probe.y = ay;

                     probe.target = p;

                     snapped = true;

                     // Cross-pane highlight: schematic + waveform + NavTLV

                     // VERIFIED: pane.highlightLogicalElement — Cookbook §8

                     if (p.logicalEntity) {

                        try { self._viz.pane.highlightLogicalElement(p.logicalEntity); } catch(er) {}

                     }

                  }

               });

               if (!snapped) {

                  probe.target = null;

                  try { self._viz.pane.unhighlightLogicalElements(); } catch(er) {}

               }

               self.State.dragTarget = null;

               self._saveProbeState();

               VI.redraw();

            });



            // ----------------------------------------------------------

            // MODULE 5: Hotkeys

            // Registered once in init(), persist across recompiles.

            // EXTENSION: Add new shortcuts with VI.onKey(key, handler).

            // VERIFIED: VI.onKey pattern — Cookbook §1

            // VERIFIED: wg.zoomIn/Out/Full/reachStart/End — Cookbook §10

            // VERIFIED: pane.prevCycle/nextCycle — Cookbook §8

            // ----------------------------------------------------------

            VI.onKey("x", function() { self.State.showXRay = !self.State.showXRay; VI.redraw(); });

            VI.onKey("t", function() { self.State.showSignalTable = !self.State.showSignalTable; VI.redraw(); });

            VI.onKey("p", function() { self.State.showParamSliders = !self.State.showParamSliders; VI.redraw(); });

            VI.onKey("+", function() { self.State.addProbe(); VI.redraw(); });

            VI.onKey("-", function() { self.State.removeProbe(); VI.redraw(); });

            VI.onKey("ArrowLeft",  function() { try { self._viz.pane.prevCycle(); } catch(e) {} });

            VI.onKey("ArrowRight", function() { try { self._viz.pane.nextCycle(); } catch(e) {} });

            VI.onKey("z", function() { try { self._viz.pane.ide.viewer.wg.zoomIn();    } catch(e) {} });

            VI.onKey("Z", function() { try { self._viz.pane.ide.viewer.wg.zoomOut();   } catch(e) {} });

            VI.onKey("f", function() { try { self._viz.pane.ide.viewer.wg.zoomFull();  } catch(e) {} });

            VI.onKey("r", function() { try { self._viz.pane.ide.viewer.wg.reachStart(); } catch(e) {} });

            // h = highlight first snapped probe in all panes

            VI.onKey("h", function() {

               const probe = self.State.probes.find(function(p) { return p.target && p.target.logicalEntity; });

               if (probe) {

                  try { self._viz.pane.highlightLogicalElement(probe.target.logicalEntity); } catch(e) {}

               }

            });



            // ----------------------------------------------------------

            // MODULE 6: Platform Bridges

            // Wires cycle-scrubbing and session events to VI.redraw().

            // VERIFIED: viewer.onCycleUpdate override — Cookbook §24 Pattern 5

            // VERIFIED: session.on("cycle-update") — Cookbook §13

            // ----------------------------------------------------------

            self._VI_redraw = VI.redraw; // expose for bridge closures



            // Bridge 1: waveform timeline scrub

            (function() {

               try {

                  const viewer = self._viz.pane.ide.viewer;

                  const orig   = viewer.onCycleUpdate;

                  viewer.onCycleUpdate = function(cyc) {

                     try { VI.redraw(); } catch(e) {}

                     if (orig) orig.apply(this, arguments);

                  };

               } catch(e) {}

            })();



            // Bridge 2: session cycle-update (belt-and-suspenders)

            try {

               self._viz.pane.session.on("cycle-update", function() {

                  try { if (self._viz && self._viz.pane) VI.redraw(); } catch(e) {}

               });

            } catch(e) {}

         },



         // ============================================================

         // MODEL — onTraceData()

         // Runs ONCE per compile when WaveData is ready.

         // Input:  this._viz.pane.waveData

         // Output: this.Manifest  (data contract consumed by render())

         //

         // Manifest schema:

         //   chipX, chipY, width, height, chipName

         //   totalSigs                  — raw signal count

         //   startCyc, endCyc           — trace bounds

         //   pins[] {

         //     id, name, dx, dy, side   — geometry

         //     path                     — waveData fullName for signal reads

         //     logicalEntity            — cross-pane highlight path

         //     type                     — "sig" | "vcc" | "gnd"

         //     sigWidth                 — bit width (1 for single-bit)

         //   }

         //

         // EXTENSION:

         //   • Scan more pipelines: loop over all tlvNode.children keys

         //   • Add heuristics: expand the isOut regex below

         //   • Change chip shape: edit the layout engine section

         //   • Add new Manifest fields: add here, read in render()

         //   • Add chip config overrides: see EXTENSION comment at bottom

         // ============================================================

         onTraceData() {

            // Reset any cached Fabric assets that depend on compile output

            if (this.State) {

               this.State._svgFabricImg = null;

            }



            const wd = this._viz.pane.waveData;

            if (!wd) return;



            // ── MODULE A: Signal Scanner ───────────────────────────

            // Primary:  walks sigHier for accurate, hierarchy-aware discovery.

            // Fallback: flat Object.keys() filter if sigHier unavailable.

            // VERIFIED: sigHier structure — Cookbook §6

            const rawSigs = [];   // array of waveData fullName strings

            const sigMap  = {};   // fullName → Variable (for metadata)



            try {

               const tlvNode = wd.sigHier &&

                               wd.sigHier.children &&

                               wd.sigHier.children["TLV"];

               if (tlvNode && tlvNode.children) {

                  Object.keys(tlvNode.children).forEach(function(pipelineKey) {

                     const pipeNode = tlvNode.children[pipelineKey];

                     if (!pipeNode || !pipeNode.sigs) return;

                     // Derive full scope string — e.g. "TLV|chip"

                     // VERIFIED: getFullScope() — Cookbook §6

                     const fullScope = (typeof pipeNode.getFullScope === "function")

                        ? pipeNode.getFullScope()

                        : ("TLV" + pipelineKey);

                     Object.keys(pipeNode.sigs).forEach(function(sigKey) {

                        const sig      = pipeNode.sigs[sigKey];

                        const shortName = (sig.notFullName) ? sig.notFullName

                                        : (sigKey.startsWith("$") ? sigKey : "$" + sigKey);

                        const fullPath = fullScope + shortName; // e.g. "TLV|chip$out_y"

                        rawSigs.push(fullPath);

                        sigMap[fullPath] = sig;

                     });

                  });

               }

            } catch(e) {}



            // Fallback

            if (rawSigs.length === 0) {

               try {

                  Object.keys(wd.signals)

                     .filter(function(k) { return k.startsWith("TLV|"); })

                     .forEach(function(path) {

                        rawSigs.push(path);

                        sigMap[path] = wd.signals[path];

                     });

               } catch(e) {}

            }



            // ── MODULE B: Semantic Sorter ──────────────────────────

            // Classifies signals as input (left) or output (right).

            // Uses name heuristic + bit-width metadata from Variable.

            // EXTENSION: Add patterns to isOut regex.

            // EXTENSION: Use sig.scope or sig.width to override classification.

            const inputs  = [];

            const outputs = [];



            rawSigs.forEach(function(path) {

               const sig  = sigMap[path] || wd.signals[path];

               if (!sig) return;

               const raw  = sig.notFullName || path.split("$").pop() || "";

               const name = raw.replace("$", "");



               // Logical entity: convert waveData path to cross-pane format

               // "TLV|chip$out_y" → "/|chip$out_y"

               // VERIFIED: logical entity format — Cookbook §12, §13

               const logicalEntity = path.replace(/^TLV/, "");



               const isOut = /out|res|tx|data|status|valid|done|rdy/i.test(name);

               const entry = {

                  name:          name.toUpperCase(),

                  path:          path,

                  logicalEntity: logicalEntity,

                  sigWidth:      (sig.width !== undefined ? sig.width : 1)

               };

               (isOut ? outputs : inputs).push(entry);

            });



            // ── MODULE C: Layout Engine ────────────────────────────

            // Computes chip geometry from signal count.

            // EXTENSION: Change pinSpacing/chipWidth for different form factors.

            // EXTENSION: Add multi-column layout for designs with >12 signals per side.

            const PIN_SPACING = 55;

            const maxSide     = Math.max(inputs.length, outputs.length);

            const chipHeight  = Math.max(200, (maxSide + 2) * PIN_SPACING + 60);

            const chipWidth   = 110;

            const CHIP_X      = 870;

            const CHIP_Y      = 80;



            // ── MODULE D: Manifest Writer ──────────────────────────

            // EXTENSION: Add new top-level fields consumed by render() layers.

            this.Manifest = {

               chipX:     CHIP_X,

               chipY:     CHIP_Y,

               width:     chipWidth,

               height:    chipHeight,

               chipName:  "AUTO-RTL",

               totalSigs: rawSigs.length,

               startCyc:  wd.startCycle  || 0,

               endCyc:    wd.endCycle    || 100,

               pins:      []

            };



            const M = this.Manifest;



            // Left pins: inputs, then GND anchor

            inputs.forEach(function(p, i) {

               M.pins.push({

                  id:            "L" + i,

                  name:          p.name.substring(0, 7),

                  dx:            0,

                  dy:            50 + i * PIN_SPACING,

                  side:          "L",

                  path:          p.path,

                  logicalEntity: p.logicalEntity,

                  type:          "sig",

                  sigWidth:      p.sigWidth

               });

            });

            M.pins.push({ id: "GND", name: "GND", dx: 0,          dy: chipHeight - 40,

                          side: "L", path: null, logicalEntity: null, type: "gnd", sigWidth: 1 });



            // Right pins: VCC anchor, then outputs

            M.pins.push({ id: "VCC", name: "VCC", dx: chipWidth,  dy: 40,

                          side: "R", path: null, logicalEntity: null, type: "vcc", sigWidth: 1 });

            outputs.forEach(function(p, i) {

               M.pins.push({

                  id:            "R" + i,

                  name:          p.name.substring(0, 7),

                  dx:            chipWidth,

                  dy:            40 + (i + 1) * PIN_SPACING,

                  side:          "R",

                  path:          p.path,

                  logicalEntity: p.logicalEntity,

                  type:          "sig",

                  sigWidth:      p.sigWidth

               });

            });



            // EXTENSION POINT: add chip config overrides here.

            // Example: if (M.chipName === "NE555") { M.width = 80; M.height = 150; }

         },



         // ============================================================

         // VIEW — render()

         // "Dumb" renderer. Reads ONLY Manifest + State. Writes to Fabric.

         // Runs on EVERY cycle change — keep it fast.

         //

         // Layers (strict z-order, bottom → top):

         //   L1  Router        PCB traces + shadows

         //   L2  Chip          Package body + pins + live values + X-ray SVG

         //   L3  Scope         Dual-beam oscilloscope with edge seeking

         //   L4  Probes        Heads, badges, snap glow, rename click

         //   L5  Signal Table  Full pin value readout (key: T)

         //   L6  Param Sliders Live ide.patch controls (key: P)

         //   L7  Cross-pane    Waveform viewer zoom/nav controls

         //   L8  HUD           Hints, status, cycle counter

         //

         // EXTENSION: Add L9+ by appending a new isolated block.

         //            Each layer reads M/S only — no cross-layer state.

         // ============================================================

         render() {

            // ── BOILERPLATE (always at top) ─────────────────────

            const VI = this._VI; if (!VI) return;

            VI.clearAll();



            const self = this;

            const M    = self.Manifest;

            const S    = self.State;

            const pane = self._viz.pane;

            const wd   = pane.waveData;

            const CYC  = pane.cyc;



            if (!M || !wd) return;



            // ── LAYOUT CONSTANTS ─────────────────────────────────

            // Adjust SCOPE dimensions to resize the oscilloscope panel.

            const SCOPE = { x: 40,  y: 40, w: 490, h: 440 };

            const PLOT  = {

               x: SCOPE.x + 20,

               y: SCOPE.y + 52,

               w: SCOPE.w - 40,

               h: SCOPE.h - 72

            };

            const NUM_PROBES = Math.max(S.probes.length, 1);

            const chH = PLOT.h / NUM_PROBES;



            // ── UTILITY FUNCTIONS ────────────────────────────────

            // Wrap all signal reads in try/catch — stale signals throw

            const getInt = function(path, cyc) {

               try { return wd.getSignalValueAtCycleByName(path, cyc).asInt(0); }

               catch(e) { return 0; }

            };

            const getHex = function(path, cyc) {

               try { return wd.getSignalValueAtCycleByName(path, cyc).asHexStr("0", 0); }

               catch(e) { return "?"; }

            };

            const resolveProbe = function(target, cyc) {

               if (!target || target.type === "nc")  return -1;

               if (target.type === "vcc")             return  1;

               if (target.type === "gnd")             return  0;

               if (!target.path)                      return -1;

               return getInt(target.path, cyc) & 1;

            };

            // Convert hex color string to rgba — for transparency effects

            const hexRgba = function(hex, alpha) {

               try {

                  const r = parseInt(hex.slice(1, 3), 16);

                  const g = parseInt(hex.slice(3, 5), 16);

                  const b = parseInt(hex.slice(5, 7), 16);

                  return "rgba(" + r + "," + g + "," + b + "," + alpha + ")";

               } catch(e) { return "rgba(200,200,200," + alpha + ")"; }

            };



            // ── L1: ROUTER ───────────────────────────────────────

            // 3-tier Manhattan routing (scope-wrap / chip-wrap / free-space).

            // EXTENSION: Replace pts[] calculation with ELKjs for auto-routing.

            // EXTENSION: Bundle probes on same pin into a visual bus.

            S.probes.forEach(function(probe, idx) {

               const entryY = PLOT.y + (idx + 0.5) * chH;

               const busX   = SCOPE.x + SCOPE.w + 18 + idx * 14;

               const behindScope = (probe.x < busX + 10) &&

                                   (probe.y > SCOPE.y - 20) &&

                                   (probe.y < SCOPE.y + SCOPE.h + 20);

               const behindChip  = (probe.x > M.chipX + 10) &&

                                   (probe.y > M.chipY - 20) &&

                                   (probe.y < M.chipY + M.height + 20);

               let pts;

               if (behindScope) {

                  const safeY = probe.y < (SCOPE.y + SCOPE.h / 2)

                                   ? SCOPE.y - 22 - idx * 8

                                   : SCOPE.y + SCOPE.h + 22 + idx * 8;

                  const leftX = Math.min(probe.x - 18, SCOPE.x - 22 - idx * 8);

                  pts = [[SCOPE.x + SCOPE.w, entryY], [busX, entryY],

                         [busX, safeY], [leftX, safeY],

                         [leftX, probe.y], [probe.x, probe.y]];

               } else if (behindChip) {

                  const safeY = probe.y < (M.chipY + M.height / 2)

                                   ? M.chipY - 22 - idx * 8

                                   : M.chipY + M.height + 22 + idx * 8;

                  const rightX = Math.max(probe.x + 18, M.chipX + M.width + 22 + idx * 8);

                  pts = [[SCOPE.x + SCOPE.w, entryY], [busX, entryY],

                         [busX, safeY], [rightX, safeY],

                         [rightX, probe.y], [probe.x, probe.y]];

               } else {

                  pts = [[SCOPE.x + SCOPE.w, entryY],

                         [busX, entryY], [busX, probe.y],

                         [probe.x, probe.y]];

               }

               // Drop shadow (sent to back)

               VI.poly("sh" + probe.id, pts.map(function(p) { return [p[0]+2, p[1]+2]; }),

                       "rgba(0,0,0,0.45)", 4, true);

               // PCB trace

               VI.poly("w" + probe.id, pts, probe.color, 2, false);

            });



            // ── L2: CHIP ─────────────────────────────────────────

            // Data-driven from Manifest. Click to toggle X-ray.

            // X-ray: embeds real Yosys SVG from session.on("graph").

            // VERIFIED: session.on("graph") SVG injection — Cookbook §12, §21

            // EXTENSION: Parse SVG to extract node positions for pin-snap upgrade.

            // EXTENSION: Add multi-chip support by iterating a chips[] array.



            // Chip body click zone — toggle X-ray

            VI.onClick("chip_xray", M.chipX, M.chipY, M.width, M.height, function() {

               S.showXRay = !S.showXRay;

               VI.redraw();

            });



            // Render all pins BEFORE package body (body partially overlaps — correct)

            M.pins.forEach(function(p) {

               const ax = M.chipX + p.dx;

               const ay = M.chipY + p.dy;



               // Pin pad — color-coded by type

               const padFill   = (p.type === "vcc") ? "#9a1515"

                               : (p.type === "gnd") ? "#155215" : "#8a7830";

               const padStroke = (p.type === "vcc") ? "#cc2222"

                               : (p.type === "gnd") ? "#1e7a1e" : "#c0a040";

               VI.rect("pad" + p.id,

                  (p.side === "L" ? ax - 22 : ax), ay - 10,

                  22, 20, padFill, padStroke, 1, 2);



               // Pin label

               const lx = (p.side === "L") ? ax - 84 : ax + 28;

               VI.label("pl" + p.id, p.name, lx, ay - 9, "#888", 10);



               // Bit-width badge for multi-bit signals

               if (p.sigWidth > 1) {

                  VI.label("pw" + p.id, "[" + p.sigWidth + "b]", lx, ay + 4, "#555", 8);

               }



               // Live value on pin face (sig pins only)

               // VERIFIED: wd.getSignalValueAtCycleByName — Cookbook §3

               if (p.type === "sig" && p.path) {

                  const raw     = getInt(p.path, CYC);

                  const dispVal = (p.sigWidth > 4) ? ("0x" + getHex(p.path, CYC)) : String(raw);

                  const valCol  = raw !== 0 ? "#55dd55" : "#555";

                  const vx = (p.side === "L") ? (M.chipX - 14) : (M.chipX + M.width - 8);

                  VI.label("pv" + p.id, dispVal, vx, ay - 8, valCol, 9, "bold");

               }

            });



            // Package body (drawn over pin pads — intentional)

            VI.rect("pkg", M.chipX, M.chipY, M.width, M.height,

               S.showXRay ? "rgba(14,18,20,0.18)" : "#181a1f", "#000", 2, 4);



            // Pin 1 marker

            VI.rect("dot", M.chipX + 10, M.chipY + 10, 8, 8,

               S.showXRay ? "rgba(255,255,255,0.06)" : "#222", "transparent", 0, 4);



            // X-ray / normal body content

            if (S.showXRay && S.graphSvg) {

               // Real Yosys schematic SVG embedded in chip body

               if (!S._svgFabricImg) {

                  // First frame after toggle: async load, fires redraw when done

                  const svgURL = "data:image/svg+xml," + encodeURIComponent(S.graphSvg);

                  fabric.Image.fromURL(svgURL, function(img) {

                     if (img) { S._svgFabricImg = img; VI.redraw(); }

                  });

               } else {

                  // Re-add each frame (clearAll removed it from canvas)

                  const img    = S._svgFabricImg;

                  const scaleX = (M.width  - 14) / Math.max(img.width  || 100, 1);

                  const scaleY = (M.height - 36) / Math.max(img.height || 100, 1);

                  const sc     = Math.min(scaleX, scaleY) * 0.88;

                  img.set({

                     left: M.chipX + 7, top: M.chipY + 22,

                     scaleX: sc, scaleY: sc,

                     selectable: false, evented: false, opacity: 0.82

                  });

                  self.getCanvas().add(img);

               }

               // Trigger live signal coloring in the Diagram pane

               // VERIFIED: graph.updateSignalColor — Cookbook §12

               try {

                  const graph = pane.ide.viewer._modelViews[0];

                  if (graph && typeof graph.updateSignalColor === "function") {

                     graph.updateSignalColor();

                  }

               } catch(e) {}

               VI.label("die_lbl", "RTL DIE VIEW",

                  M.chipX + 8, M.chipY + M.height - 16, "#1f4a1f", 9);



            } else if (!S.showXRay) {

               VI.label("silk", M.chipName,

                  M.chipX + 14, M.chipY + M.height / 2 - 8, "#555", 13, "bold");

            } else {

               // X-ray active but SVG not yet available

               VI.label("xray_wait", "AWAITING SYNTHESIS",

                  M.chipX + 8, M.chipY + M.height / 2 - 6, "#1a3d1a", 9);

            }



            VI.label("chip_hint", "[X] X-RAY  [CLICK CHIP]",

               M.chipX - 4, M.chipY - 18, "#3a3a3a", 9);



            // ── L3: SCOPE ────────────────────────────────────────

            // Dual-beam oscilloscope with bit-accurate traces.

            // Uses SignalValue.getNextTransitionCycle() for edge markers.

            // VERIFIED: getNextTransitionCycle — Cookbook §4

            // EXTENSION: Add FFT mode using Math functions.

            // EXTENSION: Add trigger mode using sig.forwardToValue().

            // EXTENSION: Add persistence (ghost trace from prev cycle).



            // Background

            VI.rect("sc_bg",   SCOPE.x, SCOPE.y, SCOPE.w, SCOPE.h, "#0d0f14", "#2c313c", 2, 8);

            VI.label("sc_hdr", "DUAL-BEAM ANALYZER",

               SCOPE.x + 14, SCOPE.y + 14, "#aaa", 11, "bold");

            VI.label("sc_cyc", "CYC " + CYC + " / " + M.endCyc,

               SCOPE.x + SCOPE.w - 90, SCOPE.y + 14, "#666", 9);



            // +/- probe count buttons

            VI.rect("b_add", SCOPE.x + SCOPE.w - 58, SCOPE.y + 10, 24, 20, "#1a1a1a", "#4fc3f7", 1, 4);

            VI.label("l_add", "+", SCOPE.x + SCOPE.w - 51, SCOPE.y + 12, "#4fc3f7", 14);

            VI.onClick("btn_add", SCOPE.x + SCOPE.w - 58, SCOPE.y + 10, 24, 20,

               function() { S.addProbe(); VI.redraw(); });



            VI.rect("b_rm",  SCOPE.x + SCOPE.w - 28, SCOPE.y + 10, 24, 20, "#1a1a1a", "#ff5252", 1, 4);

            VI.label("l_rm", "-",  SCOPE.x + SCOPE.w - 20, SCOPE.y + 12, "#ff5252", 14);

            VI.onClick("btn_rm",  SCOPE.x + SCOPE.w - 28, SCOPE.y + 10, 24, 20,

               function() { S.removeProbe(); VI.redraw(); });



            // Plot area

            VI.rect("plot_bg", PLOT.x, PLOT.y, PLOT.w, PLOT.h, "#050907", "#1a2a1a", 1);



            const CYCLES = 20;

            const stepX  = PLOT.w / CYCLES;

            const startCyc = Math.max(M.startCyc, CYC - 10);



            // Grid verticals (every 2 cycles)

            for (let g = 0; g <= CYCLES; g += 2) {

               VI.rect("gv" + g, PLOT.x + g * stepX, PLOT.y, 1, PLOT.h, "#0c1e12");

            }

            // Grid horizontals (channel dividers)

            for (let ch = 1; ch < S.probes.length; ch++) {

               VI.rect("gh" + ch, PLOT.x, PLOT.y + ch * chH, PLOT.w, 1, "#0d2010");

            }

            // Cycle cursor at CYC

            if (CYC >= startCyc && CYC <= startCyc + CYCLES) {

               VI.rect("cursor",

                  PLOT.x + (CYC - startCyc) * stepX + stepX / 2,

                  PLOT.y, 2, PLOT.h, "#333");

            }

            // Cycle-number ruler (every 4 cycles)

            for (let g = 0; g <= CYCLES; g += 4) {

               VI.label("cl" + g, String(startCyc + g),

                  PLOT.x + g * stepX - 4, PLOT.y + PLOT.h + 4, "#3a3a3a", 9);

            }



            // Waveform traces per probe

            S.probes.forEach(function(probe, idx) {

               const yBase = PLOT.y + (idx + 1) * chH - chH * 0.18;

               const amp   = chH * 0.54;



               // Channel label + connected pin name

               const tgtLabel = probe.target

                  ? (probe.target.name + (probe.target.sigWidth > 1 ? "[" + probe.target.sigWidth + "]" : ""))

                  : "DISC";

               VI.label("pn"  + probe.id, probe.name,

                  PLOT.x + 6,  yBase - amp - 16, probe.color, 11, "bold");

               VI.label("pt"  + probe.id, ">" + tgtLabel,

                  PLOT.x + 48, yBase - amp - 16, "#666", 9);



               // Live value readout at CYC

               if (probe.target && probe.target.path) {

                  const curVal = (probe.target.sigWidth > 4)

                     ? ("0x" + getHex(probe.target.path, CYC))

                     : String(getInt(probe.target.path, CYC));

                  VI.label("pval" + probe.id, curVal,

                     PLOT.x + PLOT.w - 38, yBase - amp - 16, probe.color, 10, "bold");



                  // Next-edge indicator via SignalValue seeking

                  // VERIFIED: getNextTransitionCycle — Cookbook §4

                  try {

                     const sv      = wd.getSignalValueAtCycleByName(probe.target.path, CYC);

                     const nxtCyc  = sv.getNextTransitionCycle();

                     const nxtRel  = nxtCyc - startCyc;

                     if (nxtCyc !== undefined && nxtRel > 0 && nxtRel <= CYCLES) {

                        VI.rect("nedge" + probe.id,

                           PLOT.x + nxtRel * stepX - 1, PLOT.y,

                           1, PLOT.h, hexRgba(probe.color, 0.25));

                     }

                  } catch(e) {}

               }



               // Waveform trace segments

               for (let k = 0; k < CYCLES; k++) {

                  const c  = startCyc + k;

                  const v  = resolveProbe(probe.target, c);

                  const vp = resolveProbe(probe.target, c - 1);

                  const x0 = PLOT.x + k * stepX;

                  if (v === -1) {

                     // Disconnected — faint dashed line

                     VI.rect("tn" + probe.id + k, x0, yBase - amp / 2, stepX - 1, 1, "#252525");

                  } else {

                     // Horizontal trace

                     VI.rect("th" + probe.id + k,

                        x0, v ? (yBase - amp) : yBase, stepX, 2, probe.color);

                     // Vertical transition edge

                     if (v !== vp && vp !== -1 && k > 0) {

                        const top_ = Math.min(v ? (yBase - amp) : yBase, vp ? (yBase - amp) : yBase);

                        VI.rect("tv" + probe.id + k, x0, top_, 2, amp, probe.color);

                     }

                  }

               }

            });



            // ── L4: PROBE HEADS ──────────────────────────────────

            // Always top z-order. Draggable (handled in init() Module 4).

            // Snap glow when connected. Click badge to rename.

            // EXTENSION: Add long-press color picker.

            S.probes.forEach(function(probe) {

               // Outer halo

               VI.rect("ha" + probe.id, probe.x - 14, probe.y - 14, 28, 28,

                       "transparent", probe.color, 1.5, 14);

               // Inner dot

               VI.rect("bo" + probe.id, probe.x - 6,  probe.y - 6,  12, 12,

                       "#000", probe.color, 2, 6);

               // Snap glow (visible when target is set)

               if (probe.target) {

                  VI.rect("glow" + probe.id, probe.x - 17, probe.y - 17, 34, 34,

                     "transparent", hexRgba(probe.color, 0.22), 7, 17);

               }

               // Name badge

               VI.rect("bg" + probe.id, probe.x - 20, probe.y - 35, 40, 17,

                       "#111", "#444", 1, 4);

               VI.label("lb" + probe.id, probe.name,

                        probe.x - 16, probe.y - 33, probe.color, 11, "bold");

               // Click badge to rename

               VI.onClick("ren" + probe.id, probe.x - 20, probe.y - 35, 40, 17,

                  function() {

                     const n = prompt("Rename probe (max 4 chars):", probe.name);

                     if (n !== null) {

                        probe.name = (n.substring(0, 4).toUpperCase()) || probe.name;

                        self._saveProbeState();

                        VI.redraw();

                     }

                  }

               );

            });



            // ── L5: SIGNAL TABLE (key: T) ─────────────────────────

            // Full pin value readout at CYC. Hex for wide signals.

            // EXTENSION: Add I2C/SPI bus decode pattern matching.

            // EXTENSION: Add dec/hex/bin toggle per row.

            if (S.showSignalTable) {

               const TX = SCOPE.x + SCOPE.w + 22;

               const TY = M.chipY + M.height + 22;

               const TH = Math.min(M.pins.length * 15 + 22, 200);

               VI.rect("tbl_bg",  TX, TY, 230, TH, "#0c0e13", "#2a2f3a", 1, 4);

               VI.label("tbl_hdr", "PINS @ CYC " + CYC, TX + 6, TY + 5, "#888", 9, "bold");

               let rowY = TY + 20;

               M.pins.forEach(function(p) {

                  if (rowY > TY + TH - 6) return;

                  if (p.type !== "sig" || !p.path) {

                     VI.label("tr_" + p.id, p.name + ": " + p.type.toUpperCase(),

                              TX + 6, rowY, "#444", 9);

                  } else {

                     const raw  = getInt(p.path, CYC);

                     const disp = (p.sigWidth > 4) ? ("0x" + getHex(p.path, CYC)) : String(raw);

                     VI.label("tr_" + p.id, p.name + ": " + disp,

                              TX + 6, rowY, raw ? "#5dd580" : "#666", 9);

                  }

                  rowY += 15;

               });

               VI.onClick("tbl_close", TX + 210, TY + 4, 14, 14,

                  function() { S.showSignalTable = false; VI.redraw(); });

               VI.label("tbl_x", "x", TX + 212, TY + 4, "#555", 10);

            }



            // ── L6: PARAM SLIDERS (key: P) ────────────────────────

            // Drag sliders to call VI.ide.patch() and recompile live.

            // EXTENSION: Push slider configs to S.paramSliders in init().

            // RULE: VI.ide.patch() is called from click handler — safe.

            if (S.showParamSliders && S.paramSliders.length > 0) {

               const SLX = SCOPE.x;

               const SLY = SCOPE.y + SCOPE.h + 32;

               const SLH = S.paramSliders.length * 30 + 18;

               VI.rect("par_bg",  SLX, SLY, SCOPE.w, SLH, "#0c0e13", "#2a2f3a", 1, 4);

               VI.label("par_hdr", "LIVE PARAMETERS" + (VI.ide.available ? "" : " (IDE OFFLINE)"),

                  SLX + 6, SLY + 5, "#888", 9, "bold");

               S.paramSliders.forEach(function(sl, si) {

                  const sy = SLY + 18 + si * 28;

                  const sw = SCOPE.w - 86;

                  VI.label("sl_lbl" + si, (sl.label || sl.name).substring(0, 10),

                     SLX + 6, sy + 1, "#888", 9);

                  VI.rect("sl_track" + si, SLX + 82, sy + 2, sw, 8, "#1e1e1e", "#444", 1, 4);

                  const frac = (sl.value - sl.min) / Math.max(sl.max - sl.min, 1);

                  VI.rect("sl_head" + si, SLX + 82 + frac * sw - 5, sy - 3, 10, 18,

                     "#3a9ab0", "#4fc3f7", 1, 3);

                  VI.label("sl_val" + si, String(sl.value),

                     SLX + 82 + sw + 6, sy + 1, "#4fc3f7", 9);

                  // Slider click zone — patches TLV param and recompiles

                  VI.onClick("sl_z" + si, SLX + 82, sy - 5, sw, 22, function(cx) {

                     sl.value = Math.round(sl.min +

                        (cx - (SLX + 82)) / sw * (sl.max - sl.min));

                     sl.value = Math.max(sl.min, Math.min(sl.max, sl.value));

                     if (VI.ide.available) VI.ide.patch(sl.name, sl.value);

                     VI.redraw();

                  });

               });

            }



            // ── L7: CROSS-PANE CONTROLS ───────────────────────────

            // Drive the WaveformGenerator directly from this viz.

            // VERIFIED: wg.zoomIn/Out/Full/reachStart/End — Cookbook §10

            // VERIFIED: pane.ide.viewer.wg — Cookbook §2, §10

            const WX = M.chipX;

            const WY = M.chipY + M.height + 22;

            VI.label("wf_ttl", "WFM:", WX, WY + 4, "#555", 9);

            const wfBtns = [

               { id: "zi",  lbl: "Z+",  cb: function() { try { pane.ide.viewer.wg.zoomIn();    } catch(e) {} } },

               { id: "zo",  lbl: "Z-",  cb: function() { try { pane.ide.viewer.wg.zoomOut();   } catch(e) {} } },

               { id: "zf",  lbl: "FIT", cb: function() { try { pane.ide.viewer.wg.zoomFull();  } catch(e) {} } },

               { id: "rs",  lbl: "|<",  cb: function() { try { pane.ide.viewer.wg.reachStart(); } catch(e) {} } },

               { id: "re",  lbl: ">|",  cb: function() { try { pane.ide.viewer.wg.reachEnd();   } catch(e) {} } },

               { id: "hl",  lbl: "HI",  cb: function() {

                  const pr = S.probes.find(function(p) { return p.target && p.target.logicalEntity; });

                  if (pr) try { pane.highlightLogicalElement(pr.target.logicalEntity); } catch(e) {}

               }}

            ];

            wfBtns.forEach(function(b, bi) {

               const bx = WX + 30 + bi * 34;

               VI.rect("wfb_" + b.id, bx, WY, 30, 18, "#151515", "#3a3a3a", 1, 3);

               VI.label("wfl_" + b.id, b.lbl, bx + 5, WY + 2, "#668", 9);

               VI.onClick("wfbtn_" + b.id, bx, WY, 30, 18, b.cb);

            });



            // ── L8: HUD ───────────────────────────────────────────

            // Status, hotkey reference, sig count. Always visible.

            const HY1 = SCOPE.y + SCOPE.h + 14;

            const HY2 = HY1 + 13;

            VI.label("hud1",

               "[DRAG] PROBE  [CLICK BADGE] RENAME  [x] XRAY  [t] TABLE  [p] PARAMS",

               SCOPE.x, HY1, "#333", 9);

            VI.label("hud2",

               "[h] HIGHLIGHT  [+/-] PROBES  [ARROWS] STEP  [z/Z/f] WFM ZOOM",

               SCOPE.x, HY2, "#333", 9);

            VI.label("hud_sigs",

               "SIGS: " + M.totalSigs + "   CYC: " + CYC + " / " + M.endCyc,

               M.chipX, M.chipY - 20, "#3d4a3d", 9);

            if (!VI.ide.available) {

               VI.label("hud_ide", "IDE BRIDGE OFFLINE",

                  M.chipX, M.chipY - 10, "#4a3333", 9);

            }

            // Active mode badges

            const badgeX = M.chipX + M.width + 10;

            if (S.showXRay) {

               VI.rect("bdg_xr", badgeX, M.chipY, 42, 14, "#0d2a0d", "#1e7a1e", 1, 3);

               VI.label("bdg_xr_l", "XRAY", badgeX + 4, M.chipY + 2, "#2a9a2a", 9);

            }

            if (S.showSignalTable) {

               VI.rect("bdg_tbl", badgeX, M.chipY + 18, 42, 14, "#0d1f2a", "#1e5a7a", 1, 3);

               VI.label("bdg_tbl_l", "TABLE", badgeX + 4, M.chipY + 20, "#2a7aaa", 9);

            }



            // EXTENSION POINT — Add L9, L10... blocks here.

            // Pattern: isolated block that reads M and S, writes via VI.rect/label/onClick.

            // Ideas:

            //   L9  Timing ruler — measure pulse width between two probes

            //   L10 Bus decoder  — I2C/SPI/UART pattern recognition

            //   L11 FSM view     — state machine visualization using sigHier

            //   L12 Grid heatmap — pipeline occupancy (new this.global.Grid(...))

         }

\SV

   endmodule

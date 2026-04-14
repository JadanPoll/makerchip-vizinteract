# Makerchip VizJS Internal API — Complete Cookbook
*Discovered via source exploration and console.log probing, April 2026*
*All items [VERIFIED] unless marked [INFERRED] or [SOURCE-CONFIRMED]*

---

## Table of Contents

1. [VizInteract v2.0 — Full Boilerplate](#1-vizinteract-v20--full-boilerplate)
2. [Access Paths — The Full Map](#2-access-paths--the-full-map)
3. [Signal Reading — Native API](#3-signal-reading--native-api)
4. [SignalValue Methods — Complete Reference](#4-signalvalue-methods--complete-reference)
5. [SignalValueSet — Multi-Signal Operations](#5-signalvalueset--multi-signal-operations)
6. [WaveData Methods](#6-wavedata-methods)
7. [Transitions Array Format](#7-transitions-array-format)
8. [Pane Proto Methods — Full List](#8-pane-proto-methods--full-list)
9. [Cycle Control](#9-cycle-control)
10. [Cross-Pane Control — WaveformGenerator](#10-cross-pane-control--waveformgenerator)
11. [Cross-Pane Control — NavTLV](#11-cross-pane-control--navtlv)
12. [Cross-Pane Control — Schematic (Graph)](#12-cross-pane-control--schematic-graph)
13. [Session — EventEmitter & Play Control](#13-session--eventemitter--play-control)
14. [IDE Bridge — Editor & Recompile](#14-ide-bridge--editor--recompile)
15. [Fabric Object Enhancements](#15-fabric-object-enhancements)
16. [Camera Control](#16-camera-control)
17. [VizPane Grid — 2D Pixel Canvas](#17-vizpane-grid--2d-pixel-canvas)
18. [topInstance & VizElement Internals](#18-topinstance--vizelement-internals)
19. [Synthetic WaveData Injection](#19-synthetic-wavedata-injection)
20. [Color System](#20-color-system)
21. [Compilation Lifecycle — Full Event Catalog](#21-compilation-lifecycle--full-event-catalog)
22. [Pane Registry & Tab Control](#22-pane-registry--tab-control)
23. [Sandbox Environment — Available Globals](#23-sandbox-environment--available-globals)
24. [Patterns — Interaction Recipes](#24-patterns--interaction-recipes)
25. [Gotchas — Complete List](#25-gotchas--complete-list)
26. [Future Investigation — Remaining Unknowns](#26-future-investigation--remaining-unknowns)

---
IMPORTANT: NO SINGLE QUOTES IN VIZ_JS
## 1. VizInteract v2.0 — Full Boilerplate

Paste the entire `init()` library block at the top of your `init()`. Add the two-line boilerplate at the top of `render()`. Optionally define `onTraceData()`.

```javascript
\viz_js
   box: {width: 640, height: 480, fill: "#0a0a0a"},

   init() {
      // ================================================================
      // START VizInteract v2.0 — do not modify this block
      // ================================================================
      const self = this;
      const VI = {};
      this._VI = VI;

      VI._labels      = {};
      VI._objects     = {};
      VI._hotkeys     = {};
      VI._clickZones  = [];
      VI._hoverZones  = {};
      VI._lastHovered = {};

      // VI.redraw() — declarative repaint
      VI.redraw = function() {
         if (self._viz && self._viz.pane) {
            const pane = self._viz.pane;
            if (typeof pane.unrender === "function") pane.unrender();
            if (typeof pane.render   === "function") pane.render();
         }
         self.getCanvas().renderAll();
      };

      // Focus management
      const canvasEl    = fabric.document.querySelector("canvas");
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

      // VI.toCanvasCoords(clientX, clientY)
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

      // VI.label(id, text, x, y, color, fontSize)
      VI.label = function(id, text, x, y, color, fontSize) {
         const c = self.getCanvas();
         if (!VI._labels[id]) {
            const obj = new fabric.Text(String(text), {
               left: x, top: y,
               fontSize: fontSize || 16,
               fill: color || "#e0e0e0",
               selectable: false, evented: false,
               hasControls: false, hasBorders: false
            });
            c.add(obj);
            VI._labels[id] = obj;
         } else {
            VI._labels[id].set("text", String(text));
            if (color)    VI._labels[id].set("fill",     color);
            if (fontSize) VI._labels[id].set("fontSize", fontSize);
         }
         return VI._labels[id];
      };

      // VI.rect(id, x, y, w, h, fill, stroke)
      VI.rect = function(id, x, y, w, h, fill, stroke) {
         const c = self.getCanvas();
         if (!VI._objects[id]) {
            const obj = new fabric.Rect({
               left: x, top: y, width: w, height: h,
               fill: fill || "#444",
               stroke: stroke || "#fff", strokeWidth: 1,
               selectable: false, evented: false,
               hasControls: false, hasBorders: false
            });
            c.add(obj);
            VI._objects[id] = obj;
         } else {
            if (fill)   VI._objects[id].set("fill",   fill);
            if (stroke) VI._objects[id].set("stroke", stroke);
         }
         return VI._objects[id];
      };

      // Hit zone registration
      VI.onClick = function(id, x, y, w, h, callback) {
         VI._clickZones = VI._clickZones.filter(function(z) { return z.id !== id; });
         VI._clickZones.push({id, x, y, w, h, cb: callback});
      };
      VI.onHover = function(id, x, y, w, h, onEnter, onLeave) {
         VI._hoverZones[id] = {x, y, w, h, enter: onEnter, leave: onLeave};
      };
      VI.onKey = function(key, callback) {
         VI._hotkeys[key] = callback;
      };

      // VI.clearAll() / VI.clearZones()
      VI.clearAll = function() {
         const c = self.getCanvas();
         c.clear();
         c.selection  = false;
         VI._labels     = {};
         VI._objects    = {};
         VI._clickZones = [];
         VI._hoverZones = {};
      };
      VI.clearZones = function() {
         VI._clickZones = [];
         VI._hoverZones = {};
      };

      // Hit test
      const _hit = function(zone, cx, cy) {
         return cx >= zone.x && cx <= zone.x + zone.w &&
                cy >= zone.y && cy <= zone.y + zone.h;
      };

      // Mouse and keyboard listeners
      fabric.document.addEventListener("mousedown", function(e) {
         if (focusTarget) focusTarget.focus();
      });
      fabric.document.addEventListener("mouseup", function(e) {
         if (_editorHasFocus()) return;
         const pos = VI.toCanvasCoords(e.clientX, e.clientY);
         VI._clickZones.forEach(function(zone) {
            if (_hit(zone, pos.x, pos.y)) zone.cb(pos.x, pos.y);
         });
      });
      fabric.document.addEventListener("mousemove", function(e) {
         if (_editorHasFocus()) return;
         const pos = VI.toCanvasCoords(e.clientX, e.clientY);
         Object.keys(VI._hoverZones).forEach(function(id) {
            const zone     = VI._hoverZones[id];
            const inside    = _hit(zone, pos.x, pos.y);
            const wasInside = VI._lastHovered[id];
            if (inside && !wasInside) {
               VI._lastHovered[id] = true;
               if (zone.enter) zone.enter(pos.x, pos.y);
            } else if (!inside && wasInside) {
               VI._lastHovered[id] = false;
               if (zone.leave) zone.leave(pos.x, pos.y);
            }
         });
      });
      fabric.window.addEventListener("keydown", function(e) {
         if (_editorHasFocus()) return;
         if (VI._hotkeys[e.key]) VI._hotkeys[e.key](e);
      });

      // ================================================================
      // IDE bridge
      // ================================================================
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

      VI.ide.getCode = function() {
         if (!VI.ide.available) return null;
         try {
            const r = VI.ide._m.getCode();
            if (r && typeof r.code === "string") { VI.ide._lastGen = r.changeGeneration; return r; }
         } catch(e) {}
         return null;
      };
      VI.ide.recompile = function(newCode) {
         if (!VI.ide.available || VI.ide._busy) return false;
         try {
            VI.ide._busy = true;
            VI.ide._m.loadProject(newCode);
            setTimeout(function() { VI.ide._busy = false; }, 3000);
            return true;
         } catch(e) { VI.ide._busy = false; return false; }
      };
      VI.ide.patch = function(name, value) {
         const r = VI.ide.getCode();
         if (!r) return false;
         const rx = new RegExp("\\$" + name + "\\s*\\[\\d+:\\d+\\]\\s*=\\s*[^;]+;", "g");
         if (!rx.test(r.code)) return false;
         const repl    = "$$" + name + "[7:0] = " + value + ";";
         const newCode = r.code.replace(rx, repl);
         if (newCode === r.code) return false;
         return VI.ide.recompile(newCode);
      };
      VI.ide.patchState = function(name, value) {
         const r = VI.ide.getCode();
         if (!r) return false;
         const rx = new RegExp("\\*" + name + "\\s*=\\s*[^;]+;", "g");
         if (!rx.test(r.code)) return false;
         const newCode = r.code.replace(rx, "*" + name + " = " + value + ";");
         if (newCode === r.code) return false;
         return VI.ide.recompile(newCode);
      };
      VI.ide.setCycle = function(n) {
         try {
            if (VI.ide.available && VI.ide._ide.viz &&
                typeof VI.ide._ide.viz.setCycle === "function") {
               VI.ide._ide.viz.setCycle(n); return true;
            }
         } catch(e) {}
         return false;
      };

      // Camera
      VI.camera = {
         getScale:       () => self._viz.pane.content.contentScale,
         getFocus:       () => self._viz.pane.content.userFocus,
         setScale:       (n) => { self._viz.pane.content.contentScale = n; },
         setFocus:       (x, y) => { self._viz.pane.content.userFocus = {x, y}; },
         apply:          () => self._viz.pane.content.refreshContentPosition(),
         pixelsToUnits:  (px) => self._viz.pane.content.pixelsToUserUnits(px),
         zoomBy:         (exp) => self._viz.pane.content.zoomContentBy(exp),
         zoomAt:         (exp, x, y) => self._viz.pane.content.zoomContentByAt(exp, x, y),
         panBy:          (dx, dy) => self._viz.pane.content.panContentBy(dx, dy),
         center:         () => self._viz.pane.content.centerContent(),
         focusOn:        (x, y) => self._viz.pane.content.focusContentOn(x, y)
      };

      // ================================================================
      // END VizInteract v2.0 — your init() code starts here
      // ================================================================
   },

   onTraceData() {
      // Reset cached signal-derived state here on each recompile.
      // Canvas is NOT yet rendered — do not touch Fabric objects here.
   },

   render() {
      // ================================================================
      // VizInteract v2.0 render() boilerplate — always at the top
      const VI = this._VI; if (!VI) return;
      VI.clearAll();
      // ================================================================
      // After clearAll(): recreate labels/rects, re-register zones.
      // Read signals here only — reads are stale outside render().
   }
```

---

## 2. Access Paths — The Full Map

```javascript
// Core
const pane    = this._viz.pane;           // VizPane — the main controller
const wd      = pane.waveData;            // WaveData — signals and transitions
const session = pane.session;             // Session — EventEmitter, cycle, playback
const ide     = pane.ide;                 // IDE — all panes, editor, bridge
const top     = pane.topInstance;         // VizInstanceElement — live Fabric hierarchy root

// Sibling panes (via _modelViews array)
const graph   = pane.ide.viewer._modelViews[0]; // Graph (schematic pane)
const wfv     = pane.ide.viewer._modelViews[1]; // WaveformViewer
const nav     = pane.ide.viewer._modelViews[2]; // NavTLV

// WaveformGenerator — the waveform renderer
const wg      = pane.ide.viewer.wg;       // WaveformGenerator

// Camera / scaling
const content = pane.content;             // ScalableFabric

// Scroll controls
const sw      = pane.scrollWrapper;       // ScrollWrapper

// Direct pane registry (all panes by mnemonic)
// Keys: "Editor", "Log", "Nav-TLV", "Diagram", "Viz", "Waveform"
const allPanes = fabric.window.ide ? Object.keys(fabric.window.ide.session.compilations) : {};
// Better: use TabbedView.allPanes (accessible as fabric.window.TabbedView if needed)

// Context — 'this' inside viz_js
// top.context === this (VizJSContext)
// this._viz   === top  (VizInstanceElement)
// this.global === pane.vizGlobal === {canvas, Grid}
```

---

## 3. Signal Reading — Native API

These work anywhere, including event handlers. Unlike the sugar API (`'$sig'.asInt()`), these are NOT restricted to `render()`.

```javascript
// Get a Variable object by full name
const sig = wd.getSignalByName("TLV|calc$my_sig");   // TLV signal
const sig = wd.getSignalByName("SV.cyc_cnt");         // SV signal

// Read value at a specific cycle
sig.getValueAtCycle(n)                    // → raw binary string e.g. "00000110"
sig.getValueAndValidAtCycle(n)            // → [binaryString, bool]
sig.getValueAtCycleAndStage(cyc, stage)   // → binary string, TLV stage-aware
sig.getValueAndValidAtCycleAndStage(cyc, stage) // → [binaryString, bool]
sig.getTransIndexOfCycle(n)               // → integer index into transitions[]
sig.isTlvSig()                            // → boolean

// Convenience — returns a full SignalValue object
wd.getSignalValueAtCycleByName("SV.cyc_cnt", 5)
// → SignalValue {signal, cyc, transitions, transIndex}

// Variable metadata fields
sig.width        // bit width (Number)
sig.scope        // "SV", "TLV|calc", etc.
sig.fullName     // full signal name string
sig.notFullName  // signal name without scope prefix
sig.nickname     // single-char VCD nickname
sig.type         // "wire"
sig.ports        // Verilog port spec e.g. "[31:0]"
sig.conditions   // Array of condition Variable objects (after lookupConditionSignals)
sig.transitions  // raw transitions array — see Section 7
sig.anchors      // sparse index array for fast binary search

// Sugar API — render() only, preprocessed by SandPiper
'$my_sig'.asInt()          // TLV signal as integer
'$ready'.asBool()          // 1-bit as boolean
'>>1$my_sig'.asInt()       // retimed 1 cycle ago
this.sigVal("cyc_cnt")     // SV signal by name (no prefix)
this.sigRef("|calc$reset", 0) // TLV signal by path and phase offset

// RULE: Single quotes only for sugar API. Double quotes are plain JS strings and throw.
// RULE: '*signal' sugar does NOT exist. Wrap: $my_sig[N:0] = *sv_sig[N:0]; then use '$my_sig'.
```

---

## 4. SignalValue Methods — Complete Reference

A `SignalValue` represents a signal at a particular cycle. It is the object returned by `getSignalValueAtCycleByName`, `sigRef`, `sigVal`, and the sugar API.

```javascript
const sv = wd.getSignalValueAtCycleByName("SV.cyc_cnt", pane.cyc);

// ── Value access ─────────────────────────────────────────────
sv.asInt(def)           // → Number (NaN if x/z). Throws if width > 53 bits.
sv.asSignedInt(def)     // → two's complement signed Number
sv.asBigInt(def)        // → BigInt (safe for any width)
sv.asBool(def)          // → Boolean. Throws if not 1-bit.
sv.asHexStr("0", def)   // → hex string with x/z handling
sv.asBinaryStr(def)     // → raw binary string
sv.asIntStr("", false, def) // → decimal string, optional sign and padding
sv.asString(def)        // → SV string interpretation (ASCII packed bits)
sv.asReal(def)          // → IEEE 754 float. Requires 32 or 64-bit signal.
sv.asRealFixed(places, def) // → fixed-decimal real. Requires 64-bit.
sv.asColor(def)         // → CSS "#rrggbb". Requires 12, 16, 24, or 32-bit signal.
sv.v                    // shorthand for asInt(). Throws for real/string types.
sv.getValueStr()        // → raw binary string at current cycle
sv.isValid()            // → boolean validity flag
sv.toString(space)      // → formatted display string (same as waveform viewer)

// ── Positioning ──────────────────────────────────────────────
sv.goTo(cyc)            // go to cycle (uses anchors for efficiency)
sv.jumpTo(cyc)          // go to cycle via anchors (always fast path)
sv.stepTo(cyc)          // go to cycle by walking transitions (best for small deltas)
sv.step(n)              // advance by n cycles (positive or negative)
sv.stepByCyc(n)         // alias for step(n)
sv.stepTransition(n)    // step forward/backward n transitions (value changes)
sv.goToSimStart()       // jump to start of trace
sv.goToSimEnd()         // jump to end of trace
sv.goToNextTransition() // jump to next value change
sv.goToPrevTransition() // jump to previous value change
sv.nextCycle()          // alias for goToNextTransition
sv.prevCycle()          // alias for goToPrevTransition

// ── Seeking ──────────────────────────────────────────────────
sv.forwardToValue(val)  // step forward until asInt() === val. Returns bool success.
sv.backToValue(val)     // step backward until asInt() === val. Returns bool success.

// ── Transition inspection ────────────────────────────────────
sv.getTransitionCycle()          // cycle at which current value was assigned
sv.getNextTransitionCycle()      // cycle of next transition
sv.getPrevTransitionValueStr()   // binary string before current value
sv.getNextTransitionValueStr()   // binary string after next transition
sv.isPrevTransitionValid()       // validity before current value
sv.isNextTransitionValid()       // validity after next transition
sv.getCycle()                    // current cycle

// ── Boundary detection ───────────────────────────────────────
sv.inTrace()            // true if within trace bounds (inclusive)
sv.offEnd()             // true if past end of trace
sv.offBeginning()       // true if before start of trace
sv.exists()             // false only for the non-existent sentinel SignalValue

// ── Static methods ───────────────────────────────────────────
SignalValue.representValue(type, value, width, valid, maxChars)
// → [displayText, titleText] — same formatting the schematic uses
// type: "wire" | "real" | "string"
// value: binary string
// Example: SignalValue.representValue("wire", "00001010", 8, true, 10)
// → ["0a", "8'h0a\n8'd10"]

// ── Primitive coercion ───────────────────────────────────────
// SignalValue supports [Symbol.toPrimitive]:
//   hint "number" → asInt() or asReal()
//   hint "string" → toString()
// So: sv + 1, `value: ${sv}`, and if (sv > 5) all work directly.

// ── Error types ──────────────────────────────────────────────
SignalValue.NonExistentSignalError  // thrown when signal is missing from trace
SignalValue.TypeError               // thrown for type mismatches (e.g. asBool on 8-bit)
```

---

## 5. SignalValueSet — Multi-Signal Operations

`SignalValueSet` lets you step multiple signals in unison, preserving their relative cycle offsets.

```javascript
// Create from render()
const set = this.signalSet({
   addr:   wd.getSignalValueAtCycleByName("TLV|pipe$addr",   pane.cyc),
   data:   wd.getSignalValueAtCycleByName("TLV|pipe$data",   pane.cyc),
   valid:  wd.getSignalValueAtCycleByName("TLV|pipe$valid",  pane.cyc)
});

// Access individual signal
set.sig("addr").asInt()

// Step all signals in unison
set.step(1)               // advance all by 1 cycle
set.step(-3)              // back 3 cycles
set.goTo(10)              // all go to cycle 10
set.goToSimStart()        // all go to trace start
set.goToSimEnd()          // all go to trace end

// Representative-based operations (step via rep, sync others by delta)
set.forwardToValue(set.sig("valid"), 1)   // advance until valid === 1
set.backToValue(set.sig("valid"), 1)      // backward until valid === 1
set.stepTransition(set.sig("addr"), 1)    // step to next addr transition, sync others

// Arbitrary operation on rep, delta applied to rest
set.do(set.sig("addr"), function(rep) {
   return rep.forwardToValue(255);        // any SignalValue method
});
```

---

## 6. WaveData Methods

```javascript
const wd = pane.waveData;

// Signal lookup
wd.getSignalByName(fullName)               // → Variable or null
wd.getSignalValueAtCycleByName(name, cyc)  // → SignalValue
wd.getScopeByName(name)                    // → scope string
wd.getSignals()                            // → Object of all Variables
wd.getSignalNames()                        // → Array of full name strings
wd.getNumSignals()                         // → Number

// Cycle / time
wd.getStartCycle()       // → Number (usually -5)
wd.getEndCycle()         // → Number (last transition cycle)
wd.getEndViewerCycle()   // → endCycle + 0.5 (what the viewer uses for right edge)
wd.getTimescale()        // → {number, unit}
wd.timeToCycle(time)     // → Number (converts raw VCD time to cycle number)
wd.anchorIndexToCycle(i) // → cycle for anchor index i

// Internal processing (called by constructor — can be called manually after mutation)
wd.updateData(vcdString)    // full re-parse from new VCD string
wd.computeAnchors(transitions) // → anchor array for a transitions array
wd.lookupConditionSignals() // resolve condition strings to Variable objects
wd.generateInvalids()       // apply condition signals to produce validity flags

// Live mutation — add synthetic transitions to existing signals
wd.addPoint(nickname, cycleNumber, binaryValueString)
// nickname: single-char VCD nickname (e.g. sig.nickname)
// cycleNumber: the cycle (already in cycle units, not VCD time units)
// binaryValueString: e.g. "00001010"
// NOTE: call wd.computeAnchors() and sig._setTransitions() after bulk addPoint calls
//       to keep getTransIndexOfCycle() working correctly.

// Properties
wd.signals          // Object<fullName, Variable>
wd.names            // Array of full name strings
wd.wavesByNickname  // Object<nickname, {vars: Variable[], transitions: []}>
wd.sigHier          // Scope tree root — see Section 6a
wd.startCycle       // Number
wd.endCycle         // Number
wd.numSignals       // Number
wd.numTlvSignals    // Number
wd.sandSim          // Boolean — true for Makerchip sandbox sims
wd.cycleLength      // Number — length of one cycle in time units
wd.cycleLengthConsistent // Boolean — false if trace had inconsistent timesteps
wd.cycleZeroTime    // Number — VCD time of cycle 0
wd.edgeAlignmentCount // Number — positive = aligned to even edges
wd.TIME_SLOT_WIDTH  // 10 — cycles per anchor
wd.TRANSITION_FIELDS // 3 — items per transition triplet

// Signal hierarchy tree (sigHier)
// sigHier                  root Scope {parent, isTlv, name, sigs, children}
//   .sigs: {clk, reset}    top-level SV signals
//   .children.TLV          TLV subtree
//     .children["|calc"]   one node per pipeline
//       .sigs              signals in that pipeline
//   .children.SV           SV subtree
//     .sigs                flat SV signals
//     .children[mod]       one node per SV submodule

// Traverse all signals in |calc pipeline:
const sigs = wd.sigHier.children["TLV"].children["|calc"].sigs;
Object.keys(sigs).forEach(name => console.log(name, sigs[name].width));

// Scope.getFullScope() — full path string for any node
wd.sigHier.children["SV"].getFullScope() // → "SV"
wd.sigHier.children["TLV"].children["|calc"].getFullScope() // → "TLV|calc"
```

---

## 7. Transitions Array Format

Every `Variable.transitions` and every `wavesByNickname[nick].transitions` has this layout:

```
[ cycle0, valueStr0, valid0,   cycle1, valueStr1, valid1, ... ]
  [  0  ]    [  1  ]  [ 2 ]   [  3  ]    [  4  ]   [  5 ]
```

- Every 3rd item (index 0, 3, 6…) is a **cycle number** (Number, may be fractional e.g. -4.5 for clock edges)
- Every 3rd+1 item (index 1, 4, 7…) is a **binary string** value e.g. `"00001010"` (or `"0"`/`"1"` for 1-bit)
- Every 3rd+2 item (index 2, 5, 8…) is a **validity boolean** (`true` = valid, `false` = when-condition false, `undefined` = unknown)
- `TRANSITION_FIELDS = 3` — confirmed constant
- `TIME_SLOT_WIDTH = 10` — cycles between anchor points

```javascript
// Manual read from transitions (bypass SignalValue entirely):
const t   = sig.transitions;
const idx = sig.getTransIndexOfCycle(pane.cyc);
const val = t[idx + 1];    // binary string
const ok  = t[idx + 2];    // validity
const cyc = t[idx];        // cycle this value started

// Build synthetic transitions:
const fakeTrans = [
   -5, "00000000", true,
    0, "00000001", true,
    5, "00000010", true,
   10, "00000011", true
];
```

---

## 8. Pane Proto Methods — Full List

All 70 methods on `Object.getPrototypeOf(pane)`:

```
constructor       hackFabric          _animateForAtLeast   _renderNeeded
init              resize              onViz                listenToCompilation
gotCompileResults initOpened          prepModel            updateCycle
render            unrender            model (getter)       logicalModel (getter)
lastCompileID     vcdCompileID        parseModelCompileID  vizGlobal (getter)
oldTopInstance    topInstance         logicalInstances     cyc
renderedCyc       lastRenderCyc       _renderCnt           maxAnimateTime
animateInterval   immediateAnimate    readyWaveData        defaultVizSrc
steppable         cycEl               waveData             scrollWrapper
steppableInitDOM  updatePlayStateUI   updateBubble         setWaveData
goDead            goLive              prevCycle            nextCycle
setCycle          setMyCycle          scalable             contentContainerEl
content           dragging            ZOOM_BUTTON_MASK     ZOOM_SLUGGISHNESS
PINCH_SLUGGISHNESS WHEEL_ZOOM_SLUGGISHNESS_PIXELS          WHEEL_ZOOM_SLUGGISHNESS_LINES
WHEEL_ZOOM_SLUGGISHNESS_PAGES         scalableInitDOM      userCoordsOfContainerEvent
public            blade               _modelViews          modelViews
highlightLogicalElement               highlightBehHier     unhighlightBehHiers
unhighlightLogicalElements            _highlightLogicalElement
_unhighlightLogicalElements           _highlightBehHier    _unhighlightBehHiers
```

Key methods:

```javascript
pane.render()          // re-run all viz_js render() blocks. Assert renderedCyc === null first.
pane.unrender()        // tear down canvas. Sets renderedCyc = null.
pane.updateCycle(n)    // unrender + set cyc + render
pane.setWaveData(wd)   // install new WaveData, update slider range, sync cycle
pane.goLive()          // set isLive = true, add "live-mode" CSS, call myGoLive()
pane.goDead()          // set isLive = false, remove "live-mode" CSS, call myGoDead()
pane.setCycle(n)       // → session.setCycle(n) — GLOBAL, moves all panes
pane.setMyCycle(n)     // bounds-check + move THIS pane's scroll bar and cycle only
pane.prevCycle()       // decrement by 1
pane.nextCycle()       // increment by 1
pane._renderNeeded(immediately) // schedule a canvas repaint (0ms or 30ms delay)

// Cross-pane highlight — broadcasts to Graph, WaveformViewer, NavTLV simultaneously
pane.highlightLogicalElement(le, remainHighlighted)
// le: logical entity string e.g. "/entry[2]|data$my_sig"
// remainHighlighted: true to add without clearing previous (ctrl-click behavior)

pane.highlightBehHier(le, remainHighlighted)
// targets behavioral hierarchy elements (pipelines, stages)
// vs. highlightLogicalElement which targets logical/structural elements

pane.unhighlightLogicalElements()  // clear all logical highlights
pane.unhighlightBehHiers()         // clear all behavioral hierarchy highlights

// Rendering state
pane.cyc            // current displayed cycle
pane.renderedCyc    // currently rendered cycle (null if unrendered)
pane.lastRenderCyc  // previously rendered cycle
pane._renderCnt     // incremented on each render pass — use to abort stale animations
pane.isLive         // boolean — live mode active
pane.lastCompileID  // string ID of most recent compilation
```

---

## 9. Cycle Control

```javascript
// ── Global (moves all panes) ──────────────────────────────────
pane.setCycle(n)          // → session.setCycle(n) → session.updateCycle + stop playing
session.setCycle(n)       // same

session.updateCycle(n)    // move cycle without stopping playback. Emits "cycle-update".

// ── Local (this pane only) ───────────────────────────────────
pane.setMyCycle(n)        // bounds-check, update scroll bar, update this pane's cyc
VI.ide.setCycle(n)        // scrub viz playhead via IDE bridge (also local-ish)

// ── Waveform cursor only ─────────────────────────────────────
wg.setVizCursorCycle(n)           // move the orange cursor line in waveform view
wg.setLineByCycle(n)              // move the cursor line (alias)
wg.setLineByPosition(relX)        // move cursor by pixel X position
wg.setLineBySignalCycle(sigName, cyc) // jump to cycle where signal transitions

// ── Playback ────────────────────────────────────────────────
session.updatePlayState(isPlaying, cycleTimeout)
// isPlaying: boolean or null (null = no change)
// cycleTimeout: ms per step or null (null = no change)
// Examples:
session.updatePlayState(true)         // start playing at current speed
session.updatePlayState(false)        // pause
session.updatePlayState(true, 500)    // play at 2x speed (500ms per cycle)
session.updatePlayState(null, 250)    // change speed to 4x without changing play state
session.isPlaying                     // current play state
session.cycleTimeout                  // current timeout in ms (1000 = 1x)
```

---

## 10. Cross-Pane Control — WaveformGenerator

```javascript
const wg = pane.ide.viewer.wg;

// ── Zoom & navigation ────────────────────────────────────────
wg.zoomIn(scale, cursorCycle)   // scale: optional multiplier, cursorCycle: center point
wg.zoomOut(scale, cursorCycle)
wg.zoomFull()                   // fit all cycles in view
wg.moveLeft()                   // pan left
wg.moveRight()                  // pan right
wg.reachStart()                 // jump to beginning
wg.reachEnd()                   // jump to end

// ── Signal tree ──────────────────────────────────────────────
wg.expandScope(logicalInstance)     // expand a scope in the signal list
wg.collapseScope(logicalInstance)   // collapse e.g. wg.collapseScope("SV")
wg.expandAllScopes()
wg.collapseAllScopes()              // auto-called when numTlvSignals > 50

// ── Waveform rendering ───────────────────────────────────────
wg.generateWave(start, end, width)  // full re-render of waveform display
wg.createWave(wave)                 // render a single row. wave = {type, signal}
                                    // type: "real" | "SCOPE" | "wire"
wg.processSignal(sv, drawFn)        // low-level per-signal SVG generation

// ── State properties ─────────────────────────────────────────
wg.allRows          // Array of all row objects [{key, signal, visible, type, width, data, svg}]
wg.visibleRows      // only currently visible rows
wg.numVisible       // count of visible rows
wg.currentStart     // left edge cycle of current view
wg.currentEnd       // right edge cycle of current view
wg.pixelsPerCycle   // current zoom level
wg.cyclesPerPixel   // inverse of pixelsPerCycle
wg.lineCycle        // current cursor cycle
wg.textRegionWidth  // pixel width of signal name column
wg.windowWidth      // total pixel width
wg.ELEMENT_HEIGHT   // pixel height of each row
wg.generation       // increments on each re-render
```

---

## 11. Cross-Pane Control — NavTLV

```javascript
const nav = pane.ide.viewer._modelViews[2];

// Force NavTLV to refresh inline values to a specific cycle
nav.updateValueSpans(cyc)  // updates all span[logical_entity] value overlays

// Toggle inline value overlays
nav.showValueSpans()   // jQuery show() on .value-wrapper elements
nav.hideValueSpans()   // jQuery hide() on .value-wrapper elements

// Highlight in NavTLV source view
// (Usually triggered via pane.highlightLogicalElement — but can also do directly)
nav._highlightLogicalElement(le)     // highlights [logical_entity='le'] in nav source
nav._unhighlightLogicalElements()    // clears all highlights

// Properties
nav.navtlv   // the inner navtlv object (empty [] until pane is opened/rendered)
nav.paneEl   // jQuery of the pane DOM element
```

---

## 12. Cross-Pane Control — Schematic (Graph)

```javascript
const graph = pane.ide.viewer._modelViews[0];

// Force schematic to re-color all signals for current cycle
graph.updateSignalColor()    // no-op if !isLive or !waveData
graph.resetSignalColor()     // remove all coloring (returns to static/uncolored state)

// Range sliders (for $ANY signals with ranges)
graph.addRangeSlider()       // inject HTML sliders over ranged cluster nodes
graph.removeRangeSlider()    // remove all sliders, restore original text sizes

// Highlight schematic elements
graph._highlightLogicalElement(le)
graph._unhighlightLogicalElements()

// Signal path translation
// graph.modelManager.getSignalPath(logicalEntity) → TLV signal path string
// logicalEntity: e.g. "/entry[2]|pipe$data"
// Returns: "/entry[2]|pipe$data" with range indices substituted
graph.modelManager.getSignalPath("/entry|pipe$data")
graph.modelManager.resetAllToDefaults()   // reset all range sliders to index 0

// State
graph.isLive     // boolean
graph.cyc        // current cycle
graph.waveData   // WaveData reference
graph.contentContainerEl  // jQuery of SVG container

// ── The $color signal convention (undocumented feature) ──────
// Declare a 24-bit signal named $color alongside a $ANY signal:
//   $my_sig_color[23:0] = 24'd<rgb_value>;   // named: <prefix>$color
// The schematic will use the 24-bit value as literal RGB color for that element.
// The value is interpreted as: bits[23:16]=R, bits[15:8]=G, bits[7:0]=B

// ── getColorForSignal — the exact color algorithm ────────────
session.getColorForSignal(value, valid, width, isColorSignal, isConditional)
// value: binary string | valid: bool | width: Number
// isColorSignal: true if signal name ends in "$color" and width === 24
// isConditional: true if schematic edge has stroke-dasharray (dashed = conditional)
// Returns: CSS rgb() string or null (null = invalid, caller adds gray/invalid CSS class)
//
// Color logic:
//   invalid (valid===false) → null
//   isColorSignal && width===24 → rgb(R, G, B) from 24-bit value
//   isConditional → orange gradient: rgb(200-255, 80-120, 0)
//   normal → purple gradient: rgb(102-144, 0, 128-170)
//
// Base purple (normalizedValue=0): "rgb(102, 0, 170)"  (Session.defaultPurpleColor)

// ── Schematic DOM structure ───────────────────────────────────
// Every signal element in the SVG has: [logical_entity="path"] [cycle_number="N"]
// svgEl.find("[logical_entity]")           — all signal elements
// $(element).attr("logical_entity")        — e.g. "/entry[2]|pipe$data"
// $(element).find("[stroke]")              — the colored path/line elements
// $(element).find("text")                  — the value text overlay
// $(element).is("g.edge")                  — true for edge (wire) elements
// $(element).find("path[stroke]").attr("stroke-dasharray")  — non-empty = conditional
```

---

## 13. Session — EventEmitter & Play Control

```javascript
const session = pane.session;

// ── Events (subscribe with session.on) ───────────────────────
session.on("cycle-update",    (cyc) => {})
// Fires on every cycle change. cyc is the new cycle number.
// This is the canonical hook for syncing any UI to the current cycle.

session.on("play-state-change", (isPlaying, cycleTimeout) => {})
// Fires when play/pause state or speed changes.

session.on("newcompile",      (data) => {})
// Fires when compilation starts. data = {id, sim}

session.on("vcd",             (data) => {})
// Fires when VCD is ready. data = {wd: WaveData, locked: bool}

session.on("vcd-stream",      ({id, waveData, complete}) => {})
// Fires on each VCD chunk during streaming. waveData is null until complete.

session.on("verilator/done",  (data) => {})
session.on("sandpiper/done",  (data) => {})
session.on("parse model",     ({model, id}) => {})
session.on("parse model/done",({success, id, timeout}) => {})
session.on("graphviz/done",   ({success, id}) => {})

session.on("stdall/all",      (html, complete) => {})
// Streaming compile log (HTML formatted). Accumulates across calls.

session.on("makeout/all",     (id, text, complete) => {})
// Streaming Verilator output (plain text). Last line contains "PASSED"/"FAILED"/"max cycles".

session.on("range-update",    ({baseName, newIndex, newValue}) => {})
// Fires when a range slider in the schematic changes.

session.on("simulation-enabled", (enabled) => {})
// Fires when sim is enabled/disabled (VCD locking).

// ── Emit synthetic events (you can emit too) ─────────────────
session.emit("cycle-update", 15)   // broadcast cycle 15 to all panes
// Use with caution — this moves ALL panes.

// ── VCD locking ──────────────────────────────────────────────
session.setLockedVCD(vcdString)   // inject external VCD and lock sim
session.setLockedVCD(false)       // unlock, re-enable simulation

// ── Compilation state ────────────────────────────────────────
session.compilations    // Object keyed by compile ID
session.lastId          // ID of most recent compilation

const comp = session.compilations[pane.lastCompileID];
// comp.id               string
// comp.sim              boolean — was simulation enabled
// comp.status           {parseModel, graph, vcd, sim, sandpiper}
// comp.stdall           accumulated HTML log string
// comp.stdallComplete   boolean
// comp.makeout          accumulated Verilator output string
// comp.makeoutComplete  boolean
// comp.vcdData          raw VCD string
// comp.vcdDataComplete  boolean
// comp.waveData         WaveData object (null until complete)

// ── Pane references ──────────────────────────────────────────
session.editorPane     // Editor pane
session.navTlvPane     // NavTLV pane
session.graphPane      // Graph pane
session.waveformPane   // WaveformViewer pane
session.vizPane        // VizPane (us)
session.logPane        // ErrorLog pane

// ── Model manager ────────────────────────────────────────────
session.modelManager              // ModelManager instance
session.setModelManager(mm)       // swap model manager
session.getResolvedSignalPath(le) // → TLV path with range indices substituted
```

---

## 14. IDE Bridge — Editor & Recompile

```javascript
// Via VI.ide (VizInteract wrapper — recommended, handles debounce)
VI.ide.available                     // boolean — false in sandboxed environments
VI.ide.getCode()                     // → {code: string, changeGeneration: int} or null
VI.ide.recompile(newCode)            // write + trigger recompile. Returns bool.
VI.ide.patch("my_param", 42)         // find $my_param[x:y] = ...; and replace value
VI.ide.patchState("my_var", 42)      // find *my_var = ...; and replace value
VI.ide.setCycle(n)                   // scrub viz playhead (no recompile)

// Via raw IDE object (advanced)
const ide = pane.ide;
ide.IDEMethods.getCode()             // → {code, changeGeneration}
ide.IDEMethods.loadProject(src)      // write src + trigger recompile
ide.IDEMethods.activatePane(mnemonic) // switch active tab by mnemonic
ide.IDEMethods.openStaticPane(mnemonic, background) // open a static pane

// Via session.setCode (silent write — may or may not trigger recompile)
session.setCode(code, clear, comp, triggerChange)
// clear: clear CodeMirror history
// comp: trigger compilation (default true)
// triggerChange: trigger change event (default "default")
// Returns: new CodeMirror changeGeneration or false

// CodeMirror direct access [VERIFIED EXISTS, full behavior use with caution]
const cm = ide.editor.editor;  // raw CodeMirror 5 instance
cm.getValue()                  // get full source text
cm.setValue(src)               // set source text (recompile behavior unverified)
cm.getCursor()                 // cursor position
cm.getSelection()              // selected text
cm.changeGeneration()          // current change generation counter
cm.setCursor(line, ch)         // move cursor (used by NavTLV for line-number clicks)

// NEVER call recompile/patch/loadProject from init() or render() — infinite loop.
// Bridge writes belong ONLY in event handlers (onClick, onKey, DOM listeners).

// _loaded promise — await before using IDE bridge
ide._loaded.then(() => { /* IDE is fully initialized */ });
```

---

## 15. Fabric Object Enhancements

VizPane patches `fabric.Object.prototype` with these additional methods:

```javascript
// ── Promise-based animation ───────────────────────────────────
// Every Fabric object is thenable after animate/wait:
await myRect.animate({left: 100}, {duration: 500});
// or chain:
myRect.animate({opacity: 0}, {duration: 300})
       .thenSet({visible: false})
       .thenWait(200)
       .thenAnimate({left: 0, opacity: 1}, {duration: 400});

// ── Chained methods (all return `this` for chaining) ──────────
obj.thenAnimate(props, options)  // animate after previous promise resolves
obj.thenSet(props)               // set properties after previous promise resolves
obj.thenWait(delayMs)            // wait (scaled by timestep) after previous promise

// ── Promise chain access ──────────────────────────────────────
obj.getPromise()   // get the current Promise for this object
obj.then(fn)       // then on object's promise (aborts if _renderCnt changes)
obj.catch(fn)      // catch
obj.finally(fn)    // finally

// ── Wait (caution — known bug) ────────────────────────────────
obj.wait(delayMs)
// BUG: Built-in wait() uses 'ms' instead of 'delay' — DOES NOT WORK as a standalone call.
// Use thenWait() instead, which works correctly.
// Manual workaround:
new Promise(resolve => setTimeout(resolve, 500 * pane.scrollWrapper.timestep))

// ── Animation time scaling ────────────────────────────────────
// All animate() durations are multiplied by pane.scrollWrapper.timestep
// timestep = cycleTimeout / 1000  (1.0 at normal speed, 0.5 at 2x speed)
// This means animations automatically slow down when playback is slowed down.
const speed = pane.scrollWrapper.timestep;  // read current scale factor

// ── Deprecated methods (still work, print warning) ────────────
obj.setText(text)       // use obj.set({text}) instead
obj.setFill(color)      // use obj.set({fill}) instead
obj.setStroke(color)    // use obj.set({stroke}) instead
obj.setStrokeWidth(n)   // use obj.set({strokeWidth}) instead
obj.setVisible(bool)    // use obj.set({visible}) instead
obj.setOpacity(n)       // use obj.set({opacity}) instead

// ── Render scheduling ─────────────────────────────────────────
// After any direct Fabric mutation outside of render():
pane._renderNeeded(true)   // schedule immediate repaint (0ms)
pane._renderNeeded(false)  // schedule repaint after 30ms
// Do NOT call getCanvas().requestRenderAll() — it does NOT re-run render().
// Use VI.redraw() for declarative re-renders.
```

---

## 16. Camera Control

```javascript
// ── VI.camera wrappers (recommended) ────────────────────────
VI.camera.getScale()          // current zoom (1 = 100%)
VI.camera.getFocus()          // current pan center {x, y}
VI.camera.setScale(n)         // set zoom level
VI.camera.setFocus(x, y)      // set pan center in canvas units
VI.camera.apply()             // apply scale + focus to canvas
VI.camera.pixelsToUnits(px)   // convert screen px to canvas units
VI.camera.zoomBy(exp)         // zoom by power of 2 (1 = 2x, -1 = 0.5x)
VI.camera.zoomAt(exp, x, y)   // zoom by power of 2 centered on canvas point (x, y)
VI.camera.panBy(dx, dy)       // pan by pixel delta
VI.camera.center()            // reset pan to center of userBounds
VI.camera.focusOn(x, y)       // pan to canvas coordinate with bounds clamping

// ── Direct access (same effect) ──────────────────────────────
const c = pane.content;
c.contentScale                  // read/write zoom
c.userFocus                     // read/write {x, y}
c.refreshContentPosition()      // apply both to viewport
c.pixelsToUserUnits(px)         // convert px to canvas units
c.zoomContentBy(exp)            // zoom by power of 2
c.zoomContentByAt(exp, x, y)    // zoom at canvas point
c.panContentBy(dx, dy)          // pan by pixel delta
c.centerContent()               // center on userBounds
c.focusContentOn(x, y)          // clamp-and-focus
c.setContentScale(n)            // set absolute scale

// ── Zoom to fit a region ──────────────────────────────────────
function zoomToRegion(x, y, w, h) {
   const canvas = self.getCanvas();
   const scaleX = canvas.getWidth()  / w;
   const scaleY = canvas.getHeight() / h;
   const scale  = Math.min(scaleX, scaleY) * 0.9;
   VI.camera.setScale(scale);
   VI.camera.setFocus(x + w / 2, y + h / 2);
   VI.camera.apply();
}
```

---

## 17. VizPane Grid — 2D Pixel Canvas

For pipeline stage diagrams, memory maps, heatmaps. Each pixel = one cell.

```javascript
// Constructor (in init() or render()):
// new this.global.Grid(top, context, width, height, imageOptions)
const grid = new this.global.Grid(
   this.global,    // top — pass this.global
   this,           // context — pass 'this' (VizJSContext)
   64,             // width in cells
   32,             // height in cells
   {               // imageOptions — passed to fabric.Image
      left: 0,
      top: 0,
      width: 640,    // rendered pixel width
      height: 320,   // rendered pixel height
      imageSmoothing: false  // default false — keeps pixels sharp
   }
);

// Color individual cells (pixels)
grid.setCellColor(x, y, "#ff0000")   // x, y in cell coords
grid.setCellColor(x, y, "rgba(0, 255, 0, 0.5)")

// Add to canvas
const fabricImg = grid.getFabricObject();  // creates/updates fabric.Image
self.getCanvas().add(fabricImg);

// Get as HTMLImageElement
const imgEl = grid.toImage();

// Pattern: update cells then refresh
for (let i = 0; i < 64; i++) {
   for (let j = 0; j < 32; j++) {
      const val = ...; // some signal value
      grid.setCellColor(i, j, val > 0 ? "#0f0" : "#333");
   }
}
// getFabricObject() re-reads the canvas on each call — call after all setCellColor calls
self.getCanvas().add(grid.getFabricObject());
```

---

## 18. topInstance & VizElement Internals

```javascript
const top = pane.topInstance;   // VizInstanceElement for /top

// Properties
top.context         // VizJSContext — same as 'this' inside viz_js (top.context === this)
top.modelScope      // ParseScope — the parse model node for this block
top.group           // fabric.Group — root Fabric group for this scope
top.whereBox        // fabric.Rect — bounding box in canvas coords
top.renderedObjects // Array<fabric.Object> — objects added by render()
top.initObjects     // Object<name, fabric.Object> — objects from init()
top.objectsArray    // Array<fabric.Object> — all objects in the group
top.children        // Object<name, VizElement> — child scopes by name
top._children       // Array<VizElement> — child scopes (use `of` not `in` for replicated)
top.pane            // VizPane reference
top.depth           // 0 for top-level
top.index           // instance index (0 if not replicated)
top.initResults     // {} — results of init() call

// Methods (from VizElement proto)
top.getVizBlock()       // → VizBlock — the compiled \viz_js block object
top.isInstance()        // → true for VizInstanceElement, false for VizScopeElement
top.isReplica()         // → true if this instance is within a replicated scope
top.name()              // → scope name without prefix char
top.onTraceData([])     // recursively fire onTraceData() on all children
top.render([], pane)    // recursively render all children
top.makeChildren(pane, scopes) // build child VizElement tree

// VizBlock — the compiled viz_js block
const vb = top.getVizBlock();
vb.viz          // the parsed \viz_js object {box, where, template, init, render, ...}
vb.exec         // compiled function (nxCompiler output)
vb.invoke(fn, context, scopes)  // call a function from the block
vb.all          // VizBlock for the 'all' property (replicated scopes)
vb.pane         // VizPane reference

// VizJSContext extras (beyond standard 'this')
this.steppedBy()        // → cyc - lastRenderCyc (cycles since last render)
this.getScope(name)     // → VizElement for named ancestor scope
this.getIndex(name)     // → index of named scope instance
this.getContext()       // → this._viz (VizInstanceElement)
this.getBox()           // → this._viz.initObjects.box (the box Fabric.Rect)
this.obj                // shorthand getter for initObjects
this.getInitObject(name) // → named object from initObjects
this.signalSet(sigs)    // → SignalValueSet
this.newImageFromURL(url, attribution, where, imgOptions)
// Async-safe image loader. Returns a fabric.Group placeholder immediately,
// then adds the loaded Image to it asynchronously.
// attribution: required string (can be ""). Used for license compliance.
// where: {left, top, width, height, ...} or a fabric.Object
// imgOptions: fabric.Image options (width/height override where, scale proportionally)

// positionAncestorObject — place an object from a child scope into an ancestor scope
childScope.positionAncestorObject(ancestorScope, fabricObj, {
   left: 10, top: 20, angle: 0, scale: 1,
   width: 100, height: 50,  // optional: scale to fit
   originX: "center", originY: "center"
});

// upMap — translate {left, top, angle, scale} from this scope to parent
const parentProps = childScope.upMap({left: 10, top: 20, angle: 0, scale: 1});

// ancestorMap — translate across multiple levels
const topProps = childScope.ancestorMap(topScope, {left: 5, top: 5});
```

---

## 19. Synthetic WaveData Injection

Two approaches for injecting fake waveform data.

### Approach A — Patch existing transitions (addPoint)

```javascript
// In an event handler (NOT init/render):
const wd = pane.waveData;

// Find a signal's nickname
const sig = wd.getSignalByName("SV.cyc_cnt");
const nick = sig.nickname;   // e.g. "$"

// Add synthetic transitions
// NOTE: cycles must be in cycle-space (after mapTime), not VCD time units
wd.addPoint(nick, 45, "00101101");   // at cycle 45, value 0x2D
wd.addPoint(nick, 46, "00101110");   // at cycle 46, value 0x2E

// After adding points, recompute anchors for that signal to keep seeks working
const wave = wd.wavesByNickname[nick];
const newAnchors = wd.computeAnchors(wave.transitions);
sig._setTransitions(wave.transitions, newAnchors);

// Then push to all panes
pane.setWaveData(wd);
VI.redraw();
```

### Approach B — Full synthetic WaveData (new WaveData)

```javascript
// Construct a minimal VCD string
const vcd = `$timescale 1ps $end
$var wire 32 $ cyc_cnt $end
$var wire 1  C clk $end
$var wire 1  # reset $end
$enddefinitions $end
#0
$dumpvars
b00000000 $
1C
1#
$end
#1 0C
#2 1C b00000001 $
#3 0C
#4 1C b00000010 $
...`;

// Create with sandSim: false to disable strict assertions
const syntheticWD = new (pane.waveData.constructor)(vcd, false);

// Install into viz pane only (no broadcast)
pane.setWaveData(syntheticWD);
VI.redraw();

// Or broadcast to all panes (waveform, schematic, navTLV):
// session.emit("vcd", {wd: syntheticWD, locked: true});
```

### Approach C — updateData (replace in place)

```javascript
// Re-parse a modified VCD string into the existing WaveData object
// This replaces ALL signals and transitions
pane.waveData.updateData(newVcdString);
pane.setWaveData(pane.waveData);
VI.redraw();
```

---

## 20. Color System

```javascript
// ── session.getColorForSignal ────────────────────────────────
// The exact algorithm the schematic and waveform use for signal coloring.
session.getColorForSignal(value, valid, width, isColorSignal, isConditional)
// → CSS "rgb(r, g, b)" string or null

// value: binary string e.g. "00001010"
// valid: boolean
// width: Number (bit width)
// isColorSignal: true if this is a $color signal (24-bit RGB passthrough)
// isConditional: true for dashed/conditional wires in schematic

// Algorithm:
//   invalid → null (caller adds .invalid-signal CSS class)
//   isColorSignal && width===24 → rgb from 24-bit binary value
//   isConditional → orange gradient:
//     red   = 200 + (normalizedValue * 55)   // 200..255
//     green = 80  + (normalizedValue * 40)   // 80..120
//     → rgb(200-255, 80-120, 0)
//   normal → purple gradient:
//     red   = 102 + (normalizedValue * 42)   // 102..144
//     blue  = 170 - (normalizedValue * 42)   // 128..170
//     → rgb(102-144, 0, 128-170)

Session.defaultPurpleColor   // "rgb(102, 0, 170)" — base purple for valid signals

// ── asColor() — interpret signal bits as CSS color ───────────
const colorSv = wd.getSignalValueAtCycleByName("SV.my_color_sig", pane.cyc);
const cssColor = colorSv.asColor();  // → "#rrggbb"
// Requires 12, 16, 24, or 32-bit signal. Throws SignalValue.TypeError otherwise.
// For 32-bit: includes alpha channel in hex (use carefully).

// ── The $color convention (schematic) ────────────────────────
// Declare in TLV:
//   $my_signal_color[23:0] = 24'd<rgb>;
// The schematic auto-detects signals ending in "$color" with width===24
// and uses their value as literal RGB color for the corresponding $ANY element.
// The associated $ANY signal must also exist.
```

---

## 21. Compilation Lifecycle — Full Event Catalog

```javascript
// ── Event sequence for a typical compilation ──────────────────
// 1. "newcompile"       {id, sim}         — compilation started
// 2. "graph"            svgString          — schematic SVG ready
// 3. "graphviz/done"    {success, id}      — graphviz finished
// 4. "parse model"      {model, id}        — AST ready, triggers onViz()
// 5. "parse model/done" {success, id, timeout}
// 6. "sandpiper/done"   {success, id}      — SandPiper finished
// 7. "navTLV"           htmlString         — NavTLV HTML ready
// 8. "stdall/all"       (html, complete)   — compile log (streaming)
// 9. "vcd-stream"       {id, waveData, complete} — VCD streaming
// 10. "vcd"             {wd, locked}       — WaveData ready
// 11. "verilator/done"  {success, id}      — Verilator finished
// 12. "makeout/all"     (id, text, complete) — Verilator log (streaming)

// ── Error events ──────────────────────────────────────────────
// "sandpiper/done"  {success: "failure", timeout: bool}
// "verilator/done"  {success: "failure", timeout: bool}
// "graphviz/done"   {success: "failure", timeout: bool}

// ── Simulation control ────────────────────────────────────────
// "simulation-enabled"  (bool) — fires when sim is enabled/disabled
// "range-update"        {baseName, newIndex, newValue} — range slider changed

// ── After compilation ─────────────────────────────────────────
// Access compilation result:
const comp = session.compilations[pane.lastCompileID];
comp.stdall          // accumulated HTML compile log
comp.makeout         // accumulated Verilator output (plain text)
comp.vcdData         // raw VCD string
comp.waveData        // WaveData object
comp.status.sim      // "passed" | "failed" | "max-cycles" | null

// Parse pass/fail from makeout:
if (comp.makeout.includes("Simulation PASSED!!!")) { /* passed */ }
if (comp.makeout.includes("Simulation FAILED!!!")) { /* failed */ }
if (comp.makeout.includes("Simulation reached max cycles")) { /* timeout */ }
```

---

## 22. Pane Registry & Tab Control

```javascript
// ── TabbedView.allPanes ───────────────────────────────────────
// Global registry of all panes, accessible via:
const allPanes = fabric.window.ide.session.vizPane.tabbedview.constructor.allPanes;
// Keys: "Editor", "Log", "Nav-TLV", "Diagram", "Viz", "Waveform"

// Activate (switch to) any pane:
fabric.window.ide.activatePane("Waveform")   // switch to waveform tab
fabric.window.ide.activatePane("Diagram")    // switch to schematic tab
fabric.window.ide.activatePane("Editor")     // switch to editor
// Returns: Promise<void>

// ── pane.setStatus ────────────────────────────────────────────
// Set the tab status icon for any pane:
pane.setStatus("success")       // ✓ checkmark
pane.setStatus("fail")          // ✗ red X
pane.setStatus("working")       // spinner
pane.setStatus("warning")       // orange warning
pane.setStatus("outdated")      // blue dot
pane.setStatus("locked")        // used by waveform for locked VCD
pane.setStatus("none")          // no icon
// Also: "still_working", "warning_working", "error_working", "error"

// ── ide._loaded ───────────────────────────────────────────────
// Promise that resolves when IDE is fully initialized
fabric.window.ide._loaded.then(() => {
   // safe to use any IDE API here
});
```

---

## 23. Sandbox Environment — Available Globals

The `\viz_js` sandbox (`VizBlock.staticSandboxEnv`) provides these globals. Everything NOT in this list must be accessed via `fabric.window` or `fabric.document`.

```
// JavaScript builtins:
Infinity, NaN, eval, isFinite, isNaN, parseFloat, parseInt
Object, Function, Boolean, Symbol
Error, EvalError, RangeError, ReferenceError, SyntaxError, TypeError, URIError
Number, BigInt, Math, Date, String, RegExp
Array, Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array,
Int32Array, Uint32Array, Float32Array, Float64Array,
BigInt64Array, BigUint64Array
Map, Set, WeakMap, WeakSet
ArrayBuffer, Atomics, DataView, JSON
Promise, Reflect, Proxy, Intl
console, alert, atob, confirm, prompt
FontFace
fabric              // fabric.js library
document.fonts      // only document.fonts is exposed (not full document)
setInterval, setTimeout, clearInterval, clearTimeout  // bound to window

// NOT available directly (must go through fabric.window / fabric.document):
window, document (full), localStorage, indexedDB, fetch, XMLHttpRequest
location, history, navigator, WebSocket, Worker

// Access pattern for restricted APIs:
fabric.window.localStorage.setItem("myviz.key", value)
fabric.window.fetch("https://example.com/data.json")
fabric.window.indexedDB.open("mydb", 1)
fabric.document.getElementById("some-element")
fabric.window.open("https://companion-app.com?data=" + encoded)
```

---

## 24. Patterns — Interaction Recipes

### Pattern 1: Cycle Enumeration (zero-latency UI)

Pre-compute all states in one sim run, scrub to the matching cycle.

```javascript
// TLV: wire UI inputs to cyc_cnt bits
// $switch_a[1:0] = *cyc_cnt[1:0];
// $switch_b[1:0] = *cyc_cnt[3:2];
// *passed = *cyc_cnt > 16;

init() {
   self.swA = 0; self.swB = 0;
   self._go = function() {
      const cyc = self.swA | (self.swB << 2);
      pane.setMyCycle(cyc);
      VI.redraw();
   };
   VI.onKey("ArrowRight", function() { self.swA = (self.swA + 1) % 4; self._go(); });
   VI.onKey("ArrowLeft",  function() { self.swA = (self.swA + 3) % 4; self._go(); });
},
render() {
   const a = '$switch_a'.asInt();
   const r = '$result'.asInt();   // derived signals automatically correct
   VI.label("r", "result: " + r, 20, 80, "#6f6", 20);
}
```

### Pattern 2: Parameter Patch (recompile path)

```javascript
// TLV: $my_param[7:0] = 8'd5;
VI.onKey("ArrowUp", function() {
   VI.ide.patch("my_param", self.paramVal + 1);
});
```

### Pattern 3: Preview + Commit (hybrid drag)

```javascript
self.previewVal = 128; self.committedVal = 128; self.dragging = false;

fabric.document.addEventListener("mousedown", function(e) {
   const pos = VI.toCanvasCoords(e.clientX, e.clientY);
   if (pos.y >= 194 && pos.y <= 214 && pos.x >= 20 && pos.x <= 420)
      self.dragging = true;
});
fabric.document.addEventListener("mousemove", function(e) {
   if (!self.dragging) return;
   const pos = VI.toCanvasCoords(e.clientX, e.clientY);
   self.previewVal = Math.round((pos.x - 20) * 255 / 400);
   VI._objects["handle"].set({left: pos.x - 6});
   VI.label("readout", "preview: " + self.previewVal, 20, 230);
   VI.redraw();
});
fabric.document.addEventListener("mouseup", function(e) {
   if (!self.dragging) return;
   self.dragging = false;
   if (self.previewVal !== self.committedVal) {
      self.committedVal = self.previewVal;
      VI.ide.patch("my_param", self.previewVal);
   }
});
```

### Pattern 4: Persistent State (survives recompile)

```javascript
const KEY = "myviz.count";
self.count = parseInt(fabric.window.localStorage.getItem(KEY) || "0", 10);
VI.onKey("ArrowRight", function() {
   self.count++;
   fabric.window.localStorage.setItem(KEY, String(self.count));
   VI.redraw();
});
```

### Pattern 5: Sync to Waveform Scrubbing

```javascript
// In init() only — NOT render() (would re-patch on every render)
(function() {
   const viewer = pane.ide.viewer;
   const orig   = viewer.onCycleUpdate;
   viewer.onCycleUpdate = function(cyc) {
      VI.redraw();
      if (orig) orig.apply(this, arguments);
   };
})();
```

### Pattern 6: Session Cycle Sync (alternative)

```javascript
// Subscribe to ALL cycle changes from any pane
session.on("cycle-update", function(cyc) {
   self.currentCyc = cyc;
   VI.redraw();
});
```

### Pattern 7: Auto-Sized Cycle Scrubber

```javascript
render() {
   const wd    = pane.waveData;
   const START = wd.startCycle, END = wd.endCycle;
   const TX = 20, TY = 440, TW = 560, TH = 20;
   VI.rect("timeline", TX, TY, TW, TH, "#222", "#555");
   const headX = TX + (pane.cyc - START) * TW / (END - START);
   VI.rect("head", headX - 2, TY - 5, 4, TH + 10, "#fc0");
   VI.onClick("timeline", TX, TY, TW, TH, function(cx) {
      const cyc = Math.round(START + (cx - TX) * (END - START) / TW);
      session.setCycle(cyc);
      VI.redraw();
   });
}
```

### Pattern 8: Signal Auto-Discovery

```javascript
render() {
   const sigs = Object.keys(wd.signals).filter(k => k.startsWith("TLV|calc"));
   sigs.forEach((name, i) => {
      const sig = wd.signals[name];
      const sv  = wd.getSignalValueAtCycleByName(name, pane.cyc);
      const val = sv ? sv.asInt(0) : 0;
      VI.label("sig_"+i,
         sig.notFullName + "[" + sig.width + "] = " + val,
         20, 20 + i * 20, "#aaa", 12);
   });
}
```

### Pattern 9: Cross-Pane Waveform Control

```javascript
// Drive the waveform viewer from viz keyboard shortcuts
VI.onKey("z", function() { wg.zoomIn(); });
VI.onKey("x", function() { wg.zoomOut(); });
VI.onKey("f", function() { wg.zoomFull(); });
VI.onKey("r", function() { wg.reachStart(); });
VI.onKey("c", function() { wg.setVizCursorCycle(pane.cyc); });
VI.onKey("s", function() { wg.setLineBySignalCycle("SV.my_sig", 0); });
```

### Pattern 10: Seek to Signal Event

```javascript
render() {
   const sig = wd.getSignalValueAtCycleByName("TLV|calc$my_sig", pane.cyc);
   // Find next time my_sig goes high from current cycle
   const sv = wd.getSignalValueAtCycleByName("TLV|calc$my_sig", pane.cyc);
   sv.step(1);
   const found = sv.forwardToValue(1);
   if (found) {
      VI.label("next_high", "next high: cycle " + sv.getCycle(), 20, 60, "#ff0", 14);
      VI.onClick("goto_btn", 20, 80, 100, 30, function() {
         session.setCycle(sv.getCycle());
      });
   }
}
```

### Pattern 11: SignalSet for Multi-Signal Timeline

```javascript
render() {
   const set = this.signalSet({
      addr:  wd.getSignalValueAtCycleByName("TLV|pipe$addr",  pane.cyc),
      data:  wd.getSignalValueAtCycleByName("TLV|pipe$data",  pane.cyc),
      valid: wd.getSignalValueAtCycleByName("TLV|pipe$valid", pane.cyc)
   });
   // Step both to next valid transaction
   set.forwardToValue(set.sig("valid"), 1);
   VI.label("tx_addr", "next tx addr: 0x" + set.sig("addr").asHexStr(), 20, 80, "#0f0", 14);
   VI.label("tx_data", "next tx data: " + set.sig("data").asInt(),       20, 100, "#0f0", 14);
}
```

### Pattern 12: Zoom to Fit on First Render

```javascript
onTraceData() { this._firstRender = true; },
render() {
   const VI = this._VI; if (!VI) return;
   VI.clearAll();
   // ... draw content ...
   if (this._firstRender) {
      this._firstRender = false;
      VI.camera.setScale(0.8);
      VI.camera.setFocus(320, 240);
      VI.camera.apply();
   }
}
```

### Pattern 13: Highlight from Viz Click

```javascript
VI.onClick("my_signal_box", x, y, w, h, function() {
   // Highlight "/my_pipe|stage$my_sig" in schematic, waveform, and navTLV simultaneously
   pane.highlightLogicalElement("/my_pipe|stage$my_sig");
});
```

### Pattern 14: Live Animation with Speed Scaling

```javascript
render() {
   VI.clearAll();
   const box = VI.rect("box", 100, 100, 80, 80, "#369");
   // Animation duration automatically scales with playback speed
   VI._objects["box"]
      .animate({left: 300}, {duration: 800})
      .thenWait(200)
      .thenSet({fill: "#f60"})
      .thenAnimate({left: 100}, {duration: 800});
}
```

### Pattern 15: Companion Web App via localStorage

```javascript
// In viz init():
const KEY = "myviz.channel";
fabric.window.addEventListener("storage", function(e) {
   if (e.key !== KEY) return;
   self.externalCommand = JSON.parse(e.newValue);
   VI.redraw();
});

// Companion web app writes:
// localStorage.setItem("myviz.channel", JSON.stringify({cmd: "goto", cyc: 42}));
// This fires the storage event in the Makerchip iframe automatically.
```

---

## 25. Gotchas — Complete List

```
 1. SINGLE QUOTES for sugar API signal refs, DOUBLE QUOTES for all other strings.
    '$foo'.asInt() → SandPiper rewrites → works
    "$foo".asInt() → plain JS string    → throws TypeError at runtime

 2. '*signal' sugar DOES NOT EXIST. nxCompiler crashes with SyntaxError.
    Wrap: $my_sig[N:0] = *sv_sig[N:0];  then use '$my_sig'.asInt().

 3. Apostrophes and Verilog radix literals crash SandPiper.
    "don't"  → crash. Use String.fromCharCode(39) for apostrophes.
    "8'h01"  → crash. Use decimal (1). Avoid hex radix literals entirely.

 4. String.prototype.replace treats $ as special in replacement strings.
    $$ → literal $. VI.ide.patch() handles this correctly for you.

 5. NEVER call VI.ide.recompile/patch from init() or render().
    Recompile → new viz instance → reruns init() → infinite loop.
    Bridge writes belong ONLY in event handlers.

 6. clearAll() wipes _clickZones and _hoverZones.
    Re-register ALL onClick/onHover inside render() after clearAll().
    _hotkeys are NOT cleared — register once in init().

 7. Use VI.redraw(), not requestRenderAll() or _renderNeeded().
    requestRenderAll() only repaints canvas, does NOT re-run render().
    _renderNeeded() schedules a repaint but also does NOT re-run render().
    VI.redraw() calls pane.unrender() + pane.render() + renderAll() — correct.

 8. Never call pane.render() without pane.unrender() first.
    Without unrender():
      a. Utils.assert() throws a failed assertion error
      b. Fabric objects are silently duplicated → memory leak
    VI.redraw() handles both steps correctly.

 9. Signal reads belong in render(), not in event handlers.
    '$foo'.asInt() in a click handler reads stale values from the last render pass.
    Exception: native API (sig.getValueAtCycle(n), wd.getSignalByName()) works
    anywhere — it takes an explicit cycle argument and is not stale.

10. $BOGUS_USE($signal) silences unused-signal warnings.
    SandPiper's usage analysis does not see into viz_js blocks.
    Every signal read only by viz_js needs:  `BOGUS_USE($my_signal)

11. Only init(), render(), and onTraceData() are valid entry points.
    Arbitrary methods on the \viz_js object literal are not callable as
    this.myHelper(). Define helpers as: self._myHelper = function() {...}

12. The built-in wait() helper has a confirmed bug.
    Uses `ms` (undefined variable) instead of `delay` parameter → does nothing.
    Use thenWait() instead, or:
    new Promise(resolve => setTimeout(resolve, 500 * pane.scrollWrapper.timestep))

13. VI.rect() position is fixed at creation time.
    To move a rect after creation:
      VI._objects["myid"].set({left: newX, top: newY});
      VI.redraw();
    Or use clearAll() to wipe and recreate at new position.

14. setCycle() is GLOBAL — moves ALL panes.
    setMyCycle() moves only this pane.
    VI.ide.setCycle() / pane.updateCycle() are also local.

15. \viz_js must be indented under a pipeline @stage scope.
    Cannot be placed at module top level. Minimum:
      |my_pipe @0 \viz_js ...

16. goLive/goDead stop/start the schematic color update loop.
    Calling goDead() stops the schematic from re-coloring on cycle change.
    This is pane-level state — each pane has its own isLive flag.

17. topInstance.context === this inside viz_js.
    pane.topInstance.context is the VizJSContext — same object as 'this'.
    Useful for cross-scope access patterns.

18. addPoint() uses cycle-space values, not VCD time units.
    The transitions array has already been through mapTime().
    Pass cycle numbers (e.g. 5, 10, 15), NOT raw VCD times (e.g. 10000, 20000).

19. Fabric animation abort on render cycle change.
    Fabric's abort callback returns true when _renderCnt changes, stopping animation.
    Animations started in one render cycle are automatically abandoned when VI.redraw()
    is called. This is intentional — guards against stale animations.

20. session.on() listeners accumulate across recompiles IF you register in init().
    Each recompile creates a new viz instance with a new init() — but session persists.
    Guard with a flag or use once() semantics if needed.

21. asInt() throws for signals wider than 53 bits.
    Use asBigInt() for wide signals, or asHexStr() for display.

22. SignalValueSet.do() preserves relative cycle offsets, not absolute cycles.
    If sigA is at cycle 5 and sigB is at cycle 7 (offset 2), after forwardToValue
    they will be at (new_cyc) and (new_cyc + 2) respectively.

23. wg (WaveformGenerator) is null until first VCD arrives.
    Guard: if (!pane.ide.viewer.wg) return;
```

---

## 26. Future Investigation — Remaining Unknowns

These were identified as existing but their full behavior is unconfirmed:

```javascript
// ── session.setCode vs loadProject ───────────────────────────
// session.setCode(code, clear=false, comp=false, triggerChange=false)
// May allow a silent editor write without triggering compilation.
// Test: call it, watch console for "Started compilation".
// If absent → silent write primitive. Combine with ide.editor.compileThis().

// ── ide.editor.compileThis() ─────────────────────────────────
// Confirmed to exist. Probably triggers recompile of current editor buffer.
// Potential clean recompile pattern: session.setCode(src) + compileThis()
// vs. the current loadProject() approach.

// ── cm.setValue() (CodeMirror) ───────────────────────────────
// Confirmed to exist. Whether it triggers Makerchip's change detection is unknown.
// Could be the actual silent-write primitive bypassing loadProject.

// ── ide.viewer.onCycleUpdate call signature ───────────────────
// Confirmed to receive a cycle number argument (verified by WaveformViewer source).
// Full original implementation: sets wg cursor. Override pattern verified.

// ── wg.createWave / wg.processSignal for row injection ────────
// Source confirmed. wg.createWave({type: "wire", signal: variableObj}) generates SVG.
// Whether adding to allRows and calling generateWave() produces visible new rows
// has not been end-to-end tested.

// ── pane.setWaveData with a fully synthetic WaveData ─────────
// updateSliderRange only calls waveData.getEndCycle() — very thin interface.
// Full synthetic injection (Approach B in Section 19) is plausible but
// the WaveData constructor with sandSim:false and a hand-crafted VCD
// has not been end-to-end tested with all downstream consumers.

// ── pane.id.viewer._modelViews order stability ────────────────
// [0]=Graph, [1]=WaveformViewer, [2]=NavTLV confirmed for current IDE layout.
// May change if pane init order changes. Access by mnemonic is safer:
// const allViews = pane.ide.viewer._modelViews;
// const nav = allViews.find(v => v.bladeName === "NavTLV");

// ── VizElement.operateAlongPath ───────────────────────────────
// Source confirmed. Traverses from one VizElement to another applying
// upCB going up and downCB going down. Could enable cross-scope
// coordinate transformations for multi-scope animations.

// ── pane.logicalInstances ─────────────────────────────────────
// Object keyed by instance path strings like "/my_hier[3]|my_pipe".
// Each entry is a LogicalInstance with a .data property for user state.
// Could be used to persist per-instance state across renders without
// using module-level variables.

// ── getVizBlock() on child instances ────────────────────────
// top.children["calc"].getVizBlock() → VizBlock for |calc's \viz_js block.
// top.children["calc"].context       → VizJSContext for |calc.
// This enables one \viz_js block to call functions in another scope's block:
// top.children["calc"].getVizBlock().invoke("myHelper", context, {})

// ── session.getSettings / setSettings ────────────────────────
// Confirmed to exist. Shape of settings object unknown.
// May expose: clock speed, cycle count limit, sim settings, display preferences.
// Call session.getSettings() in console to discover shape.

// ── VizPane.ScalableFabric.userBounds ────────────────────────
// Set to new Pane.Rect().set(-1000, -1000, 2000, 2000) initially.
// focusContentOn() clamps to userBounds — if you need to pan beyond ±1000,
// expand: pane.content.userBounds.set(-5000, -5000, 10000, 10000)

// ── pane.oldTopInstance ───────────────────────────────────────
// VizScopeContext (legacy \viz_alpha hierarchy). Still rendered alongside topInstance.
// If you need to interact with \viz_alpha-based code, this is the entry point.
// Methods: render(), instances, initObjects, modelScope.
```

---

*End of Cookbook*
*All APIs discovered through console.log probing and source code review of Makerchip internals.*
*These are undocumented internal APIs — may break on any Makerchip update.*
*VizInteract v2.0 drawing/input layer uses stable browser APIs and should work indefinitely.*

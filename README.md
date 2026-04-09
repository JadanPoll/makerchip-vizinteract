# VizInteract

A paste-once library that adds mouse, keyboard, hover, and click-zone support to TL-Verilog `\viz_js` blocks in Makerchip, plus a documented reference for reaching the Makerchip IDE internals from inside a viz (for triggering recompiles from viz code).

## What it does

Out of the box, `\viz_js` gives you a Fabric.js canvas and a `render()` function that runs on sim steps. There's no official API for click handling, keyboard input, hover states, or redrawing the canvas without stepping the simulation. This library adds all of that.

- `VI.onClick(id, x, y, w, h, cb)` — rectangular click zones with hit testing
- `VI.onHover(id, x, y, w, h, enter, leave)` — hover enter/leave callbacks
- `VI.onKey(key, cb)` — keyboard shortcuts with editor-focus guard
- `VI.label(id, text, x, y, color, size)` — create-or-update text in place
- `VI.rect(id, x, y, w, h, fill, stroke)` — create-or-update rectangles in place
- `VI.redraw()` — force a canvas redraw without stepping the sim
- `VI.clearAll()` / `VI.clearZones()` — reset state

There's also an IDE bridge (`VI.ide`) that reads and writes the editor buffer and can trigger real recompiles from inside a viz — useful if you want a button that changes a constant and rebuilds. This part depends on undocumented Makerchip internals and may break on future updates; the library detects this and falls back gracefully.

## Usage

Paste the library block at the top of your `init()`, add the two-line boilerplate at the top of your `render()`, and write your own code after the markers. The file includes a working demo you can delete.

```javascript
init() {
   // --- library block ---
   // (paste once, don't modify)
   // --- end library block ---

   self.count = 0;

   VI.onKey("ArrowRight", function() {
      self.count++;
      VI.redraw();
   });

   VI.onClick("btn", 20, 100, 120, 40, function() {
      self.count = 0;
      VI.redraw();
   });
},
render() {
   const VI = this._VI; if (!VI) return;
   VI.clearAll();

   VI.label("count", "count: " + this.count, 20, 20);
   VI.rect("btn", 20, 100, 120, 40, "#444");
   VI.label("btnlbl", "reset", 55, 115, "#fff");
}
```

## Notes on the focus-management piece

The non-obvious part of getting keyboard input to work is that the Makerchip editor (a CodeMirror textarea) steals focus any time you click it, and the viz canvas never gets keyboard events after that. The naive fix — refocus the canvas on mouseup — doesn't work, because when you click back into the viz area, `activeElement` is still the textarea at mouseup time (the browser hasn't transferred focus yet).

The fix: steal focus on `mousedown` before the guard check runs, not on `mouseup`. The click interaction logic then runs on `mouseup` with focus already correctly transferred.

## The IDE bridge

The library includes a `VI.ide` namespace that reaches `fabric.window.ide.IDEMethods` and exposes:

- `VI.ide.getCode()` — synchronous, returns `{code, changeGeneration}`
- `VI.ide.recompile(newCode)` — writes source and triggers a build
- `VI.ide.patch(name, value)` — regex-replaces `$name[x:y] = ...;` with a new decimal value and recompiles
- `VI.ide.patchState(name, value)` — same but for SV state signals (`*name`)

This is built on undocumented internals. `IDEMethods` exists as Makerchip's Penpal RPC surface for external tooling, and happens to be reachable directly from inside `\viz_js` through `fabric.window`. This may or may not be intentional, and may change in future Makerchip versions. The library handles that gracefully — if the bridge is unreachable, `VI.ide.available` is `false`, bridge calls return `false` with a warning, and the rest of the library keeps working.

**Do not call `VI.ide.recompile` or `VI.ide.patch` from `init()` or `render()`.** Each recompile creates a fresh viz instance that reruns `init()`, so any bridge call made during init produces an infinite loop. Bridge writes belong in event handlers only.

## What's documented but not implemented

The library file itself contains a reference section documenting everything I found while building this but didn't wire in. Short list:

- `ide.session.setCode(code)` — may write the editor buffer without triggering a compile (unverified)
- `ide.editor.compileThis()` — probably what the Compile button calls (unverified)
- `ide.viz.setCycle(n)` / `setMyCycle(n)` — probably scrubs the global playhead (inferred, included in library with a verification note)
- `ide.viz.setWaveData(data)` — probably loads waveform data for display (shape unknown)
- `ide.session.modelManager`, `ide.session.compilations`, `ide.errorlog`, `ide.graph`, `ide.navtlv`, `ide.viewer` — reachable IDE subsystems that might be worth exploring for more advanced integrations
- Browser APIs confirmed available via `fabric.window`: `indexedDB`, `fetch` (against raw.githubusercontent.com and cdn.jsdelivr.net), `window.open`, `paste` events, and the ability to build drag from `mousedown`+`mousemove`+`mouseup`

There's also a confirmed-absent section: I did a recursive hunt across `ide.viz`, `ide.viewer`, `ide.session`, and `modelManager` for any method matching `/^(set|poke|force|override|inject|write|stim)/` combined with `/(sig|signal|val|value|cyc|wave|data|pin|port)/` and found nothing that lets you inject signal values into a running simulation. Makerchip's architecture treats sims as immutable artifacts — to change a signal value you have to rewrite source and recompile. No shortcut exists.

## Gotchas worth knowing

Things that cost me real debugging time and are documented in the library file:

1. **Single quotes inside `\viz_js` are reserved for TLV signal references.** Use double quotes or template literals. Apostrophes in string literals — including Verilog radix notation like `` `8'h01` `` — crash SandPiper. Use decimal or build the string with `String.fromCharCode(39)`.

2. **Only `init()` and `render()` are recognized entry points.** Arbitrary methods like `this._helper()` on the viz_js object literal don't work the way they would on a normal class. Use local closures inside `init` or assign helpers to `self._foo = function() {...}`.

3. **The `\viz_js` block must be indented under a pipeline `@stage` scope** (e.g. `|calc @0`). It can't be at module top level.

4. **`$signal` assignments in TL-Verilog require the `$` prefix on the LHS.** Macros that emit pipesignal assignments need `$$1` (the double-`$` escapes m4 to emit a literal `$`).

5. **`String.prototype.replace` treats `$` as special.** To emit a literal `$` in a replacement string, use `$$`. The `patch()` method handles this.

6. ``` `BOGUS_USE($signal) ``` is required to silence unused-signal warnings when a signal is only read by viz_js, since SandPiper's usage analysis doesn't see into the viz.

## Files

- `vizinteract.tlv` — the library file, includes a minimal working demo

## Status

Built and verified against the Makerchip web IDE. The input/drawing layer is built on standard browser APIs and should work indefinitely. The IDE bridge is built on undocumented internals and may break on any Makerchip update — when that happens, the library's four fallback access paths are documented in the code, and the recursive memory-hunt script I used to find them originally is also in the comments so you can re-run it if all four paths stop working.

## License

MIT. Do whatever you want with it.

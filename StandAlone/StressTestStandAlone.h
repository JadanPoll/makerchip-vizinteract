<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Beast Mode EDA: RTL Stress Test Suite</title>
    <style>
        *, *::before, *::after { box-sizing: border-box; }
        body { font-family: system-ui, sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 20px; margin: 0; }
        h2 { color: #f97171; margin-top: 0; font-size: 1.6rem; text-transform: uppercase; letter-spacing: 1px; }
        h3 { color: #9cdcfe; margin: 0 0 10px; font-size: 1.05rem; }
        p { margin: 0 0 10px; line-height: 1.5; color: #b0b8c8; font-size: 0.9rem; }
        button, select { padding: 11px 22px; font-size: 1rem; background: #1565c0; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; margin-right: 10px; margin-bottom: 8px; transition: background 0.15s; }
        button:hover:not(:disabled), select:hover { background: #1e88e5; }
        button:disabled { opacity: 0.45; cursor: not-allowed; }
        button.green { background: #2e7d32; }
        button.green:hover:not(:disabled) { background: #388e3c; }
        button.red { background: #c62828; }
        button.red:hover:not(:disabled) { background: #e53935; }
        select { background: #333; border: 1px solid #555; }
        .panel { background: #1e2030; border: 1px solid #2a3050; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        #console-log { height: 200px; overflow-y: auto; color: #9cdcfe; white-space: pre-wrap; font-family: monospace; font-size: 0.82rem; border: 1px solid #2a3050; background: #0d0f1a; padding: 10px; border-radius: 6px; line-height: 1.5; }
        .log-err { color: #f97171; }
        .log-ok { color: #69db7c; }
        .log-warn { color: #ffd43b; }
        .schematic-container { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 20px; }
        
        /* Interactive CAD Viewport CSS */
        .schematic-box { flex: 1; min-width: min(100%, 480px); background: #fff; padding: 14px; border-radius: 8px; overflow: hidden; min-height: 500px; border: 2px solid #1565c0; }
        .schematic-box h3 { color: #1a237e; font-size: 0.85rem; margin-bottom: 8px; }
        .schematic-box svg { width: 100%; height: 500px; display: block; border: 1px solid #eee; background: #fafafa; cursor: grab; }
        .schematic-box svg:active { cursor: grabbing; }
        
        textarea { width: 100%; height: 350px; font-family: monospace; font-size: 0.85rem; background: #0d0f1a; color: #ce9178; border: 1px solid #3a2a1a; border-radius: 6px; padding: 12px; resize: vertical; line-height: 1.45; }
        .controls { display: flex; flex-wrap: wrap; gap: 12px; align-items: flex-end; margin-top: 15px;}
        .value-display { font-size: 1.2rem; font-weight: bold; font-family: monospace; background: #111; padding: 8px 16px; border-radius: 6px; min-width: 120px; text-align: center; color: #69db7c; word-break: break-all;}
        .hidden { display: none !important; }
        .control-group { display: flex; flex-direction: column; gap: 4px; }
        .control-group label { font-size: 0.8rem; color: #888; text-transform: uppercase; font-weight: bold; }
        .control-group input { background: #111; color: #fff; border: 1px solid #333; padding: 8px; border-radius: 4px; font-family: monospace; font-size: 1rem; width: 140px; }
        .control-group input.wide-input { width: 450px; font-size: 0.8rem;}
    </style>
</head>
<body>
    <h2>🔥 Beast Mode: RTL Stress Test Suite</h2>
    <p>Testing robust limb-aligned chunking, 16MB Bump Allocator, and signed math boundaries.</p>
    
    <div style="margin-bottom: 16px; display: flex; align-items: center; gap: 15px;">
        <select id="testSelector">
            <option value="wide">Test 1: "The Wide Boy" (256-Bit Dynamic Shifter)</option>
            <option value="ram">Test 2: "RAM Collision" (Dual-Port Race Conditions)</option>
            <option value="dsp">Test 3: "Signed DSP" (Catastrophic Math Boundaries)</option>
        </select>
        <button id="runBtn" class="red">▶ Synthesize & Compile</button>
    </div>
    
    <div class="panel">
        <h3>SystemVerilog Module</h3>
        <textarea id="verilogInput" spellcheck="false"></textarea>
    </div>
    
    <div class="panel">
        <h3>Console / Yosys Log</h3>
        <div id="console-log">Select a test and hit Compile.</div>
    </div>
    
    <div id="visuals" class="hidden">
        <div class="schematic-container">
            <div class="schematic-box">
                <h3>1 · RTL view (Interactive Viewport)</h3>
                <div id="rtlSchematic"><em style="color:#888;font-size:0.85rem;">Rendering…</em></div>
            </div>
            <div class="schematic-box">
                <h3>2 · Post-synth gate-level</h3>
                <div id="synthSchematic"><em style="color:#888;font-size:0.85rem;">Rendering…</em></div>
            </div>
        </div>
    </div>

    <div class="panel hidden" id="statusPanel">
        <h3>Wasm Compilation Status</h3>
        <div id="wasmStatus" style="color: #69db7c; font-family: monospace;">Waiting...</div>
    </div>

    <div id="ui-wide" class="panel hidden">
        <h3>Live Sim: 256-Bit Dynamic Shifter</h3>
        <div class="controls">
            <div class="control-group">
                <label>Data In [255:0] (Hex)</label>
                <input type="text" id="uiWideIn" class="wide-input" value="DEADBEEFCAFEBABEDBADF00D0123456789ABCDEF000000000000000000000001" maxlength="64">
            </div>
            <div class="control-group">
                <label>Shift Amount (0-255)</label>
                <input type="number" id="uiWideShift" value="16" min="0" max="255">
            </div>
            <button id="tickWideBtn" class="green" style="height: 42px; margin-bottom: 0;">⏱ Tick Clock</button>
            <button id="rstWideBtn" class="red" style="height: 42px; margin-bottom: 0;">Reset</button>
        </div>
        <div class="controls" style="margin-top: 15px;">
            <div class="control-group" style="width: 100%;">
                <label>Data Out [255:0] (Hex) = (In &lt;&lt;&lt; Shift) ^ (In &gt;&gt; ~Shift[4:0])</label>
                <div id="uiWideOut" class="value-display" style="text-align: left;">0000000000000000000000000000000000000000000000000000000000000000</div>
            </div>
        </div>
    </div>

    <div id="ui-ram" class="panel hidden">
        <h3>Live Sim: Dual-Port RAM Collision</h3>
        <p style="color:#888; font-size:0.85rem;">Force Addr A == Addr B and set both Write Enables high to test priority masking.</p>
        <div class="controls">
            <div class="control-group"><label>Addr A (0-15)</label><input type="number" id="uiRamAddrA" value="5" min="0" max="15"></div>
            <div class="control-group"><label>Data In A</label><input type="number" id="uiRamDinA" value="1111"></div>
            <div class="control-group"><label>Write Enable A</label>
                <select id="uiRamWeA" style="width:80px; margin-bottom:0;"><option value="1">1</option><option value="0">0</option></select>
            </div>
            <div style="width: 20px;"></div>
            <div class="control-group"><label>Addr B (0-15)</label><input type="number" id="uiRamAddrB" value="5" min="0" max="15"></div>
            <div class="control-group"><label>Data In B</label><input type="number" id="uiRamDinB" value="9999"></div>
            <div class="control-group"><label>Write Enable B</label>
                <select id="uiRamWeB" style="width:80px; margin-bottom:0;"><option value="1">1</option><option value="0" selected>0</option></select>
            </div>
            
            <button id="tickRamBtn" class="green" style="height: 42px; margin-bottom: 0;">⏱ Tick Clock</button>
        </div>
        <div class="controls" style="margin-top: 15px;">
            <div class="control-group"><label>Read Out A</label><div id="uiRamOutA" class="value-display">0</div></div>
            <div class="control-group"><label>Read Out B</label><div id="uiRamOutB" class="value-display" style="color:#7eb8f7;">0</div></div>
        </div>
    </div>

    <div id="ui-dsp" class="panel hidden">
        <h3>Live Sim: Signed Edge-Case DSP</h3>
        <p style="color:#888; font-size:0.85rem;">Try A = -2147483648 and B = -1. Standard C++ usually crashes. We survive.</p>
        <div class="controls">
            <div class="control-group"><label>Input A (int32)</label><input type="number" id="uiDspA" value="-2147483648"></div>
            <div class="control-group"><label>Input B (int32)</label><input type="number" id="uiDspB" value="-1"></div>
            <button id="tickDspBtn" class="green" style="height: 42px; margin-bottom: 0;">⏱ Tick Clock</button>
        </div>
        <div class="controls" style="margin-top: 15px;">
            <div class="control-group" style="width: 100%;">
                <label>MAC Accumulator Out (int64) = Accum + (A / B) * B</label>
                <div id="uiDspOut" class="value-display" style="text-align: left; color:#ffb86c;">0</div>
            </div>
        </div>
    </div>

<script type="module">
    import { runYosys } from 'https://cdn.jsdelivr.net/npm/@yowasp/yosys/gen/bundle.js';
    import { runClang } from 'https://cdn.jsdelivr.net/npm/@yowasp/clang/gen/bundle.js';
    
    const logEl = document.getElementById('console-log');
    const dec = new TextDecoder();
    let wasmInstance = null;
    
    function log(msg, cls = '') {
        const line = document.createElement('span');
        if (cls) line.className = cls;
        line.textContent = msg + '\n';
        logEl.appendChild(line);
        logEl.scrollTop = logEl.scrollHeight;
    }
    
    function toStr(v) { return v ? (typeof v === 'string' ? v : dec.decode(v)) : ''; }

    function fixYosysJson(json) {
        if (!json?.modules) return json;
        const fixVal = (v) => (typeof v === 'string' && /^[01]+$/.test(v) && v.length <= 32) ? parseInt(v, 2) : v;
        const fixAttrs = (obj) => { if (obj) for (const k of Object.keys(obj)) obj[k] = fixVal(obj[k]); };
        for (const mod of Object.values(json.modules)) {
            fixAttrs(mod.attributes);
            for (const cell of Object.values(mod.cells ?? {})) { fixAttrs(cell.attributes); fixAttrs(cell.parameters); }
        }
        return json;
    }

    async function loadScript(src) {
        return new Promise((res, rej) => {
            if (document.querySelector(`script[src="${src}"]`)) { res(); return; }
            const s = document.createElement('script');
            s.src = src; s.crossOrigin = 'anonymous';
            s.onload = res; s.onerror = () => rej(new Error('Failed to load: ' + src));
            document.head.appendChild(s);
        });
    }

    // Safety-Wrapped Render Function with SVG-Pan-Zoom
    async function renderSchematic(containerId, netlistJson) {
        const el = document.getElementById(containerId);
        el.innerHTML = '<em style="color:#888;font-size:0.85rem;">Rendering schematic...</em>';
        try {
            const skin = netlistsvg.digitalSkin;
            const svgElement = await new Promise((resolve, reject) => {
                netlistsvg.render(skin, netlistJson, (err, result) => {
                    if (err) return reject(err);
                    if (!result) return reject(new Error("NetlistSVG failed to generate an image. The logic graph is too complex to route graphically."));
                    resolve(result);
                });
            });

            let svgString = typeof svgElement === 'string' ? svgElement : (svgElement.outerHTML || String(svgElement));
            el.innerHTML = svgString;

            // Initialize pan/zoom
            await loadScript('https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js');
            const svgDom = el.querySelector('svg');
            if (svgDom) {
                svgDom.removeAttribute('width');
                svgDom.removeAttribute('height');
                svgPanZoom(svgDom, {
                    zoomEnabled: true,
                    controlIconsEnabled: true,
                    fit: true,
                    center: true,
                    minZoom: 0.1,
                    maxZoom: 10
                });
            }
        } catch (e) {
            el.innerHTML = `<pre style="color:#f97171;font-size:0.8rem;white-space:pre-wrap;">[Render Bypassed]\n${e.message}</pre>`;
            log(`[Render bypassed] ${containerId}: ${e.message}`, 'log-warn');
        }
    }

    async function fetchCxxrtlHeader() {
        const cdnUrl = 'https://cdn.jsdelivr.net/gh/JadanPoll/makerchip-vizinteract@main/cxxrtl_bare_baremetal.h';
        log(`Fetching core silicon engine from jsDelivr CDN...`);
        const response = await fetch(cdnUrl);
        if (!response.ok) throw new Error(`CDN Fetch failed: ${response.status} ${response.statusText}`);
        log('Core engine fetched successfully.', 'log-ok');
        return await response.text();
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST SUITE DEFINITIONS
    // ─────────────────────────────────────────────────────────────────────
    const TEST_SUITE = {
        wide: {
            top: "stress_wide",
            verilog: `module stress_wide (
    input logic clk,
    input logic rst_n,
    input logic [255:0] data_in,
    input logic [7:0] shift_amt,
    output logic [255:0] data_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) data_out <= 256'b0;
        else data_out <= (data_in <<< shift_amt) ^ (data_in >> (~shift_amt[4:0]));
    end
endmodule`,
            driver: `
#include <cxxrtl/cxxrtl.h>
// 16MB Bump Allocator for dynamic memory in WASM
char memory_pool[16 * 1024 * 1024]; 
size_t memory_ptr = 0;
void* operator new(size_t size) { 
    size_t aligned = (size + 7) & ~7; 
    void* ptr = &memory_pool[memory_ptr]; 
    memory_ptr += aligned; 
    return ptr; 
}
void* operator new[](size_t size) { return operator new(size); }
void operator delete(void*) noexcept {}
void operator delete[](void*) noexcept {}
void operator delete(void*, size_t) noexcept {}
void operator delete[](void*, size_t) noexcept {}

#include "sim.cpp"
cxxrtl_design::p_stress__wide dut;
extern "C" {
    __attribute__((export_name("init"))) void init() { dut.reset(); dut.step(); }
    __attribute__((export_name("tick"))) void tick() { dut.p_clk.data[0]=0; dut.step(); dut.p_clk.data[0]=1; dut.step(); }
    __attribute__((export_name("set_rst"))) void set_rst(int v) { dut.p_rst__n.data[0]=v; dut.step(); }
    __attribute__((export_name("set_shift"))) void set_shift(int v) { dut.p_shift__amt.data[0]=v; dut.step(); }
    __attribute__((export_name("set_data_in"))) void set_data_in(int idx, uint32_t val) { dut.p_data__in.data[idx]=val; dut.step(); }
    __attribute__((export_name("get_data_out"))) uint32_t get_data_out(int idx) { return dut.p_data__out.curr.data[idx]; }
}`
        },
        ram: {
            top: "stress_ram_collision",
            verilog: `module stress_ram_collision (
    input logic clk,
    input logic [3:0] addr_a, input logic [3:0] addr_b,
    input logic [15:0] din_a, input logic [15:0] din_b,
    input logic we_a, input logic we_b,
    output logic [15:0] dout_a, output logic [15:0] dout_b
);
    logic [15:0] dual_port_ram [0:15];
    always_ff @(posedge clk) begin
        if (we_a) dual_port_ram[addr_a] <= din_a;
        dout_a <= dual_port_ram[addr_a];
    end
    always_ff @(posedge clk) begin
        if (we_b) dual_port_ram[addr_b] <= din_b;
        dout_b <= dual_port_ram[addr_b];
    end
endmodule`,
            driver: `
#include <cxxrtl/cxxrtl.h>
char memory_pool[16 * 1024 * 1024]; 
size_t memory_ptr = 0;
void* operator new(size_t size) { 
    size_t aligned = (size + 7) & ~7; 
    void* ptr = &memory_pool[memory_ptr]; 
    memory_ptr += aligned; 
    return ptr; 
}
void* operator new[](size_t size) { return operator new(size); }
void operator delete(void*) noexcept {}
void operator delete[](void*) noexcept {}
void operator delete(void*, size_t) noexcept {}
void operator delete[](void*, size_t) noexcept {}

#include "sim.cpp"
cxxrtl_design::p_stress__ram__collision dut;
extern "C" {
    __attribute__((export_name("init"))) void init() { dut.reset(); dut.step(); }
    __attribute__((export_name("tick"))) void tick() { dut.p_clk.data[0]=0; dut.step(); dut.p_clk.data[0]=1; dut.step(); }
    __attribute__((export_name("set_a"))) void set_a(int addr, int din, int we) { dut.p_addr__a.data[0]=addr; dut.p_din__a.data[0]=din; dut.p_we__a.data[0]=we; dut.step(); }
    __attribute__((export_name("set_b"))) void set_b(int addr, int din, int we) { dut.p_addr__b.data[0]=addr; dut.p_din__b.data[0]=din; dut.p_we__b.data[0]=we; dut.step(); }
    __attribute__((export_name("get_out_a"))) int get_out_a() { return dut.p_dout__a.curr.data[0]; }
    __attribute__((export_name("get_out_b"))) int get_out_b() { return dut.p_dout__b.curr.data[0]; }
}`
        },
        dsp: {
            top: "stress_signed_dsp",
            verilog: `module stress_signed_dsp (
    input logic clk,
    input logic signed [31:0] a,
    input logic signed [31:0] b,
    output logic signed [63:0] mac_result
);
    logic signed [31:0] div_stage;
    logic signed [63:0] accum;
    assign mac_result = accum;

    always_ff @(posedge clk) begin
        div_stage <= a / (b == 0 ? 32'sd1 : b);
        accum <= accum + (div_stage * b);
    end
endmodule`,
            driver: `
#include <cxxrtl/cxxrtl.h>
char memory_pool[16 * 1024 * 1024]; 
size_t memory_ptr = 0;
void* operator new(size_t size) { 
    size_t aligned = (size + 7) & ~7; 
    void* ptr = &memory_pool[memory_ptr]; 
    memory_ptr += aligned; 
    return ptr; 
}
void* operator new[](size_t size) { return operator new(size); }
void operator delete(void*) noexcept {}
void operator delete[](void*) noexcept {}
void operator delete(void*, size_t) noexcept {}
void operator delete[](void*, size_t) noexcept {}

#include "sim.cpp"
cxxrtl_design::p_stress__signed__dsp dut;
extern "C" {
    __attribute__((export_name("init"))) void init() { dut.reset(); dut.step(); }
    __attribute__((export_name("tick"))) void tick() { dut.p_clk.data[0]=0; dut.step(); dut.p_clk.data[0]=1; dut.step(); }
    __attribute__((export_name("set_ab"))) void set_ab(int a, int b) { dut.p_a.data[0]=a; dut.p_b.data[0]=b; dut.step(); }
    __attribute__((export_name("get_mac_l"))) uint32_t get_mac_l() { return dut.p_accum.curr.data[0]; }
    __attribute__((export_name("get_mac_h"))) uint32_t get_mac_h() { return dut.p_accum.curr.data[1]; }
}`
        }
    };

    // ─────────────────────────────────────────────────────────────────────
    // UI & TEST SELECTION LOGIC
    // ─────────────────────────────────────────────────────────────────────
    const testSelector = document.getElementById('testSelector');
    const verilogInput = document.getElementById('verilogInput');

    function loadSelectedTest() {
        const testId = testSelector.value;
        verilogInput.value = TEST_SUITE[testId].verilog;
        
        document.getElementById('ui-wide').classList.add('hidden');
        document.getElementById('ui-ram').classList.add('hidden');
        document.getElementById('ui-dsp').classList.add('hidden');
        document.getElementById('statusPanel').classList.add('hidden');
        document.getElementById('visuals').classList.add('hidden');
        
        wasmInstance = null;
    }

    testSelector.addEventListener('change', loadSelectedTest);
    loadSelectedTest();

    /* ── YOSYS PIPELINE ── */
    async function doFullPipeline() {
        const testId = testSelector.value;
        const testDef = TEST_SUITE[testId];
        
        const verilog = verilogInput.value.trim();
        if (!verilog) return log('Verilog code is empty!', 'log-err');
        
        logEl.textContent = '';
        document.getElementById('runBtn').disabled = true; 
        window.filesOutCache = null;
        
        try {
            log('Loading ELK + NetlistSVG…');
            await loadScript('https://cdn.jsdelivr.net/npm/elkjs/lib/elk.bundled.js');
            await loadScript('https://cdn.jsdelivr.net/npm/netlistsvg@1.0.2/built/netlistsvg.bundle.js');

            log(`Invoking Yosys on module: ${testDef.top}…`);
            
            const yosysScript = [
                'read_verilog -sv input.v',
                `prep -top ${testDef.top}`,
                'write_json rtl.json',
                'write_cxxrtl sim.cpp',
                `synth -top ${testDef.top}`,
                'write_json synth.json'
            ].join('; ');
            
            const filesOut = await runYosys(
                ['-p', yosysScript],
                { 'input.v': verilog },
                { stdout: b => b && log(toStr(b).trimEnd()), stderr: b => b && log(toStr(b).trimEnd()) }
            );
            
            window.filesOutCache = filesOut;
            
            if (filesOut['sim.cpp']) {
                log('CXXRTL model generated successfully.', 'log-ok');
                document.getElementById('visuals').classList.remove('hidden');
                
                function getJson(name) {
                    const raw = filesOut[name];
                    if (!raw) throw new Error(`Missing ${name}`);
                    return fixYosysJson(JSON.parse(toStr(raw)));
                }
                
                await renderSchematic('rtlSchematic', getJson('rtl.json'));
                await renderSchematic('synthSchematic', getJson('synth.json'));
                
                await compileToWasm(testDef);
            } else {
                throw new Error("sim.cpp was not generated.");
            }
        } catch (err) {
            log('[CRITICAL ERROR] ' + err.message, 'log-err');
        } finally {
            document.getElementById('runBtn').disabled = false;
        }
    }

    /* ── WASM COMPILATION ── */
    async function compileToWasm(testDef) {
        if (!window.filesOutCache?.['sim.cpp']) return;
        
        document.getElementById('statusPanel').classList.remove('hidden');
        document.getElementById('wasmStatus').textContent = 'Compiling via Clang...';
        
        try {
            // Fetch header from jsDelivr 
            const headerContent = await fetchCxxrtlHeader();

            const files = {
                'driver.cpp': testDef.driver,
                'sim.cpp': toStr(window.filesOutCache['sim.cpp']),
                'cxxrtl': { 'cxxrtl.h': headerContent }
            };

            const clangArgs = [
                'clang++', '-std=c++17', '-O3', '-I/', '--target=wasm32',
                '-nostdlib', '-nostdinc', '-fno-exceptions', '-ferror-limit=0', '-fno-rtti', '-Wno-new-returns-null',
                '-Wl,--no-entry', '-Wl,--allow-undefined', 'driver.cpp', '-o', 'sim.wasm'
            ];

            let clangErr = '';
            const result = await runClang(clangArgs, files, {
                stdout: b => {}, // suppress clang stdout to keep log clean
                stderr: b => { 
                    if(b) { 
                        let str = dec.decode(b, {stream:true});
                        clangErr += str; 
                        const lines = clangErr.split('\n');
                        clangErr = lines.pop(); 
                        for(const l of lines) log(l, 'log-warn'); 
                    } 
                }
            });
            if(clangErr) log(clangErr, 'log-warn');

            const wasmBin = result['sim.wasm'];
            if (!wasmBin || wasmBin.byteLength === 0) throw new Error("Clang failed to produce sim.wasm");
            
            document.getElementById('wasmStatus').innerHTML = `Wasm Simulator Ready (${wasmBin.byteLength} bytes)`;
            
            const dummyEnv = new Proxy({}, { get: () => () => 0 });
            const { instance } = await WebAssembly.instantiate(wasmBin, { env: dummyEnv, wbindgen_placeholder: dummyEnv });
            wasmInstance = instance.exports;
            
            // Power on reset
            wasmInstance.init();

            // Show appropriate UI
            document.getElementById(`ui-${testSelector.value}`).classList.remove('hidden');
            
            // Bind the UI
            bindActiveUI(testSelector.value);

        } catch (err) {
            document.getElementById('wasmStatus').textContent = 'Failed.';
            log('[Clang error] ' + err.message, 'log-err');
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // DYNAMIC UI BINDINGS
    // ─────────────────────────────────────────────────────────────────────
    function bindActiveUI(testId) {
        if (!wasmInstance) return;

        if (testId === 'wide') {
            const uiWideIn = document.getElementById('uiWideIn');
            const uiWideShift = document.getElementById('uiWideShift');
            const uiWideOut = document.getElementById('uiWideOut');

            const applyWide = () => {
                let hexStr = uiWideIn.value.padStart(64, '0');
                for(let i=0; i<8; i++) {
                    let chunkHex = hexStr.substr(56 - i*8, 8);
                    wasmInstance.set_data_in(i, parseInt(chunkHex, 16) || 0);
                }
                wasmInstance.set_shift(parseInt(uiWideShift.value) || 0);
                wasmInstance.tick();

                let res = "";
                for(let i=7; i>=0; i--) {
                    res += (wasmInstance.get_data_out(i) >>> 0).toString(16).padStart(8, '0');
                }
                uiWideOut.textContent = res.toUpperCase();
            };

            document.getElementById('tickWideBtn').onclick = applyWide;
            document.getElementById('rstWideBtn').onclick = () => {
                wasmInstance.set_rst(0); wasmInstance.tick();
                wasmInstance.set_rst(1); applyWide();
            };
            applyWide();
        } 
        
        else if (testId === 'ram') {
            const applyRam = () => {
                wasmInstance.set_a(
                    parseInt(document.getElementById('uiRamAddrA').value) || 0,
                    parseInt(document.getElementById('uiRamDinA').value) || 0,
                    parseInt(document.getElementById('uiRamWeA').value) || 0
                );
                wasmInstance.set_b(
                    parseInt(document.getElementById('uiRamAddrB').value) || 0,
                    parseInt(document.getElementById('uiRamDinB').value) || 0,
                    parseInt(document.getElementById('uiRamWeB').value) || 0
                );
                wasmInstance.tick();
                document.getElementById('uiRamOutA').textContent = wasmInstance.get_out_a();
                document.getElementById('uiRamOutB').textContent = wasmInstance.get_out_b();
            };
            document.getElementById('tickRamBtn').onclick = applyRam;
            applyRam();
        }

        else if (testId === 'dsp') {
            const uiA = document.getElementById('uiDspA');
            const uiB = document.getElementById('uiDspB');
            const uiOut = document.getElementById('uiDspOut');

            const applyDsp = () => {
                wasmInstance.set_ab(parseInt(uiA.value) || 0, parseInt(uiB.value) || 0);
                wasmInstance.tick();
                
                let low = wasmInstance.get_mac_l() >>> 0;
                let high = wasmInstance.get_mac_h() >>> 0;
                
                let bigRes = (BigInt(high) << 32n) | BigInt(low);
                if (high & 0x80000000) {
                    bigRes = bigRes - (1n << 64n);
                }
                uiOut.textContent = bigRes.toString();
            };

            document.getElementById('tickDspBtn').onclick = applyDsp;
            applyDsp();
        }
    }
    
    document.getElementById('runBtn').addEventListener('click', doFullPipeline);
</script>
</body>
</html>

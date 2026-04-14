<!DOCTYPE html>

<html lang="en">

<head>

    <meta charset="UTF-8">

    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>In-Browser Verilog Synthesis (JSFiddle Fixed)</title>

    <style>

        body { font-family: system-ui, sans-serif; background: #1e1e1e; color: #d4d4d4; padding: 20px; margin: 0; }

        pre { background: #2d2d2d; padding: 15px; border-radius: 8px; overflow-x: auto; color: #9cdcfe; white-space: pre-wrap; }

        h2 { color: #569cd6; }

        button { padding: 12px 24px; font-size: 1.1rem; background: #569cd6; color: #1e1e1e; border: none; border-radius: 6px; cursor: pointer; }

        button:hover { background: #9cdcfe; }

    </style>

</head>

<body>

    <h2>Yosys WebAssembly Logic Synthesis</h2>

    <p>Full client-side Yosys — no server, no worker needed.</p>

    <button id="runBtn">▶ Run Synthesis</button>

    <pre id="output">Click "Run Synthesis" to start...</pre>



    <script type="module">

        import { runYosys } from 'https://cdn.jsdelivr.net/npm/@yowasp/yosys/gen/bundle.js';



        const verilogCode = `

module my_and_gate (

    input a,

    input b,

    output y

);

    assign y = a & b;

endmodule

        `;



        async function doSynthesis() {

            const outputEl = document.getElementById('output');

            outputEl.textContent = 'Downloading WASM (~50 MB, cached after first run) and synthesizing...';



            let stdoutText = "";

            let stderrText = "";

            const decoder = new TextDecoder();



            try {

                // The YoWASP API: runYosys(args, filesIn, options)

                const filesOut = await runYosys(

                    ['-p', 'read_verilog input.v; synth -top my_and_gate; write_verilog -noattr output.v'],

                    { 'input.v': verilogCode },

                    {

                        // Capture standard output streams via callbacks

                        stdout: bytes => { if (bytes) stdoutText += decoder.decode(bytes, { stream: true }); },

                        stderr: bytes => { if (bytes) stderrText += decoder.decode(bytes, { stream: true }); }

                    }

                );



                if (filesOut['output.v']) {

                    const outData = filesOut['output.v'];

                    // Safely handle the file output whether YoWASP returns a Uint8Array or a string

                    const netlist = typeof outData === 'string' ? outData : decoder.decode(outData);

                    

                    outputEl.textContent =

                        "// --- VERILOG INPUT ---\n" + verilogCode.trim() +

                        "\n\n// --- SYNTHESIZED NETLIST ---\n" + netlist.trim() +

                        "\n\n// --- STDOUT ---\n" + stdoutText.trim();

                } else {

                    outputEl.textContent = "No output file generated.\n\n// --- LOG ---\n" + stderrText.trim();

                }

            } catch (err) {

                outputEl.textContent = "Error: " + err.message;

            }

        }



        // Attach button from inside the module

        document.getElementById('runBtn').addEventListener('click', doSynthesis);

    </script>

</body>

</html>

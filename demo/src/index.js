/**
 * index.js — Main thread entry point for the WebWamrc demo.
 *
 * Spawns the worker, wires up the UI, and forwards file compile requests.
 */

// Only the ARM backend is compiled into wamrc.wasm, so only ARM/Thumb2 targets
// are available.  Cortex-M7 (thumbv7em) is the primary use-case.
const TARGETS = [
    { value: "thumbv7em",  label: "Cortex-M7 / thumbv7em (default)",  cpu: "cortex-m7"  },
    { value: "thumbv7em",  label: "Cortex-M4 / thumbv7em",             cpu: "cortex-m4"  },
    { value: "thumbv7m",   label: "Cortex-M3 / thumbv7m",              cpu: "cortex-m3"  },
    { value: "thumbv6m",   label: "Cortex-M0+ / thumbv6m",             cpu: "cortex-m0+" },
    { value: "armv7",      label: "Cortex-A (ARM 32-bit)",             cpu: null         },
];

// ----- DOM refs -----
const fileInput     = document.getElementById("wasm-input");
const targetSelect  = document.getElementById("target-select");
const compileBtn    = document.getElementById("compile-btn");
const downloadBtn   = document.getElementById("download-btn");
const statusEl      = document.getElementById("status");
const logEl         = document.getElementById("log");

// ----- Populate target select -----
TARGETS.forEach(({ value, label, cpu }, i) => {
    const opt = document.createElement("option");
    opt.value = value;
    opt.dataset.cpu = cpu ?? "";
    opt.textContent = label;
    if (i === 0) opt.selected = true;
    targetSelect.appendChild(opt);
});

// ----- Worker setup -----
const worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });

let pendingResolvers = {};
let nextResponseId = 1;

function sendToWorker(msg, transfer = []) {
    return new Promise((resolve, reject) => {
        const responseId = nextResponseId++;
        pendingResolvers[responseId] = { resolve, reject };
        worker.postMessage({ ...msg, responseId }, transfer);
    });
}

worker.onmessage = (event) => {
    const { id, responseId, message, aotBytes } = event.data;

    if (id === "progress") {
        appendLog(message);
        return;
    }

    const handlers = pendingResolvers[responseId];
    if (!handlers) {
        if (id === "ready") {
            setStatus("wamrc ready ✓", "success");
            compileBtn.disabled = false;
        } else if (id === "error") {
            setStatus("Initialisation error: " + message, "error");
            appendLog("ERROR: " + message);
        }
        return;
    }

    delete pendingResolvers[responseId];
    if (id === "result") {
        handlers.resolve(aotBytes);
    } else {
        handlers.reject(new Error(message));
    }
};

// ----- Init -----
setStatus("Loading wamrc…", "info");
appendLog("Initialising wamrc WebAssembly module…");
worker.postMessage({ id: "init" });

// ----- Compile button -----
let lastAotBytes = null;

compileBtn.addEventListener("click", async () => {
    const file = fileInput.files[0];
    if (!file) {
        setStatus("Please select a .wasm file first.", "error");
        return;
    }

    const target = targetSelect.value;
    setStatus("Compiling…", "info");
    appendLog(`\nCompiling ${file.name} → ${target} AOT…`);
    compileBtn.disabled = true;
    downloadBtn.disabled = true;
    lastAotBytes = null;

    try {
        const selectedOpt = targetSelect.selectedOptions[0];
        const cpu = selectedOpt?.dataset.cpu || null;
        // Always pass --size-level=3 for bare-metal; add --cpu= when known
        const extraArgs = [
            "--size-level=3",
            "--enable-builtin-intrinsics=i64.common,fp.common",
            ...(cpu ? [`--cpu=${cpu}`] : []),
        ];
        const wasmBytes = await file.arrayBuffer();
        const aotBytes  = await sendToWorker(
            { id: "compile", wasmBytes, target, extraArgs },
            [wasmBytes]
        );

        lastAotBytes = aotBytes;
        const kb = (aotBytes.byteLength / 1024).toFixed(1);
        setStatus(`Compiled successfully — ${kb} KB`, "success");
        appendLog(`Done. Output size: ${kb} KB`);
        downloadBtn.disabled = false;
    } catch (e) {
        setStatus("Compilation failed: " + e.message, "error");
        appendLog("ERROR: " + e.message);
    } finally {
        compileBtn.disabled = false;
    }
});

// ----- Download button -----
downloadBtn.addEventListener("click", () => {
    if (!lastAotBytes) return;
    const blob = new Blob([lastAotBytes], { type: "application/octet-stream" });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement("a");
    const stem = (fileInput.files[0]?.name ?? "output").replace(/\.wasm$/, "");
    a.href     = url;
    a.download = `${stem}.aot`;
    a.click();
    URL.revokeObjectURL(url);
});

// ----- Helpers -----
function setStatus(msg, type = "info") {
    statusEl.textContent = msg;
    statusEl.className   = `status status--${type}`;
}

function appendLog(msg) {
    logEl.textContent += msg + "\n";
    logEl.scrollTop    = logEl.scrollHeight;
}

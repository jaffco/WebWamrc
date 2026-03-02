/**
 * worker.js — Web Worker for WebWamrc.
 *
 * Loads the wamrc WebAssembly binary inside a Worker so the compilation never
 * blocks the main thread.  Communicates via postMessage.
 *
 * Protocol
 * --------
 * Main → Worker:
 *   { id: 'init' }
 *     Initialise the wamrc module.  Replies with { id: 'ready' } or
 *     { id: 'error', message }.
 *
 *   { id: 'compile', responseId: <any>, wasmBytes: ArrayBuffer, target: string,
 *     extraArgs?: string[] }
 *     Compile wasmBytes → .aot for the given target.  Replies with
 *     { id: 'result', responseId, aotBytes: ArrayBuffer } (transferable) or
 *     { id: 'error', responseId, message: string }.
 *
 * Worker → Main:
 *   { id: 'ready' }
 *   { id: 'result', responseId, aotBytes: ArrayBuffer }
 *   { id: 'progress', message: string }
 *   { id: 'error', [responseId], message: string }
 */

import WamrcProcess from "./WamrcProcess.mjs";

let wamrc = null;

self.onmessage = async (event) => {
    const { id, responseId } = event.data;

    switch (id) {
    case "init": {
        try {
            self.postMessage({ id: "progress", message: "Loading wamrc…" });
            wamrc = await new WamrcProcess({
                onprint:    (msg) => self.postMessage({ id: "progress", message: msg }),
                onprintErr: (msg) => self.postMessage({ id: "progress", message: msg }),
            });
            self.postMessage({ id: "ready" });
        } catch (e) {
            self.postMessage({ id: "error", message: String(e) });
        }
        break;
    }

    case "compile": {
        const { wasmBytes, target = "thumbv7em", extraArgs = [] } = event.data;
        try {
            if (!wamrc) throw new Error("wamrc not initialised — send 'init' first");

            self.postMessage({ id: "progress", message: `Compiling for target: ${target}…` });
            const aotBytes = await wamrc.compile(wasmBytes, target, extraArgs);

            self.postMessage(
                { id: "result", responseId, aotBytes },
                [aotBytes]            // transfer ownership — avoids a copy
            );
        } catch (e) {
            self.postMessage({ id: "error", responseId, message: String(e) });
        }
        break;
    }

    default:
        self.postMessage({ id: "error", message: `Unknown message id: ${id}` });
    }
};

import EmProcess from "./EmProcess.mjs";
import WamrcModule from "../wamrc/wamrc.mjs";

/**
 * WamrcProcess wraps the wamrc WebAssembly binary.
 *
 * It inherits EmProcess's HEAPU8 snapshot/restore so that wamrc can be
 * called multiple times in the same Wasm instance without LLVM global-state
 * corruption.
 */
export default class WamrcProcess extends EmProcess {
    constructor(opts = {}) {
        super(WamrcModule, opts);
    }

    /**
     * Compile a WebAssembly module to native AOT code.
     *
     * @param {Uint8Array|ArrayBuffer} wasmBytes  Input .wasm binary
     * @param {string}  target     wamrc target string (default: "thumbv7em" for Cortex-M7)
     * @param {string[]} extraArgs Additional wamrc CLI flags (optional)
     * @returns {Promise<ArrayBuffer>}  The compiled .aot bytes
     */
    async compile(wasmBytes, target = "thumbv7em", extraArgs = []) {
        const input = new Uint8Array(
            wasmBytes instanceof ArrayBuffer ? wasmBytes : wasmBytes.buffer
        );

        this.FS.writeFile("/tmp/input.wasm", input);

        const args = [
            "wamrc",
            `--target=${target}`,
            "-o", "/tmp/output.aot",
            ...extraArgs,
            "/tmp/input.wasm",
        ];

        const result = this.exec(args);

        // Always clean up input, even on error
        try { this.FS.unlink("/tmp/input.wasm"); } catch (_) {}

        if (result.returncode !== 0) {
            let msg = result.stderr || result.stdout || "(no output)";
            throw new Error(`wamrc failed (exit ${result.returncode}):\n${msg}`);
        }

        const aotBytes = this.FS.readFile("/tmp/output.aot");
        try { this.FS.unlink("/tmp/output.aot"); } catch (_) {}

        // Return a copy as a detachable ArrayBuffer
        return aotBytes.slice().buffer;
    }
}

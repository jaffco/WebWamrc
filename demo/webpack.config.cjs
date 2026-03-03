/**
 * webpack.config.cjs
 *
 * Bundles the WebWamrc demo.
 *
 * The wamrc Wasm binary produced by the build step must be placed at:
 *   demo/wamrc/wamrc.mjs
 *   demo/wamrc/wamrc.wasm
 *
 * The build scripts write them to build/wamrc/; you can symlink or copy:
 *   ln -sfn ../build/wamrc demo/wamrc
 */

const path              = require("path");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const CopyPlugin        = require("copy-webpack-plugin");

const SRC  = path.resolve(__dirname, "src");
const DIST = path.resolve(__dirname, "dist");
// The wamrc Emscripten outputs (wamrc.mjs + wamrc.wasm)
const WAMRC_DIR = path.resolve(__dirname, "wamrc");

module.exports = {
    mode: "production",

    entry: path.join(SRC, "index.js"),

    output: {
        path: DIST,
        filename: "bundle.js",
        clean: true,
    },

    resolve: {
        extensions: [".mjs", ".js"],
    },

    module: {
        rules: [
            // Treat .wasm files referenced via import() as separate assets so
            // that Emscripten can load them by URL at runtime.
            {
                test: /\.wasm$/,
                type: "asset/resource",
                generator: { filename: "[name][ext]" },
            },
            // Emscripten-generated .mjs glue code should not be transpiled.
            {
                test: /\.mjs$/,
                type: "javascript/esm",
                resolve: { fullySpecified: false },
            },
        ],
    },

    plugins: [
        new HtmlWebpackPlugin({
            template: path.join(SRC, "index.html"),
            filename: "index.html",
            // bundle.js is already referenced in the template; suppress the
            // automatic injection so we don't duplicate the script tag.
            inject: false,
        }),

        // Copy only the two runtime files that the browser needs.
        // Webpack's own bundler would mangle Emscripten's glue code, so we
        // copy wamrc.mjs verbatim and let the browser load it natively.
        // Listing files explicitly prevents cmake build artifacts (.a, .ninja, …)
        // from ending up in dist/.
        new CopyPlugin({
            patterns: [
                {
                    from: path.join(WAMRC_DIR, "wamrc.mjs"),
                    to: path.join(DIST, "wamrc", "wamrc.mjs"),
                    noErrorOnMissing: true,
                },
                {
                    from: path.join(WAMRC_DIR, "wamrc.wasm"),
                    to: path.join(DIST, "wamrc", "wamrc.wasm"),
                    noErrorOnMissing: true,
                },
            ],
        }),
    ],

    // Web Workers are first-class in Webpack 5 via the Worker(new URL(…)) syntax.
    // No extra configuration needed; the worker entry (worker.js) is discovered
    // automatically via the import in index.js.

    devServer: {
        static: DIST,
        port: 8080,
        hot: false,
        headers: {
            // Required for SharedArrayBuffer + Atomics used by some Emscripten builds.
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Embedder-Policy": "require-corp",
        },
    },
};

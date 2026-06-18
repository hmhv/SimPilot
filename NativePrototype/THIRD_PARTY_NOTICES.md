# Third-Party Notices

## serve-sim

This prototype was informed by inspecting `serve-sim` while building a native Simulator bridge.

- Repository: https://github.com/EvanBacon/serve-sim
- License: Apache License 2.0
- Inspected package: `serve-sim@0.1.41` (from the npm/npx cache)

### Scope of use — important

The shipped npm package does **not** include the source of its core helper (`bin/serve-sim-bin`); only
the compiled Mach-O binary is distributed. The only native *sources* in the package are unrelated to the
core engine (`Sources/SimCameraInjector/*.m`, `Sources/SimAXSettings/*.m`).

Because that source is not available, this prototype does **not** copy or adapt serve-sim source code.
The native bridge under `Sources/SimBridge/` is an **independent reimplementation** that calls the same
Apple **private** frameworks (CoreSimulator, SimulatorKit, AccessibilityPlatformTranslation) directly.
What was learned from serve-sim is limited to *which* private symbols are relevant and *how the pieces
fit together* (facts about Apple's APIs, observed via the binary's strings/symbols and standard runtime
introspection) — not serve-sim's own code.

If, in the future, any source **is** copied or adapted from serve-sim (e.g. from its GitHub repository),
that file must preserve Apache-2.0 attribution and keep a file-level comment identifying the original
source and the local changes.

### Apple private frameworks

This prototype depends on Apple private frameworks that ship with Xcode/macOS. They are loaded at runtime
via `dlopen` and are not redistributed here. This approach is for local development and experimentation
only and is not suitable for App Store distribution.

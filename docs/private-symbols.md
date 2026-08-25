# Private symbols map (churn-mitigation)

`sipi` drives Apple's Simulator through three **private** frameworks that ship
with Xcode / macOS. None is linked at build time; all are loaded at runtime via
`dlopen`, and every undocumented class / selector / C symbol / magic constant is
confined to a single Objective-C target, `Sources/SimBridge/SimBridge.m`. This
is the only Apple-version churn surface `sipi` carries: a new Xcode that renames
or moves any of these symbols breaks `sipi`.

This document is the authoritative inventory of that surface. For every symbol it
records **what it does**, **where it is used**, and the **doctor guard** — the
`respondsToSelector` / `NSClassFromString` / `dlsym` check that turns a churned
symbol into an actionable error instead of a crash, and (where applicable) the
corresponding `sipi doctor` check that flags it ahead of time. Keep this table in
sync when `SimBridge.m` changes.

Call sites are named by **symbol**, not by line number: `+method:` / `-method:`
for Objective-C, `Name()` for C statics, `@interface Name` for a declaration.
Line numbers were tried first and rotted within a few commits — grep the symbol
instead. `NSError` code numbers are quoted because they are stable identifiers in
their own right, greppable in `SimBridge.m`. Files referenced:
`Sources/SimBridge/SimBridge.m`, `Sources/SimBridge/include/SimBridge.h`, and
`Sources/sipi/Doctor.swift` (all four `sipi doctor` checks live in its
`DoctorReport.probe()`).

---

## 1. Framework load paths (dlopen)

These absolute paths are the load surface. CoreSimulator lives under
`/Library/Developer/PrivateFrameworks`; SimulatorKit lives **inside the active
Xcode**, but which subdirectory depends on the release (see below); APT lives
only in the **dyld shared cache** (there is no linkable on-disk binary — it must
be `dlopen`d by its shared-cache path).

| Path constant | Framework | Where used | Doctor guard |
|---|---|---|---|
| `kCoreSimulatorPath` = `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator` | CoreSimulator | file-scope constant under `#pragma mark - Private framework paths`; loaded by `+loadCoreSimulator:`, `-[SPHIDInjector setupForUDID:developerDir:error:]`, and `-[SPFrameCapture wireUpForUDID:developerDir:error:]` | `SPDlopen()` returns NO + `NSError` on failure; `sipi doctor` "CoreSimulator" check in `DoctorReport.probe()`. |
| SimulatorKit — path resolved by `+simulatorKitPathForDeveloperDir:` | SimulatorKit | **Two candidates, in order:** `<Xcode>.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit` (Xcode 27+, where the framework actually lives) then `developerDir + Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit` (Xcode 26 and earlier). The first existing file wins; if neither exists the classic path is returned so the error names it. Loaded in `+uiOrientationForUDID:…`, `+hidSymbolStatusForDeveloperDir:`, and `-[SPHIDInjector setupForUDID:developerDir:error:]` | `SPDlopen` NO + `NSError`; `sipi doctor` "SimulatorKit" check tests `FileManager` existence + `dlopen` + the HID client class, in `DoctorReport.probe()`. |
| `kAccessibilityPlatformTranslationPath` = `/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation` | AccessibilityPlatformTranslation (APT) | file-scope constant under the same `#pragma mark`; loaded by `+loadAccessibilityPlatformTranslation:` and `-[SPAccessibilityBridge ensureLoaded:]` | `SPDlopen` NO + `NSError`; `sipi doctor` "AccessibilityPlatformTranslation" check via `+accessibilityBridgeStatus`. APT is shared-cache only, so the absolute-path `dlopen` is the explicit doctor check. |

---

## 2. CoreSimulator classes & selectors

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `SimServiceContext` | class | Root service context; `+sharedServiceContextForDeveloperDir:error:` and `-defaultDeviceSetWithError:` reach the device set. | `@interface SimServiceContext` (local decl); resolved via `NSClassFromString` in `SPCopySimDeviceForUDID()` and `+listDevicesForDeveloperDir:` | `NSClassFromString` nil check → `NSError`; `sipi doctor` asserts `NSClassFromString("SimServiceContext") != nil` in `DoctorReport.probe()`. |
| `SimDeviceSet` | class | `.devices` array of every simulator. | `@interface SimDeviceSet` (local decl); iterated in `SPCopySimDeviceForUDID()` and `+listDevicesForDeveloperDir:` | covered by the device enumeration path; failure yields `NSError` code 4. |
| `SimDevice` | class | A single simulator: `UDID`, `name`, `state`, `stateString`, `deviceType`, `runtime`. | `@interface SimDevice` (local decl) | `sipi doctor` asserts `NSClassFromString("SimDevice") != nil` in `DoctorReport.probe()`. |
| `SimDevice.state` (`NSUInteger`) + magic value `3` | property + constant | `SimDeviceState.Booted == 3`. `-[SPSimDevice isBooted]` compares `state == 3`. The property is declared `NSUInteger` deliberately to match the real 8-byte enum width (a narrower type would be a return-type ABI mismatch). | `state` in `@interface SimDevice`; compared in `-[SPSimDevice isBooted]` | none direct; wrong width is UB, so the declaration is the guard. Booted-state surfaced in `sipi doctor` "booted devices". |
| `SimDevice -sendAccessibilityRequestAsync:completionQueue:completionHandler:` | selector | Device-side transport: forwards each APT translator request to the booted device and returns the AX response. The spine of the whole describe-ui path. | selector string in `+probeAccessibilityBridgeTokenProto:…`, `+hidSymbolStatusForDeveloperDir:`, `-[SPAccessibilityBridge treeForUDID:…]`, `-[SPAccessibilityBridge setValue:…]`; invoked via `objc_msgSend` in `-[SPAccessibilityBridge runRequest:onDevice:]` | `respondsToSelector` check → `NSError` code 23 (in `treeForUDID:` and `setValue:…`); `sipi doctor` "AXPTranslator ready (… SimDevice transport ✓)" via `class_getInstanceMethod` in `+probeAccessibilityBridgeTokenProto:…`. |
| `SimDevice -io` | selector | Returns the device IO client (framebuffer descriptors live under it). | `SPPerformNoArg(device, @"io")` in `-[SPFrameCapture wireUpForUDID:developerDir:error:]` | `SPPerformNoArg()` is `respondsToSelector`-guarded; nil result → `NSError` code 40. |
| `SimDevice -setHardwareKeyboardEnabled:keyboardType:error:` | selector | Puts the guest into hardware-keyboard mode (dismisses the on-screen software keyboard and composes HID modifiers across key events). The same private API the Simulator app's "I/O ▸ Keyboard ▸ Connect Hardware Keyboard" menu drives. **Required for chords:** without it the software keyboard drops held modifiers, so Cmd+V types a literal `v` and Shift+a types lowercase `a` (FIX-A). Called the first time a modifier usage is sent. | selector string + invoke in `-[SPHIDInjector ensureHardwareKeyboardEnabled]`; gated by `-[SPHIDInjector sendKeyUsage:down:]` on `SPIsModifierUsage()` | `respondsToSelector`-guarded and best-effort: if absent or failing, plain typing still works and chords degrade to the prior (modifier-dropping) behaviour rather than crashing. |

---

## 3. SimulatorKit classes, selectors & Indigo HID C symbols

### 3.1 HID client (mangled Swift class name)

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `_TtC12SimulatorKit24SimDeviceLegacyHIDClient` | class (mangled) | The Swift `SimulatorKit.SimDeviceLegacyHIDClient` class. Created via `-initWithDevice:error:`; receives all Indigo HID messages. The mangled name is brittle: a SimulatorKit rename (or a recount of the `12`/`24` length prefixes) breaks it. | mangled string in `-[SPHIDInjector setupForUDID:developerDir:error:]`; same string again in `Doctor.swift` | `NSClassFromString` nil check → `NSError` code 31; `sipi doctor` "SimulatorKit … HID client" asserts the class resolves in `DoctorReport.probe()`. |
| `-initWithDevice:error:` | selector | Initializes the HID client against a `SimDevice`. | selector string and `objc_msgSend` send, both in `-[SPHIDInjector setupForUDID:developerDir:error:]` | `client == nil \|\| initError != nil` → `NSError` code 32. |
| `-sendWithMessage:freeWhenDone:completionQueue:completion:` | selector | Submits an Indigo message; `freeWhenDone:YES` transfers ownership so the client frees the message buffer. | selector cached into `_sendSel` in `-[SPHIDInjector setupForUDID:developerDir:error:]`; sent in `-[SPHIDInjector sendMessage:]` | cached `_sendSel` is nil-checked before send; on nil it frees the message instead of sending. |
| `SimulatorKit.SimDeviceScreen` | class | Orientation READ: `-initWithDevice:screenID:` → `-screen` → `-screenProperties` → `-uiOrientation`. | `NSClassFromString(@"SimulatorKit.SimDeviceScreen")` in `+uiOrientationForUDID:…` | `NSClassFromString` nil check → `NSError` code 50; each chained selector separately guarded (codes 51-56). |
| `-initWithDevice:screenID:` + magic `screenID == 1` | selector + constant | Builds a `SimDeviceScreen` for the primary display (screen ID 1). | both the selector and the literal `screenID:1` in `+uiOrientationForUDID:…` | `instancesRespondToSelector` → `NSError` code 51; nil result → code 52. |
| `-screen`, `-screenProperties`, `-uiOrientation` | selectors | Walk to the orientation enum. `uiOrientation` returns a `UInt32` 1…4 (1 portrait, 2 portrait-upside-down, 3 landscape-left, 4 landscape-right). | all three in `+uiOrientationForUDID:…` | `SPPerformNoArg()` guards `-screen`/`-screenProperties` (codes 53, 54); `respondsToSelector` guards `-uiOrientation` (code 55); an out-of-range raw value → code 56. |

### 3.2 Indigo HID C functions (dlsym from SimulatorKit)

Resolved with `dlsym(RTLD_DEFAULT, …)` once SimulatorKit is loaded and cached as
function pointers on `SPHIDInjector` in `-setupForUDID:developerDir:error:`.
`+hidSymbolStatusForDeveloperDir:` resolves the same four independently, for
`sipi doctor`.

| Symbol | What it does | Where used | Doctor guard |
|---|---|---|---|
| `IndigoHIDMessageForMouseNSEvent` | Builds a touch / mouse Indigo message: `fn(&pt, pt2, flags, phase, 1.0, 1.0, edge)`. Single-point taps/swipes pass `pt2 = NULL`; multi-touch passes a second point. | `dlsym` in `-[SPHIDInjector setupForUDID:developerDir:error:]`; called in `-sendTouchPhase:x:y:edge:` and `-sendMultiTouchPhase:x1:y1:x2:y2:` | required: `_mouseFunc == NULL` → `NSError` code 30 at setup; every send re-checks `_mouseFunc == NULL`. |
| `IndigoHIDMessageForButton` | Builds a hardware-button Indigo message: `fn(source, direction, 0x33)`. | `dlsym` in `-setupForUDID:developerDir:error:`; called in `-[SPHIDInjector sendHIDButtonSource:direction:]` | optional: `_buttonFunc == NULL` early-returns; a missing button symbol degrades buttons but does not crash. |
| `IndigoHIDMessageForKeyboardArbitrary` | Builds a keyboard Indigo message: `fn(usage, isDown)` where `isDown` is `1` (down) / `2` (up). | `dlsym` in `-setupForUDID:developerDir:error:`; called in `-[SPHIDInjector sendKeyUsage:down:]` | optional: `_keyboardFunc == NULL` early-returns. |
| `IndigoHIDMessageForDigitalCrownEvent` | Builds a Digital Crown rotation Indigo message: `fn(delta)` (Apple Watch simulators only). | `dlsym` in `-setupForUDID:developerDir:error:`; called in `-[SPHIDInjector sendDigitalCrown:]` | optional: `_crownFunc == NULL` (or `NaN` delta) early-returns. |

### 3.3 Magic HID constants

These integers are baked into the Indigo wire format; they were recovered by
disassembly of the reference binary and have no symbolic name. A change in the
Indigo protocol would silently mis-encode events (no crash, wrong behavior), so
they are documented here rather than guarded at runtime.

| Constant | Meaning | Where used |
|---|---|---|
| `50` | Mouse/touch event "type" for a single-finger touch in `IndigoHIDMessageForMouseNSEvent`. | `-[SPHIDInjector sendTouchPhase:x:y:edge:]` (`_mouseFunc(&point, NULL, 50, phase, …)`) |
| `0x32` (50) | Mouse/touch flags for a **two-finger** (multi-touch) event — one message carries both points. | `-[SPHIDInjector sendMultiTouchPhase:x1:y1:x2:y2:]` (`_mouseFunc(&p1, &p2, 0x32, phase, …)`) |
| `0x33` (51) | Third argument to `IndigoHIDMessageForButton` (button page/usage selector). | `-[SPHIDInjector sendHIDButtonSource:direction:]` |
| touch `phase` 1 / 2 | `1` = begin/move, `2` = end. A tap is `1` then `2`; a swipe is `1` … (interpolated moves) … `2`. | `-[SPHIDInjector tapAbsoluteX:y:]`, `-[SPHIDInjector swipeHome]`, and every caller of `sendTouchPhase:`/`sendMultiTouchPhase:` (including `-[SPMirrorView sendTouchPhase:forEvent:]`) |
| key direction 1 / 2 | `1` = key down, `2` = key up. | `-[SPHIDInjector sendKeyUsage:down:]` (`_keyboardFunc(usage, down ? 1 : 2)`) |
| button direction 1 / 2 | `1` = press, `2` = release (the reference binary's follow-up code). | `-[SPHIDInjector pressButton:]` |
| button source codes `0`, `1`, `3`, `3000`, `0x400002` | Hardware-button source identifiers: `0` = Home, `1` = Lock, `3000` = side button, `0x400002` = Siri (press-and-hold). App Switcher = double Home; Swipe Home = bottom edge swipe. | `-[SPHIDInjector pressButton:]` |
| `edge` `0` / `3` | Touch edge flag: `0` = interior touch, `3` = bottom-edge swipe (used by swipe-home). | `-[SPHIDInjector sendTouchPhase:x:y:edge:]`, `-[SPHIDInjector swipeHome]` |

---

## 4. AccessibilityPlatformTranslation (APT) classes, selectors & KVC keys

The describe-ui tree is produced entirely through APT. The recipe (recovered by
runtime introspection of `AXPTranslator` and disassembly of the reference
binary) is documented inline in the comment block under
`#pragma mark - In-process accessibility bridge (AccessibilityPlatformTranslation)`.

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `AXPTranslator` | class | The translator singleton (`+sharedInstance`); the root of the AX path. | `NSClassFromString(@"AXPTranslator")` in `+probeAccessibilityBridgeTokenProto:…`, `+accessibilityBridgeStatus`, `+accessibilityBridgeReady`, `-[SPAccessibilityBridge ensureLoaded:]` | `NSClassFromString` nil check in each; `sipi doctor` reports `AXPTranslator ready` / `class missing` via `+accessibilityBridgeStatus`. |
| `+sharedInstance` | selector | Returns the translator singleton. | same call sites as `AXPTranslator` | `respondsToSelector` + nil-result checks → status string / `NSError` code 20-21 in `-ensureLoaded:`. |
| KVC keys `bridgeTokenDelegate`, `supportsDelegateTokens`, `accessibilityEnabled` | KVC properties | Configure the translator: set this bridge as the token delegate, enable delegate tokens, enable accessibility. The reference binary uses `setValue:forKey:`, not setters. | `-[SPAccessibilityBridge ensureLoaded:]` | implicit (KVC); the subsequent transport calls fail with `NSError` if the translator was not configured. |
| `bridgeDelegateToken` lifetime (stable per device) | behavioral contract | `AXPTranslator` caches the `AXPMacPlatformElement` it builds for the frontmost app and pins it to the token of the *first* fetch; that element's later AX requests still dispatch through that original token. So the bridge mints **one stable token per device** and never evicts it from `_tokenToDevice`, otherwise a second in-process fetch reuses the cached element against an evicted token and degenerates to an empty root. | `-[SPAccessibilityBridge stableTokenForDevice:udid:]` (`_udidToToken` / `_tokenToDevice`) | gated `SimNativeIntegrationTests` assert repeated in-process fetches each return `> 1` node. |
| `frontmostApplicationWithDisplayId:bridgeDelegateToken:` + magic `displayId == 0` | selector + constant | Returns the frontmost app's root `AXPTranslationObject` for display 0. | selector string and send in `-[SPAccessibilityBridge treeForUDID:…]`; presence also probed in `+hidSymbolStatusForDeveloperDir:` | nil result → `NSError` code 24. |
| `macPlatformElementFromTranslation:` | selector | Converts an `AXPTranslationObject` into an NSAccessibility-walkable `AXPMacPlatformElement`. | `-[SPAccessibilityBridge treeForUDID:…]`, `-discoverByGridForToken:…`, `-elementAtPoint:token:`, `-elementAtPointForUDID:…` | `respondsToSelector` check; nil result → `NSError` code 25. |
| `objectAtPoint:displayId:bridgeDelegateToken:` + magic `displayId == 0` | selector + constant | Single hit-test at a logical point; backs both the 16pt grid pass and `describe-point`. | `-[SPAccessibilityBridge discoverByGridForToken:…]` (grid) and `-elementAtPoint:token:` / `-elementAtPointForUDID:…` (`describe-point`) | `respondsToSelector` → grid pass quietly skips, or `NSError` code 26 for `describe-point`. |
| `AXPTranslatorResponse` + `+emptyResponse` | class + selector | The "no data" sentinel the bridge returns from a translator callback when the token has no device / the transport times out. | `-[SPAccessibilityBridge emptyResponse]`, used by `-accessibilityTranslationDelegateBridgeCallbackWithToken:` and `-runRequest:onDevice:` | `responseClass && respondsToSelector` guard; returns `nil` if unavailable. |
| `AXPTranslationTokenDelegateHelper` (protocol) | protocol | The delegate protocol whose callbacks (`accessibilityTranslationDelegateBridgeCallbackWithToken:` etc.) forward each translator request to the device transport. | conformance implemented in the `#pragma mark AXPTranslationTokenDelegateHelper` block of `SPAccessibilityBridge`; protocol existence probed in `+probeAccessibilityBridgeTokenProto:…` | `objc_getProtocol(...) != NULL` reported as `tokenDelegate proto ✓/✗` by `+accessibilityBridgeStatus`. |
| `AXPMacPlatformElement` | class | The NSAccessibility element type the tree walk serializes. | presence probed in `+probeAccessibilityBridgeTokenProto:…`; the walked type in `-[SPAccessibilityBridge treeForUDID:…]` | `NSClassFromString(...) != nil` reported as `macElement ✓/✗` by `+accessibilityBridgeStatus`. |
| NSAccessibility KVC keys (`accessibilityLabel`, `accessibilityValue`, `accessibilityRoleDescription`, `accessibilityRole`, `accessibilitySubrole`, `accessibilityIdentifier`, `accessibilityEnabled`, `accessibilityChildren`, `accessibilityFrame`) | KVC / selectors | Per-node serialization into the describe-ui shape. `accessibilityRole` is captured raw into `role`, then `AX`-stripped into `type`; `accessibilitySubrole` is emitted only when non-empty. | `-[SPAccessibilityBridge serializeElement:…]`; `accessibilityFrame` in `-[SPAccessibilityBridge frameOf:]` | each read goes through `SPAXString()` / `SPAXBool()`, which `@try/@catch` around `valueForKey:` and return a default on failure; `accessibilityFrame` is `respondsToSelector`-guarded. |
| `setAccessibilityValue:` (and the `accessibilityValue` KVC key as a WRITE) | selector / KVC | Text entry with no keyboard: `sipi set-text` / the `set-text` action hit-test the target, then write the element's value straight through the translated element. This is the only text path that works on a simulator that has stopped delivering keyboard HID (a device-age condition, not a runtime one). | `-[SPAccessibilityBridge setValue:atPoint:…]`, wrapper `+[SPSimBridge setAccessibilityValue:…]` | `respondsToSelector` for the setter, KVC as the fallback, both inside `@try/@catch`; nothing at the point → `NSError` code 28, neither write path usable → code 29. A write that the app ignores is caught one layer up: the caller re-reads the value in a FRESH process (an in-process read can echo the write back) and fails the command/step. |
| `registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:` / `unregisterScreenCallbacksWithUUID:` | selectors | Framebuffer mirror: register/unregister screen ping callbacks on a display descriptor. | `-[SPFrameCapture registerCallbacks]` / `-[SPFrameCapture unregisterCallbacks]` | `respondsToSelector` guards both. |
| `updateIOPorts`, `deviceIOPorts` (KVC), `portIdentifier`, `descriptor`, `framebufferSurface` + magic `"com.apple.framebuffer.display"` | selectors / KVC / constant | Resolve the framebuffer IOSurface: refresh IO ports, find the port whose `portIdentifier == "com.apple.framebuffer.display"`, take its `descriptor`, read `framebufferSurface`. | `-[SPFrameCapture wireUpForUDID:developerDir:error:]` (resolve) and `-[SPFrameCapture currentSurface]` | `updateIOPorts` / `portIdentifier` / `framebufferSurface` are `respondsToSelector` / `SPPerformNoArg()`-guarded; `deviceIOPorts` is `@try/@catch` + class check → `NSError` code 41; no descriptor → code 42. |

### Which display the framebuffer capture picks

A simulator vends more than one live framebuffer. Xcode 27 adds a 7680x4320
"Resizable" display (display class 1) alongside the device screen (class 0), and
its surface is live and permanently black — so the previous rule, "the live
IOSurface with the largest area", captured the blank display. Every visual
artifact on an iOS 27 run (screenshots, per-step harness images, verify
captures, the mirror view, `record-video`) came back black.

The display class is NOT readable in-process. The descriptor is a
`ROCKRemoteProxy` that answers neither `displayClass` nor KVC for it; its `state`
snapshot is a `ROCKImmutableProxy` whose values live in a `properties`
`NSMapTable` that **crashes the process** when read — `objectForKey:` traps
(SIGTRAP) and `dictionaryRepresentation` segfaults (SIGSEGV), both measured on
Xcode 27.0 beta 4. Do not reach into that map.

`SPBuiltInDisplaySizeForUDID()` therefore reads the built-in display's size from
`xcrun simctl io <udid> enumerate`, which prints each display's class and default
size, and `-[SPFrameCapture currentSurface]` selects the surface matching that
size. The subprocess result is cached per UDID for the life of the process, so a
harness run pays for it once rather than once per capture, and an unreadable
enumerate falls back to the old largest-area behavior rather than failing the
capture.

---

## 5. How the guards roll up into `sipi doctor`

`sipi doctor` (`Sources/sipi/Doctor.swift`, all of it inside
`DoctorReport.probe()`) is the per-Xcode early-warning system for this whole
surface. Its four core checks map directly onto the sections above:

- **CoreSimulator** — `+loadCoreSimulator:` dlopen + `SimServiceContext` /
  `SimDevice` class resolution (§1, §2).
- **SimulatorKit** — binary existence + `dlopen` + the mangled
  `_TtC12SimulatorKit24SimDeviceLegacyHIDClient` class (§1, §3.1).
- **IndigoHID** — `dlsym` of the four Indigo event builders (via
  `+hidSymbolStatusForDeveloperDir:`); only the mouse builder is required, the
  others are reported as warnings (§3).
- **AccessibilityPlatformTranslation** — `+accessibilityBridgeStatus` probes
  APT dlopen, `AXPTranslator`/`sharedInstance`, the token-delegate protocol, the
  Mac platform-element class, and the `SimDevice` transport selector (§1, §4).

A note (never the exit code) reports whether `xcrun devicectl` can target
simulators here, which gates the Xcode 27+ device-state surface. That surface is
public tooling, not a private symbol, so its absence is not a driver failure.

**What these checks do NOT cover:** they prove the symbols RESOLVE, not that the
events they build are DELIVERED. A runtime can accept every HID message and act
on none of it — measured on iOS 27.0, where the keyboard path is dead (and, in
one session, touch as well) while `doctor` reports every builder present. Symbol
resolution is a necessary, not sufficient, condition; the per-action effect
checks (`type`'s text-field comparison) are what catch the delivery failures.

If any core check fails, `sipi doctor` exits non-zero and `preflight` stops the
workflow (see `docs/sipi-doctor-contract.md`). The workflow in
`.github/workflows/sipi-doctor-matrix.yml` is a **DRAFT**: it is manual-only
(`workflow_dispatch`; the push/PR triggers are commented out) and carries a
single placeholder Xcode entry, so it does **not** run per-Xcode today. It is
*intended* to run `sipi doctor --json` against each supported Xcode — so a
private-symbol break would show up as a failed check naming the exact capability
rather than as a downstream crash — once a runner-fleet decision (which Xcodes,
which runners) is made. Treat it as aspirational, not an active churn gate.

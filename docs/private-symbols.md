# Private symbols map (churn-mitigation)

`sipi` drives Apple's Simulator through three **private** frameworks that ship
with Xcode / macOS. None is linked at build time; all are loaded at runtime via
`dlopen`, and every undocumented class / selector / C symbol / magic constant is
confined to a single Objective-C target, `Sources/SimBridge/SimBridge.m`. This
is the only Apple-version churn surface `sipi` carries: a new Xcode that renames
or moves any of these symbols breaks `sipi`.

This document is the authoritative inventory of that surface. For every symbol it
records **what it does**, **where it is used** (`file:line`), and the
**doctor guard** — the `respondsToSelector` / `NSClassFromString` / `dlsym`
check that turns a churned symbol into an actionable error instead of a crash,
and (where applicable) the corresponding `sipi doctor` check that flags it
ahead of time. Keep this table in sync when `SimBridge.m` changes.

Line numbers refer to `Sources/SimBridge/SimBridge.m` and
`Sources/SimBridge/include/SimBridge.h` at the time of writing; treat them as
approximate anchors, not exact addresses.

---

## 1. Framework load paths (dlopen)

These absolute paths are the load surface. CoreSimulator lives under
`/Library/Developer/PrivateFrameworks`; SimulatorKit lives **inside the active
Xcode** (so the path is derived from the developer dir); APT lives only in the
**dyld shared cache** (there is no linkable on-disk binary — it must be `dlopen`d
by its shared-cache path).

| Path constant | Framework | Where used | Doctor guard |
|---|---|---|---|
| `kCoreSimulatorPath` = `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator` | CoreSimulator | `SimBridge.m:16-17` (constant); loaded by `+loadCoreSimulator:` `SimBridge.m:160-173`, and in `SPHIDInjector -setupForUDID:` `SimBridge.m:935`, `SPFrameCapture -wireUpForUDID:` `SimBridge.m:1182` | `SPDlopen` returns NO + `NSError` on failure (`SimBridge.m:82-96`); `sipi doctor` "CoreSimulator" check (`Doctor.swift:104-122`). |
| `developerDir + Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit` | SimulatorKit | path built at `SimBridge.m:309-311`, `936-938`, `1183-1185`; loaded via `SPDlopen` in `+uiOrientationForUDID:`, `SPHIDInjector -setupForUDID:`, `SPFrameCapture -wireUpForUDID:` | `SPDlopen` NO + `NSError`; `sipi doctor` "SimulatorKit" check tests `FileManager` existence + `dlopen` + the HID client class (`Doctor.swift:124-138`). |
| `kAccessibilityPlatformTranslationPath` = `/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation` | AccessibilityPlatformTranslation (APT) | `SimBridge.m:18-20` (constant); loaded by `+loadAccessibilityPlatformTranslation:` `SimBridge.m:175-187` and `SPAccessibilityBridge -ensureLoaded:` `SimBridge.m:577` | `SPDlopen` NO + `NSError`; `sipi doctor` "AccessibilityPlatformTranslation" check via `+accessibilityBridgeStatus` (`Doctor.swift:140-147`). APT is shared-cache only, so the absolute-path `dlopen` is the explicit doctor check. |

---

## 2. CoreSimulator classes & selectors

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `SimServiceContext` | class | Root service context; `+sharedServiceContextForDeveloperDir:error:` and `-defaultDeviceSetWithError:` reach the device set. | `SimBridge.m:37-41` (decl); resolved via `NSClassFromString` in `SPCopySimDeviceForUDID` (`SimBridge.m:102-103`) and `+listDevicesForDeveloperDir:` (`SimBridge.m:381-394`) | `NSClassFromString` nil check → `NSError` (`SimBridge.m:382-390`); `sipi doctor` asserts `NSClassFromString("SimServiceContext") != nil` (`Doctor.swift:106`). |
| `SimDeviceSet` | class | `.devices` array of every simulator. | `SimBridge.m:43-45` (decl); iterated in `SPCopySimDeviceForUDID` and `+listDevicesForDeveloperDir:` | covered by the device enumeration path; failure yields `NSError` code 4 (`SimBridge.m:400-405`). |
| `SimDevice` | class | A single simulator: `UDID`, `name`, `state`, `stateString`, `deviceType`, `runtime`. | `SimBridge.m:58-67` (decl) | `sipi doctor` asserts `NSClassFromString("SimDevice") != nil` (`Doctor.swift:107`). |
| `SimDevice.state` (`NSUInteger`) + magic value `3` | property + constant | `SimDeviceState.Booted == 3`. `-[SPSimDevice isBooted]` compares `state == 3`. The property is declared `NSUInteger` deliberately to match the real 8-byte enum width (a narrower type would be a return-type ABI mismatch). | `SimBridge.m:63`, `SimBridge.m:72` | none direct; wrong width is UB, so the declaration is the guard. Booted-state surfaced in `sipi doctor` "booted devices" (`Doctor.swift:149-160`). |
| `SimDevice -sendAccessibilityRequestAsync:completionQueue:completionHandler:` | selector | Device-side transport: forwards each APT translator request to the booted device and returns the AX response. The spine of the whole describe-ui path. | selector string at `SimBridge.m:456`, `635`, `781`, `849`; invoked via `objc_msgSend` at `SimBridge.m:644` | `respondsToSelector` check → `NSError` code 23 (`SimBridge.m:782-786`, `850-854`); `sipi doctor` "AXPTranslator ready (… SimDevice transport ✓)" via `class_getInstanceMethod` (`SimBridge.m:451-465`). |
| `SimDevice -io` | selector | Returns the device IO client (framebuffer descriptors live under it). | `SimBridge.m:1190` (`SPPerformNoArg(device, @"io")`) | `SPPerformNoArg` is `respondsToSelector`-guarded (`SimBridge.m:1094-1098`); nil result → `NSError` code 40 (`SimBridge.m:1191-1195`). |
| `SimDevice -setHardwareKeyboardEnabled:keyboardType:error:` | selector | Puts the guest into hardware-keyboard mode (dismisses the on-screen software keyboard and composes HID modifiers across key events). The same private API the Simulator app's "I/O ▸ Keyboard ▸ Connect Hardware Keyboard" menu drives. **Required for chords:** without it the software keyboard drops held modifiers, so Cmd+V types a literal `v` and Shift+a types lowercase `a` (FIX-A). Called the first time a modifier usage is sent (`SPHIDInjector -ensureHardwareKeyboardEnabled`). | selector string + invoke in `-ensureHardwareKeyboardEnabled` (`SimBridge.m`); gated by `-sendKeyUsage:down:` on `SPIsModifierUsage` | `respondsToSelector`-guarded and best-effort: if absent or failing, plain typing still works and chords degrade to the prior (modifier-dropping) behaviour rather than crashing. |

---

## 3. SimulatorKit classes, selectors & Indigo HID C symbols

### 3.1 HID client (mangled Swift class name)

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `_TtC12SimulatorKit24SimDeviceLegacyHIDClient` | class (mangled) | The Swift `SimulatorKit.SimDeviceLegacyHIDClient` class. Created via `-initWithDevice:error:`; receives all Indigo HID messages. The mangled name is brittle: a SimulatorKit rename (or a recount of the `12`/`24` length prefixes) breaks it. | mangled string at `SimBridge.m:954`; `Doctor.swift:130` | `NSClassFromString` nil check → `NSError` code 31 (`SimBridge.m:955-959`); `sipi doctor` "SimulatorKit … HID client" asserts the class resolves (`Doctor.swift:130-138`). |
| `-initWithDevice:error:` | selector | Initializes the HID client against a `SimDevice`. | selector string at `SimBridge.m:961`; sent via `objc_msgSend` at `SimBridge.m:963` | `client == nil || initError != nil` → `NSError` code 32 (`SimBridge.m:964-968`). |
| `-sendWithMessage:freeWhenDone:completionQueue:completion:` | selector | Submits an Indigo message; `freeWhenDone:YES` transfers ownership so the client frees the message buffer. | selector cached at `SimBridge.m:972`; sent at `SimBridge.m:981` | cached `_sendSel` is nil-checked before send (`SimBridge.m:979`); on nil it frees the message instead of sending. |
| `SimulatorKit.SimDeviceScreen` | class | Orientation READ: `-initWithDevice:screenID:` → `-screen` → `-screenProperties` → `-uiOrientation`. | `NSClassFromString(@"SimulatorKit.SimDeviceScreen")` at `SimBridge.m:316` | `NSClassFromString` nil check → `NSError` code 50 (`SimBridge.m:317-321`); each chained selector separately guarded (codes 51-56). |
| `-initWithDevice:screenID:` + magic `screenID == 1` | selector + constant | Builds a `SimDeviceScreen` for the primary display (screen ID 1). | selector `SimBridge.m:323`; `screenID:1` at `SimBridge.m:330` | `instancesRespondToSelector` → `NSError` code 51 (`SimBridge.m:324-328`); nil result → code 52 (`SimBridge.m:331-335`). |
| `-screen`, `-screenProperties`, `-uiOrientation` | selectors | Walk to the orientation enum. `uiOrientation` returns a `UInt32` 1…4 (1 portrait, 2 portrait-upside-down, 3 landscape-left, 4 landscape-right). | `SimBridge.m:337` (`screen`), `344` (`screenProperties`), `351-357` (`uiOrientation`) | `SPPerformNoArg` guards `-screen`/`-screenProperties` (codes 53, 54); `respondsToSelector` guards `-uiOrientation` (code 55); an out-of-range raw value → code 56 (`SimBridge.m:360-370`). |

### 3.2 Indigo HID C functions (dlsym from SimulatorKit)

Resolved with `dlsym(RTLD_DEFAULT, …)` once SimulatorKit is loaded; cached as
function pointers on `SPHIDInjector` (`SimBridge.m:944-947`).

| Symbol | What it does | Where used | Doctor guard |
|---|---|---|---|
| `IndigoHIDMessageForMouseNSEvent` | Builds a touch / mouse Indigo message: `fn(&pt, pt2, flags, phase, 1.0, 1.0, edge)`. Single-point taps/swipes pass `pt2 = NULL`; multi-touch passes a second point. | `dlsym` at `SimBridge.m:944`; called in `-sendTouchPhase:` `SimBridge.m:987` and `-sendMultiTouchPhase:` `SimBridge.m:1076` | required: `_mouseFunc == NULL` → `NSError` code 30 (`SimBridge.m:948-952`); every send re-checks `_mouseFunc == NULL` (`SimBridge.m:985`, `1073`). |
| `IndigoHIDMessageForButton` | Builds a hardware-button Indigo message: `fn(source, direction, 0x33)`. | `dlsym` at `SimBridge.m:945`; called in `-sendHIDButtonSource:direction:` `SimBridge.m:999` | optional: `_buttonFunc == NULL` early-returns (`SimBridge.m:998`); a missing button symbol degrades buttons but does not crash. |
| `IndigoHIDMessageForKeyboardArbitrary` | Builds a keyboard Indigo message: `fn(usage, isDown)` where `isDown` is `1` (down) / `2` (up). | `dlsym` at `SimBridge.m:946`; called in `-sendKeyUsage:down:` `SimBridge.m:1060` | optional: `_keyboardFunc == NULL` early-returns (`SimBridge.m:1059`). |
| `IndigoHIDMessageForDigitalCrownEvent` | Builds a Digital Crown rotation Indigo message: `fn(delta)` (Apple Watch simulators only). | `dlsym` at `SimBridge.m:947`; called in `-sendDigitalCrown:` `SimBridge.m:1067` | optional: `_crownFunc == NULL` (or `NaN` delta) early-returns (`SimBridge.m:1066`). |

### 3.3 Magic HID constants

These integers are baked into the Indigo wire format; they were recovered by
disassembly of the reference binary and have no symbolic name. A change in the
Indigo protocol would silently mis-encode events (no crash, wrong behavior), so
they are documented here rather than guarded at runtime.

| Constant | Meaning | Where used |
|---|---|---|
| `50` | Mouse/touch event "type" for a single-finger touch in `IndigoHIDMessageForMouseNSEvent`. | `SimBridge.m:987` (`_mouseFunc(&point, NULL, 50, phase, …)`) |
| `0x32` (50) | Mouse/touch flags for a **two-finger** (multi-touch) event — one message carries both points. | `SimBridge.m:1076` (`_mouseFunc(&p1, &p2, 0x32, phase, …)`) |
| `0x33` (51) | Third argument to `IndigoHIDMessageForButton` (button page/usage selector). | `SimBridge.m:999` |
| touch `phase` 1 / 2 | `1` = begin/move, `2` = end. A tap is `1` then `2`; a swipe is `1` … (interpolated moves) … `2`. | `SimBridge.m:992-994` (tap), `1008-1014` (swipe-home), passed through everywhere `sendTouchPhase:`/`sendMultiTouchPhase:` is called |
| key direction 1 / 2 | `1` = key down, `2` = key up. | `SimBridge.m:1060` (`_keyboardFunc(usage, down ? 1 : 2)`) |
| button direction 1 / 2 | `1` = press, `2` = release (the reference binary's follow-up code). | `SimBridge.m:1018-1051` (`-pressButton:`) |
| button source codes `0`, `1`, `3`, `3000`, `0x400002` | Hardware-button source identifiers: `0` = Home, `1` = Lock, `3000` = side button, `0x400002` = Siri (press-and-hold). App Switcher = double Home; Swipe Home = bottom edge swipe. | `SimBridge.m:1019-1051` |
| `edge` `0` / `3` | Touch edge flag: `0` = interior touch, `3` = bottom-edge swipe (used by swipe-home). | `SimBridge.m:987`, `1006-1014` |

---

## 4. AccessibilityPlatformTranslation (APT) classes, selectors & KVC keys

The describe-ui tree is produced entirely through APT. The recipe (recovered by
runtime introspection of `AXPTranslator` and disassembly of the reference
binary) is documented inline at `SimBridge.m:470-482`.

| Symbol | Kind | What it does | Where used | Doctor guard |
|---|---|---|---|---|
| `AXPTranslator` | class | The translator singleton (`+sharedInstance`); the root of the AX path. | `NSClassFromString(@"AXPTranslator")` at `SimBridge.m:434`, `580` | `NSClassFromString` nil check (`SimBridge.m:435-437`, `582-586`); `sipi doctor` reports `AXPTranslator ready` / `class missing` (`SimBridge.m:434-446`). |
| `+sharedInstance` | selector | Returns the translator singleton. | `SimBridge.m:439-443`, `581-587` | `respondsToSelector` + nil-result checks → status string / `NSError` code 21 (`SimBridge.m:582-592`). |
| KVC keys `bridgeTokenDelegate`, `supportsDelegateTokens`, `accessibilityEnabled` | KVC properties | Configure the translator: set this bridge as the token delegate, enable delegate tokens, enable accessibility. The reference binary uses `setValue:forKey:`, not setters. | `SimBridge.m:595-597` | implicit (KVC); the subsequent transport calls fail with `NSError` if the translator was not configured. |
| `bridgeDelegateToken` lifetime (stable per device) | behavioral contract | `AXPTranslator` caches the `AXPMacPlatformElement` it builds for the frontmost app and pins it to the token of the *first* fetch; that element's later AX requests still dispatch through that original token. So the bridge mints **one stable token per device** and never evicts it from `_tokenToDevice`, otherwise a second in-process fetch reuses the cached element against an evicted token and degenerates to an empty root. | `SimBridge.m` `-stableTokenForDevice:udid:` (`_udidToToken`/`_tokenToDevice`) | gated `SimNativeIntegrationTests` assert repeated in-process fetches each return `> 1` node. |
| `frontmostApplicationWithDisplayId:bridgeDelegateToken:` + magic `displayId == 0` | selector + constant | Returns the frontmost app's root `AXPTranslationObject` for display 0. | selector string `SimBridge.m:794`; sent at `SimBridge.m:795` | nil result → `NSError` code 24 (`SimBridge.m:796-800`). |
| `macPlatformElementFromTranslation:` | selector | Converts an `AXPTranslationObject` into an NSAccessibility-walkable `AXPMacPlatformElement`. | `SimBridge.m:733`, `804-807`, `877-880` | `respondsToSelector` check; nil result → `NSError` code 25 (`SimBridge.m:808-812`). |
| `objectAtPoint:displayId:bridgeDelegateToken:` + magic `displayId == 0` | selector + constant | Single hit-test at a logical point; backs both the 16pt grid pass and `describe-point`. | selector string `SimBridge.m:732`, `856`; sent at `SimBridge.m:751`, `870` | `respondsToSelector` → grid pass quietly skips (`SimBridge.m:734`), or `NSError` code 26 for `describe-point` (`SimBridge.m:857-861`). |
| `AXPTranslatorResponse` + `+emptyResponse` | class + selector | The "no data" sentinel the bridge returns from a translator callback when the token has no device / the transport times out. | `SimBridge.m:567-572` | `responseClass && respondsToSelector` guard; returns `nil` if unavailable (`SimBridge.m:569-572`). |
| `AXPTranslationTokenDelegateHelper` (protocol) | protocol | The delegate protocol whose callbacks (`accessibilityTranslationDelegateBridgeCallbackWithToken:` etc.) forward each translator request to the device transport. | conformance implemented `SimBridge.m:607-630`; protocol existence probed at `SimBridge.m:448` | `objc_getProtocol(...) != NULL` reported as `tokenDelegate proto ✓/✗` in `sipi doctor` (`SimBridge.m:448`, `461-465`). |
| `AXPMacPlatformElement` | class | The NSAccessibility element type the tree walk serializes. | presence probed at `SimBridge.m:449` | `NSClassFromString(...) != nil` reported as `macElement ✓/✗` in `sipi doctor` (`SimBridge.m:449`, `461-465`). |
| NSAccessibility KVC keys (`accessibilityLabel`, `accessibilityValue`, `accessibilityRoleDescription`, `accessibilityRole`, `accessibilitySubrole`, `accessibilityIdentifier`, `accessibilityEnabled`, `accessibilityChildren`, `accessibilityFrame`) | KVC / selectors | Per-node serialization into the describe-ui shape. `accessibilityRole` is captured raw into `role`, then `AX`-stripped into `type`; `accessibilitySubrole` is emitted only when non-empty. | `SimBridge.m:674-697` (serialize), `656-658` (`accessibilityFrame`) | each read goes through `SPAXString`/`SPAXBool`, which `@try/@catch` around `valueForKey:` and return a default on failure (`SimBridge.m:484-497`); `accessibilityFrame` is `respondsToSelector`-guarded (`SimBridge.m:656-657`). |
| `registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:` / `unregisterScreenCallbacksWithUUID:` | selectors | Framebuffer mirror: register/unregister screen ping callbacks on a display descriptor. | `SimBridge.m:1269-1271` (register), `1290` (unregister) | `respondsToSelector` guards both (`SimBridge.m:1279`, `1294`). |
| `updateIOPorts`, `deviceIOPorts` (KVC), `portIdentifier`, `descriptor`, `framebufferSurface` + magic `"com.apple.framebuffer.display"` | selectors / KVC / constant | Resolve the framebuffer IOSurface: refresh IO ports, find the port whose `portIdentifier == "com.apple.framebuffer.display"`, take its `descriptor`, read `framebufferSurface`. | `SimBridge.m:1196-1217` (resolve), `1227-1238` (`currentSurface`) | `updateIOPorts`/`portIdentifier`/`framebufferSurface` are `respondsToSelector`/`SPPerformNoArg`-guarded; `deviceIOPorts` is `@try/@catch` + class check → `NSError` code 41 (`SimBridge.m:1199-1205`); no descriptor → code 42 (`SimBridge.m:1218-1222`). |

---

## 5. How the guards roll up into `sipi doctor`

`sipi doctor` (`Sources/sipi/Doctor.swift`) is the per-Xcode early-warning
system for this whole surface. Its three core checks map directly onto the
sections above:

- **CoreSimulator** — `+loadCoreSimulator:` dlopen + `SimServiceContext` /
  `SimDevice` class resolution (§1, §2).
- **SimulatorKit** — binary existence + `dlopen` + the mangled
  `_TtC12SimulatorKit24SimDeviceLegacyHIDClient` class (§1, §3.1).
- **AccessibilityPlatformTranslation** — `+accessibilityBridgeStatus` probes
  APT dlopen, `AXPTranslator`/`sharedInstance`, the token-delegate protocol, the
  Mac platform-element class, and the `SimDevice` transport selector (§1, §4).

If any core check fails, `sipi doctor` exits non-zero and `preflight` stops the
workflow (see `docs/sipi-doctor-contract.md`). The workflow in
`.github/workflows/sipi-doctor-matrix.yml` is a **DRAFT**: it is manual-only
(`workflow_dispatch`; the push/PR triggers are commented out) and carries a
single placeholder Xcode entry, so it does **not** run per-Xcode today. It is
*intended* to run `sipi doctor --json` against each supported Xcode — so a
private-symbol break would show up as a failed check naming the exact capability
rather than as a downstream crash — once a runner-fleet decision (which Xcodes,
which runners) is made. Treat it as aspirational, not an active churn gate.

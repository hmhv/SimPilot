// SimBridge.h
//
// Native bridge into Apple's private Simulator frameworks (CoreSimulator,
// SimulatorKit, AccessibilityPlatformTranslation), loaded at runtime via dlopen.
// It drives the Simulator in-process: accessibility tree fetch, HID injection,
// and zero-copy framebuffer capture, with no Node runtime and no spawned helper
// process.
//
// SimBridge is largely an independent implementation against those Apple private
// frameworks. Its HID injector (SPHIDInjector) is adapted from serve-sim
// (Apache-2.0); the accessibility, framebuffer, and orientation paths are
// independent reimplementations informed by serve-sim and idb/AXe, with no
// source copied. See THIRD_PARTY_LICENSES.md.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One simulator device discovered through CoreSimulator.
@interface SPSimDevice : NSObject
@property (nonatomic, copy) NSString *udid;
@property (nonatomic, copy) NSString *name;
/// CoreSimulator SimDeviceState raw value (3 == Booted).
@property (nonatomic) NSInteger state;
@property (nonatomic, copy) NSString *stateString;
@property (nonatomic, copy, nullable) NSString *runtimeName;
@property (nonatomic, copy, nullable) NSString *runtimeIdentifier;
@property (nonatomic, copy, nullable) NSString *deviceTypeName;
@property (nonatomic, copy, nullable) NSString *deviceTypeIdentifier;

@property (nonatomic, readonly) BOOL isBooted;
@end

/// Entry point for the native bridge. All methods are safe to call off the main
/// thread. CoreSimulator/APT are dlopen'd lazily on first use.
@interface SPSimBridge : NSObject

/// Resolve the active Xcode developer dir: `DEVELOPER_DIR` if set, else
/// `xcode-select -p`, else `/Applications/Xcode.app/Contents/Developer`.
+ (NSString *)defaultDeveloperDir;

/// Force-load CoreSimulator from disk. Returns NO and fills `error` on failure.
+ (BOOL)loadCoreSimulator:(NSError **)error;

/// Enumerate every simulator in the developer dir's default device set.
/// Pure CoreSimulator: no `xcrun simctl`, no `npx`, no spawned helper.
+ (nullable NSArray<SPSimDevice *> *)listDevicesForDeveloperDir:(NSString *)developerDir
                                                          error:(NSError **)error;

/// Probe whether the AccessibilityPlatformTranslation bridge is loadable and the
/// AXPTranslator class resolves at runtime. Returns a short human-readable
/// status string; never throws.
+ (NSString *)accessibilityBridgeStatus;

/// Structured counterpart to `accessibilityBridgeStatus`: returns YES only when
/// every sub-check the bridge actually depends on resolves — APT loads,
/// AXPTranslator/sharedInstance is non-nil, the AXPTranslationTokenDelegateHelper
/// protocol and AXPMacPlatformElement class exist, and the SimDevice accessibility
/// transport selector is present. Use this to gate `doctor` (the status string is
/// for display only, and its "AXPTranslator ready" prefix is emitted even when a
/// sub-check is ✗). Never throws.
+ (BOOL)accessibilityBridgeReady;

/// Fetch the frontmost app's accessibility tree fully in-process via
/// AccessibilityPlatformTranslation — no Node, no spawned helper.
/// Returns an array with the root node; each node has the shape:
///   { AXLabel, AXValue, role_description, role, subrole, AXUniqueId, type,
///     frame:{x,y,width,height}, enabled, children:[...] }
/// (`role` is the raw accessibilityRole; `type` is the same role with the `AX`
/// prefix stripped; `subrole` is emitted only when non-empty.)
/// Returns nil + `error` on failure.
///
/// `deep` controls the cost/coverage tradeoff:
///   * NO  — frontmost element + recursive accessibilityChildren walk only
///           (fast, ~AXe speed; misses cross-process / System-UI overlays).
///   * YES — additionally run the full-screen 16pt objectAtPoint grid pass,
///           which surfaces status bar / map annotations / System-UI elements
///           the accessibilityChildren tree cannot reach (~1.0s).
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)accessibilityTreeForUDID:(NSString *)udid
                                                                         deep:(BOOL)deep
                                                                 developerDir:(NSString *)developerDir
                                                                        error:(NSError **)error;

/// Backward-compatible wrapper that fetches the accessibility tree with the grid
/// pass enabled (`deep:YES`). Prefer the `deep:`-taking variant for new callers.
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)accessibilityTreeForUDID:(NSString *)udid
                                                                 developerDir:(NSString *)developerDir
                                                                        error:(NSError **)error;

/// Single `objectAtPoint` hit-test at logical screen coordinates (x, y). No grid
/// pass — just one APT `objectAtPoint:displayId:bridgeDelegateToken:` lookup and
/// serialization of the hit element (same node shape as the tree, but without
/// recursing into its children). Returns the serialized node dictionary, or nil
/// when nothing is at the point (`error` stays nil) or on failure (`error` set).
+ (nullable NSDictionary<NSString *, id> *)elementAtPointForUDID:(NSString *)udid
                                                               x:(double)x
                                                               y:(double)y
                                                    developerDir:(NSString *)developerDir
                                                           error:(NSError **)error;

// MARK: - In-process HID injection
//
// Inject touches and hardware buttons via SimulatorKit's Indigo HID functions
// and SimDeviceLegacyHIDClient — in-process, no Node.

/// Report which of the four Indigo HID message builders resolve out of
/// SimulatorKit (`mouse` drives tap/touch/swipe; `button` drives `sipi button`;
/// `keyboard` drives `sipi key`/`type`; `crown` drives `sipi crown`). Each is
/// dlsym'd lazily, so a churned/missing symbol otherwise no-ops silently while the
/// command still reports ok. Loads SimulatorKit if needed, then probes each
/// symbol and returns the result keyed by name ("mouse", "button", "keyboard",
/// "crown") with @YES/@NO values; on dlopen failure the dictionary is empty.
/// `mouse` is the only required symbol (its absence fails all HID paths); the
/// others are reported so `doctor` can warn when an input class is unavailable.
+ (NSDictionary<NSString *, NSNumber *> *)hidSymbolStatusForDeveloperDir:(NSString *)developerDir;

/// Tap at normalized coordinates (0...1 of the screen) — a begin + end touch.
+ (BOOL)tapUDID:(NSString *)udid
    normalizedX:(double)nx
              y:(double)ny
   developerDir:(NSString *)developerDir
          error:(NSError **)error;

/// Low-level tap passing the location straight to the Indigo mouse builder,
/// which itself expects a normalized 0...1 location (so this is equivalent to
/// `tapUDID:normalizedX:y:`).
+ (BOOL)tapUDID:(NSString *)udid
      absoluteX:(double)x
              y:(double)y
   developerDir:(NSString *)developerDir
          error:(NSError **)error;

/// Press a hardware button: "home", "lock", "side_button", "swipe_home".
+ (BOOL)pressButton:(NSString *)button
               udid:(NSString *)udid
       developerDir:(NSString *)developerDir
              error:(NSError **)error;

/// Send a single touch phase at a normalized 0...1 location. `phase` 1 = begin/move,
/// 2 = end. Sequence 1 (down) → 1… (drag) → 2 (up) to tap or swipe. Used to wire
/// direct clicks/drags on the live mirror to the simulator.
+ (BOOL)touchUDID:(NSString *)udid
            phase:(NSInteger)phase
      normalizedX:(double)nx
                y:(double)ny
     developerDir:(NSString *)developerDir
            error:(NSError **)error;

/// Two-finger touch phase at two normalized 0...1 points (e.g. pinch-to-zoom).
/// `phase` 1 = begin/move, 2 = end.
+ (BOOL)multiTouchUDID:(NSString *)udid
                 phase:(NSInteger)phase
                    x1:(double)x1
                    y1:(double)y1
                    x2:(double)x2
                    y2:(double)y2
          developerDir:(NSString *)developerDir
                 error:(NSError **)error;

/// Send a keyboard event by USB HID usage code (e.g. 0x2A = Delete, 0x28 = Return).
+ (BOOL)sendKeyUsage:(NSUInteger)usage
                down:(BOOL)down
                udid:(NSString *)udid
        developerDir:(NSString *)developerDir
               error:(NSError **)error;

/// Send a Digital Crown rotation delta (Apple Watch simulators only).
+ (BOOL)sendDigitalCrownDelta:(double)delta
                         udid:(NSString *)udid
                 developerDir:(NSString *)developerDir
                        error:(NSError **)error;

/// Capture a single framebuffer frame to a PNG file (headless utility / capture
/// verification). Uses the zero-copy IOSurface path. Returns NO + error on failure.
+ (BOOL)writeFramebufferPNGForUDID:(NSString *)udid
                      developerDir:(NSString *)developerDir
                            toPath:(NSString *)path
                             error:(NSError **)error;

// MARK: - Orientation (native READ)

/// Read the current physical UI orientation natively, with no FB frameworks and
/// no osascript: SimulatorKit's `SimDeviceScreen.uiOrientation`. Wire-up:
///   screen = [[SimDeviceScreen alloc] initWithDevice:<SimDevice> screenID:1];
///   props  = [[screen screen] screenProperties];
///   raw    = (UInt32)[props uiOrientation];
/// The raw value is a `UIInterfaceOrientation`-style enum, 1...4:
///   1 = portrait, 2 = portrait-upside-down, 3 = landscape-left, 4 = landscape-right.
/// On success returns the raw value (1...4) in `*rawOut` and a stable lowercase
/// name ("portrait" | "portrait-upside-down" | "landscape-left" |
/// "landscape-right") in `*nameOut`, and returns YES. Returns NO + `error` when
/// the device, SimDeviceScreen class, or the uiOrientation selector cannot be
/// resolved (each step is `respondsToSelector`-guarded so a churned symbol
/// surfaces as an actionable error, not a crash). This is READ only; orientation
/// SET stays on the existing osascript path until the native PurpleEvent SET
/// lands in M4.
+ (BOOL)uiOrientationForUDID:(NSString *)udid
                developerDir:(NSString *)developerDir
                      rawOut:(nullable uint32_t *)rawOut
                     nameOut:(NSString *_Nullable *_Nullable)nameOut
                       error:(NSError **)error;

// MARK: - Orientation (native SET via PurpleEvent)

/// Set the device's interface orientation natively, with no FB frameworks and
/// no osascript, by sending a `GSEventTypeDeviceOrientationChanged` mach message
/// to the simulator's `PurpleWorkspacePort`. Wire format (reverse-engineered from
/// `Simulator.app`'s `[SimDevice(GSEvents) gsEventsSendOrientation:]`, documented
/// in idb's `PrivateHeaders/SimulatorApp/GSEvent.h` and unit-tested in tddworks
/// *baguette*'s `OrientationEvent`): a 112-byte buffer whose `mach_msg_header_t`
/// carries `msgh_bits`=0x13, `msgh_size`=108, `msgh_id`=0x7B, and whose GSEvent
/// body holds `type`=(50|0x20000) at 0x18, `record_info_size`=4 at 0x48, and the
/// `UIDeviceOrientation` raw value (1...4) at 0x4C; the looked-up port is patched
/// into `msgh_remote_port` at offset 0x08.
///
/// `orientation` accepts the same lowercase names the READ emits: "portrait",
/// "portrait-upside-down", "landscape-left", "landscape-right". NOTE: the wire
/// payload is `UIDeviceOrientation`, where landscape-left=4 and landscape-right=3
/// (the opposite of the `UIInterfaceOrientation`-style values the READ reports);
/// this method maps the names to the correct device-orientation raw values.
/// "face-up"/"face-down" are NOT supported here — PurpleEvent covers only
/// `UIDeviceOrientation` 1...4, so those stay on the osascript path.
///
/// The `PurpleWorkspacePort` is nil/0 until the guest is past pre-springboard
/// boot, so the lookup is retried a few times before giving up. Every step is
/// guarded (the lookup selector is checked, the reverse-engineered wire format is
/// fenced behind a capability probe), so a churned symbol or an un-booted device
/// surfaces as an actionable NSError, not a crash. Returns NO + `error` on
/// failure so the caller can fall back to the osascript SET path.
+ (BOOL)setOrientationNative:(NSString *)orientation
                        udid:(NSString *)udid
                developerDir:(NSString *)developerDir
                       error:(NSError **)error;

@end

// MARK: - Live framebuffer mirror

@class NSView;

/// Mirrors the simulator framebuffer fully in-process via SimulatorKit's display
/// descriptor (zero-copy IOSurface), with no WebView.
@interface SPFrameCapture : NSObject

/// Start mirroring into the returned layer-backed view (its layer's `contents`
/// is updated with each framebuffer IOSurface). Returns nil + error on failure.
/// Convenience for `wireUpForUDID:` + `makeMirrorView` on the main thread.
- (nullable NSView *)startMirrorForUDID:(NSString *)udid
                           developerDir:(NSString *)developerDir
                                  error:(NSError **)error;

/// Resolve the framebuffer descriptors (CoreSimulator/SimulatorKit). XPC-backed,
/// so this is safe to call off the main thread. Returns NO + error on failure.
- (BOOL)wireUpForUDID:(NSString *)udid
         developerDir:(NSString *)developerDir
                error:(NSError **)error;

/// Build the mirror view and begin capture. MUST be called on the main thread
/// (it creates an NSView), after a successful `wireUpForUDID:`.
- (nullable NSView *)makeMirrorView;

/// Stop capturing (safe from any thread).
- (void)stop;

@end

NS_ASSUME_NONNULL_END

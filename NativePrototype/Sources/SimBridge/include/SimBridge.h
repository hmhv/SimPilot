// SimBridge.h
//
// Native bridge into Apple's private Simulator frameworks (CoreSimulator,
// SimulatorKit, AccessibilityPlatformTranslation). This lets the prototype talk
// to the Simulator without going through Node / `npx serve-sim`.
//
// Implementation concepts (which private symbols matter, how the accessibility
// path is wired) were learned by inspecting `serve-sim` (Apache-2.0). No source
// is copied from serve-sim; the calls here are an independent reimplementation
// against the same Apple private APIs. See ../../THIRD_PARTY_NOTICES.md.

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

/// Resolve the active Xcode developer dir (mirrors `xcode-select -p`), falling
/// back to `/Applications/Xcode.app/Contents/Developer`.
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

/// Fetch the frontmost app's accessibility tree fully in-process via
/// AccessibilityPlatformTranslation — no serve-sim, no Node, no spawned helper.
/// Returns an array with the root node; each node has the same shape as
/// serve-sim's `/ax` endpoint:
///   { AXLabel, AXValue, role_description, AXUniqueId, type,
///     frame:{x,y,width,height}, enabled, children:[...] }
/// Returns nil + `error` on failure.
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)accessibilityTreeForUDID:(NSString *)udid
                                                                 developerDir:(NSString *)developerDir
                                                                        error:(NSError **)error;

// MARK: - In-process HID injection (no serve-sim)
//
// Inject touches and hardware buttons via SimulatorKit's Indigo HID functions
// and SimDeviceLegacyHIDClient — no `serve-sim tap/button`, no Node.

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

@end

// MARK: - Live framebuffer mirror (no serve-sim stream)

@class NSView;

/// Mirrors the simulator framebuffer fully in-process via SimulatorKit's display
/// descriptor (zero-copy IOSurface), with no serve-sim and no WebView.
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

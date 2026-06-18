// SimBridge.m — see SimBridge.h for attribution and scope.

#import "SimBridge.h"
#import <dlfcn.h>
#import <unistd.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#import <CoreImage/CoreImage.h>

#pragma mark - Private framework paths

static NSString *const kCoreSimulatorPath =
    @"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator";
static NSString *const kAccessibilityPlatformTranslationPath =
    @"/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/"
    @"AccessibilityPlatformTranslation";

static NSString *const kBridgeErrorDomain = @"SPSimBridge";

#pragma mark - Minimal private interfaces
//
// These declarations only tell the compiler the selector shapes; the real
// implementations come from the dlopen'd frameworks at runtime. Keeping them
// here (instead of linking) avoids hardcoding a build-time framework search
// path and lets us load AccessibilityPlatformTranslation, which lives only in
// the dyld shared cache (no linkable on-disk binary).

@class SimDeviceSet;
@class SimDeviceType;
@class SimRuntime;
@class SimDevice;

@interface SimServiceContext : NSObject
+ (instancetype)sharedServiceContextForDeveloperDir:(NSString *)developerDir
                                              error:(NSError **)error;
- (SimDeviceSet *)defaultDeviceSetWithError:(NSError **)error;
@end

@interface SimDeviceSet : NSObject
@property (nonatomic, readonly) NSArray<SimDevice *> *devices;
@end

@interface SimDeviceType : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *identifier;
@end

@interface SimRuntime : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *versionString;
@end

@interface SimDevice : NSObject
@property (nonatomic, readonly) NSUUID *UDID;
@property (nonatomic, readonly) NSString *name;
// SimDeviceState is NS_ENUM(NSUInteger, ...) — must match the real 8-byte width;
// declaring this `unsigned int` would be a return-type ABI mismatch (UB).
@property (nonatomic, readonly) NSUInteger state;
@property (nonatomic, readonly) NSString *stateString;
@property (nonatomic, readonly) SimDeviceType *deviceType;
@property (nonatomic, readonly) SimRuntime *runtime;
@end

#pragma mark - SPSimDevice

@implementation SPSimDevice
- (BOOL)isBooted { return self.state == 3; } // SimDeviceState.Booted
@end

#pragma mark - Helpers

static BOOL SPDlopen(NSString *path, NSString *label, NSError **error) {
    if (dlopen(path.fileSystemRepresentation, RTLD_NOW) != NULL) {
        return YES;
    }
    if (error) {
        const char *e = dlerror();
        *error = [NSError errorWithDomain:kBridgeErrorDomain
                                     code:1
                                 userInfo:@{
            NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Failed to load %@: %s", label, e ? e : "unknown error"]
        }];
    }
    return NO;
}

// Look up the SimDevice (returned as id, since CoreSimulator types are dynamic)
// for a UDID via the default device set. Shared by the AX and HID bridges.
static id SPCopySimDeviceForUDID(NSString *udid, NSString *developerDir, NSError **error) {
    if (![SPSimBridge loadCoreSimulator:error]) return nil;
    Class contextClass = NSClassFromString(@"SimServiceContext");
    SimServiceContext *context = [contextClass sharedServiceContextForDeveloperDir:developerDir error:error];
    if (context == nil) return nil;
    SimDeviceSet *deviceSet = [context defaultDeviceSetWithError:error];
    if (deviceSet == nil) return nil;
    for (SimDevice *device in deviceSet.devices) {
        if ([device.UDID.UUIDString caseInsensitiveCompare:udid] == NSOrderedSame) {
            return device;
        }
    }
    if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:22 userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No SimDevice with UDID %@", udid]}];
    return nil;
}

#pragma mark - SPSimBridge

// In-process accessibility bridge (defined below). Forward-declared so the
// public +accessibilityTreeForUDID: entry point can live on the primary class.
@interface SPAccessibilityBridge : NSObject
+ (instancetype)shared;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)treeForUDID:(NSString *)udid
                                                     developerDir:(NSString *)developerDir
                                                            error:(NSError **)error;
@end

@interface SPHIDInjector : NSObject
+ (instancetype)shared;
- (BOOL)setupForUDID:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error;
- (void)tapAbsoluteX:(double)x y:(double)y;
- (void)sendTouchPhase:(int32_t)phase x:(double)x y:(double)y edge:(uint32_t)edge;
- (BOOL)pressButton:(NSString *)name;
- (void)sendKeyUsage:(uint32_t)usage down:(BOOL)down;
- (void)sendDigitalCrown:(double)delta;
- (void)sendMultiTouchPhase:(int32_t)phase x1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2;
@end

// Private helper on the framebuffer mirror, used by the headless PNG utility.
@interface SPFrameCapture ()
- (nullable CGImageRef)copyCurrentCGImage CF_RETURNS_RETAINED;
@end

@implementation SPSimBridge

+ (NSString *)defaultDeveloperDir {
    // `xcode-select -p` without spawning a process: DEVELOPER_DIR wins, else
    // the well-known Xcode location.
    NSString *envDir = NSProcessInfo.processInfo.environment[@"DEVELOPER_DIR"];
    if (envDir.length > 0) return envDir;
    return @"/Applications/Xcode.app/Contents/Developer";
}

+ (BOOL)loadCoreSimulator:(NSError **)error {
    // Memoize only success. dlopen is refcounted and idempotent, so retrying
    // after a transient first failure is cheap and lets a later call (e.g. the
    // Reload button) recover instead of being stuck for the process lifetime.
    static BOOL loaded = NO;
    if (loaded) return YES;
    NSError *e = nil;
    if (SPDlopen(kCoreSimulatorPath, @"CoreSimulator", &e)) {
        loaded = YES;
        return YES;
    }
    if (error) *error = e;
    return NO;
}

+ (BOOL)loadAccessibilityPlatformTranslation:(NSError **)error {
    // Same success-only memoization as CoreSimulator so the AX probe loads the
    // framework once instead of re-dlopen'ing it on every status call.
    static BOOL loaded = NO;
    if (loaded) return YES;
    NSError *e = nil;
    if (SPDlopen(kAccessibilityPlatformTranslationPath, @"AccessibilityPlatformTranslation", &e)) {
        loaded = YES;
        return YES;
    }
    if (error) *error = e;
    return NO;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)accessibilityTreeForUDID:(NSString *)udid
                                                        developerDir:(NSString *)developerDir
                                                               error:(NSError **)error {
    return [[SPAccessibilityBridge shared] treeForUDID:udid developerDir:developerDir error:error];
}

+ (BOOL)tapUDID:(NSString *)udid absoluteX:(double)x y:(double)y developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    // Serialize setup + send on the shared injector so its cached client/device/
    // function pointers aren't read while another thread is (re)setting them.
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        [hid tapAbsoluteX:x y:y];
    }
    return YES;
}

+ (BOOL)tapUDID:(NSString *)udid normalizedX:(double)nx y:(double)ny developerDir:(NSString *)developerDir error:(NSError **)error {
    // The Indigo mouse builder takes a normalized 0...1 location directly, so
    // normalized coordinates pass straight through.
    return [self tapUDID:udid absoluteX:nx y:ny developerDir:developerDir error:error];
}

+ (BOOL)touchUDID:(NSString *)udid phase:(NSInteger)phase normalizedX:(double)nx y:(double)ny developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        [hid sendTouchPhase:(int32_t)phase x:nx y:ny edge:0];
    }
    return YES;
}

+ (BOOL)pressButton:(NSString *)button udid:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        if (![hid pressButton:button]) {
            if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:34 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown button: %@", button]}];
            return NO;
        }
    }
    return YES;
}

+ (BOOL)sendKeyUsage:(NSUInteger)usage down:(BOOL)down udid:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        [hid sendKeyUsage:(uint32_t)usage down:down];
    }
    return YES;
}

+ (BOOL)sendDigitalCrownDelta:(double)delta udid:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        [hid sendDigitalCrown:delta];
    }
    return YES;
}

+ (BOOL)multiTouchUDID:(NSString *)udid phase:(NSInteger)phase x1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 developerDir:(NSString *)developerDir error:(NSError **)error {
    SPHIDInjector *hid = [SPHIDInjector shared];
    @synchronized (hid) {
        if (![hid setupForUDID:udid developerDir:developerDir error:error]) return NO;
        [hid sendMultiTouchPhase:(int32_t)phase x1:x1 y1:y1 x2:x2 y2:y2];
    }
    return YES;
}

+ (BOOL)writeFramebufferPNGForUDID:(NSString *)udid developerDir:(NSString *)developerDir toPath:(NSString *)path error:(NSError **)error {
    SPFrameCapture *capture = [SPFrameCapture new];
    if (![capture wireUpForUDID:udid developerDir:developerDir error:error]) return NO;
    CGImageRef image = [capture copyCurrentCGImage];
    if (image == NULL) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:43 userInfo:@{
            NSLocalizedDescriptionKey: @"No framebuffer image available"}];
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    BOOL ok = [png writeToFile:path atomically:YES];
    if (!ok && error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:44 userInfo:@{
        NSLocalizedDescriptionKey: @"Failed to write PNG"}];
    return ok;
}

+ (nullable NSArray<SPSimDevice *> *)listDevicesForDeveloperDir:(NSString *)developerDir
                                                          error:(NSError **)error {
    if (![self loadCoreSimulator:error]) return nil;

    Class contextClass = NSClassFromString(@"SimServiceContext");
    if (contextClass == nil) {
        if (error) {
            *error = [NSError errorWithDomain:kBridgeErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"SimServiceContext class not found after load"}];
        }
        return nil;
    }

    NSError *ctxError = nil;
    SimServiceContext *context =
        [contextClass sharedServiceContextForDeveloperDir:developerDir error:&ctxError];
    if (context == nil) {
        if (error) *error = ctxError ?: [NSError errorWithDomain:kBridgeErrorDomain code:3 userInfo:nil];
        return nil;
    }

    NSError *setError = nil;
    SimDeviceSet *deviceSet = [context defaultDeviceSetWithError:&setError];
    if (deviceSet == nil) {
        if (error) *error = setError ?: [NSError errorWithDomain:kBridgeErrorDomain code:4 userInfo:nil];
        return nil;
    }

    NSMutableArray<SPSimDevice *> *result = [NSMutableArray array];
    for (SimDevice *device in deviceSet.devices) {
        SPSimDevice *info = [SPSimDevice new];
        info.udid = device.UDID.UUIDString ?: @"";
        info.name = device.name ?: @"";
        info.state = (NSInteger)device.state;
        info.stateString = device.stateString ?: @"";
        SimRuntime *runtime = device.runtime;
        info.runtimeName = runtime.name;
        info.runtimeIdentifier = runtime.identifier;
        SimDeviceType *type = device.deviceType;
        info.deviceTypeName = type.name;
        info.deviceTypeIdentifier = type.identifier;
        [result addObject:info];
    }
    return result;
}

+ (NSString *)accessibilityBridgeStatus {
    // Probes the in-process accessibility path. Each step below is a real
    // runtime check, so this status reflects what actually resolves on this
    // machine, not a hardcoded string.
    NSError *aptError = nil;
    if (![self loadAccessibilityPlatformTranslation:&aptError]) {
        return aptError.localizedDescription ?: @"APT not loadable";
    }

    Class translatorClass = NSClassFromString(@"AXPTranslator");
    if (translatorClass == nil) {
        return @"APT loaded but AXPTranslator class missing";
    }

    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    id translator = nil;
    if ([translatorClass respondsToSelector:sharedSel]) {
        translator = ((id (*)(id, SEL))objc_msgSend)(translatorClass, sharedSel);
    }
    if (translator == nil) {
        return @"AXPTranslator present but sharedInstance returned nil";
    }

    BOOL hasTokenProtocol = objc_getProtocol("AXPTranslationTokenDelegateHelper") != NULL;
    BOOL hasMacElement = NSClassFromString(@"AXPMacPlatformElement") != nil;

    // Confirm the device-side transport selector exists on SimDevice.
    BOOL hasTransport = NO;
    if ([self loadCoreSimulator:NULL]) {
        Class simDeviceClass = NSClassFromString(@"SimDevice");
        SEL transportSel =
            NSSelectorFromString(@"sendAccessibilityRequestAsync:completionQueue:completionHandler:");
        hasTransport = simDeviceClass != nil &&
            class_getInstanceMethod(simDeviceClass, transportSel) != NULL;
    }

    return [NSString stringWithFormat:
            @"AXPTranslator ready (sharedInstance ✓, tokenDelegate proto %@, macElement %@, SimDevice transport %@)",
            hasTokenProtocol ? @"✓" : @"✗",
            hasMacElement ? @"✓" : @"✗",
            hasTransport ? @"✓" : @"✗"];
}

@end

#pragma mark - In-process accessibility bridge (AccessibilityPlatformTranslation)
//
// Reimplements serve-sim's AccessibilityBridge against the same Apple private
// APIs (independent reimplementation — serve-sim's helper source is not
// distributed; see ../../THIRD_PARTY_NOTICES.md). Recipe recovered by runtime
// introspection of AXPTranslator and disassembly of the reference binary:
//   1. translator = [AXPTranslator sharedInstance]
//   2. KVC: bridgeTokenDelegate = self; supportsDelegateTokens = YES; accessibilityEnabled = YES
//   3. token = UUID; tokenToDevice[token] = SimDevice
//   4. root = [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:token]
//   5. walk root via NSAccessibility KVC into the serve-sim /ax node shape
// The translator drives the AXPTranslationTokenDelegateHelper callbacks below,
// which forward each translator request to SimDevice -sendAccessibilityRequestAsync:.

static NSString *SPAXString(id element, NSString *key) {
    id value = nil;
    @try { value = [element valueForKey:key]; } @catch (__unused id e) { return nil; }
    if (value == nil) return nil;
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value respondsToSelector:@selector(string)]) return [value string]; // NSAttributedString
    return [value description];
}

static BOOL SPAXBool(id element, NSString *key) {
    id value = nil;
    @try { value = [element valueForKey:key]; } @catch (__unused id e) { return NO; }
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static void SPAXLog(NSString *fmt, ...) {
    if (getenv("SPAX_DEBUG") == NULL) return;
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    fprintf(stderr, "[spax] %s\n", msg.UTF8String);
}

// Content identity for a serialized node: prefer the AX identifier, else fall
// back to label+role+rounded frame. Used to dedupe grid-discovered elements
// against the tree walk (separate objectAtPoint calls return fresh wrappers, so
// pointer identity cannot dedupe them).
static NSString *SPNodeKey(NSDictionary *node) {
    // Position-based identity. AXUniqueId is NOT unique (e.g. repeated "cell"
    // identifiers like "PinnedTile" across sibling buttons), so it must not be
    // the key — distinct elements at distinct frames are distinct nodes.
    NSDictionary *f = node[@"frame"];
    return [NSString stringWithFormat:@"%@|%@|%@|%.0f|%.0f|%.0f|%.0f",
            node[@"AXLabel"], node[@"AXUniqueId"], node[@"type"],
            [f[@"x"] doubleValue], [f[@"y"] doubleValue],
            [f[@"width"] doubleValue], [f[@"height"] doubleValue]];
}

static BOOL SPFrameContainsPoint(NSDictionary *f, CGPoint p) {
    CGFloat x = [f[@"x"] doubleValue], y = [f[@"y"] doubleValue];
    CGFloat w = [f[@"width"] doubleValue], h = [f[@"height"] doubleValue];
    return p.x >= x && p.x < x + w && p.y >= y && p.y < y + h;
}

// A node's frame may suppress future grid probes only if it is a small leaf:
// containers and full-screen-ish elements must keep probing their interior so
// distinct sibling/overlay elements are still hit-tested.
static BOOL SPIsCoverable(NSDictionary *node, CGFloat screenArea) {
    if ([node[@"children"] count] != 0) return NO;
    NSDictionary *f = node[@"frame"];
    CGFloat area = [f[@"width"] doubleValue] * [f[@"height"] doubleValue];
    // Only genuinely small leaves (buttons, labels, annotations) suppress
    // probing. A mid-size leaf can be a hit-test container whose visual children
    // are reachable only point-by-point, so it must not blank out its interior.
    (void)screenArea;
    return area > 0 && area < 20000; // ~141x141 pt
}

@implementation SPAccessibilityBridge {
    id _translator;
    dispatch_queue_t _queue;            // serial completion queue for the async transport
    NSLock *_lock;
    NSMutableDictionary<NSString *, id> *_tokenToDevice;
    BOOL _loaded;
}

+ (instancetype)shared {
    static SPAccessibilityBridge *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SPAccessibilityBridge new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.simpilot.ax.transport", DISPATCH_QUEUE_SERIAL);
        _lock = [NSLock new];
        _tokenToDevice = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)emptyResponse {
    Class responseClass = NSClassFromString(@"AXPTranslatorResponse");
    SEL sel = NSSelectorFromString(@"emptyResponse");
    if (responseClass && [responseClass respondsToSelector:sel]) {
        return ((id (*)(id, SEL))objc_msgSend)(responseClass, sel);
    }
    return nil;
}

- (BOOL)ensureLoaded:(NSError **)error {
    if (_loaded) return YES;
    if (!SPDlopen(kAccessibilityPlatformTranslationPath, @"AccessibilityPlatformTranslation", error)) {
        return NO;
    }
    Class translatorClass = NSClassFromString(@"AXPTranslator");
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (translatorClass == nil || ![translatorClass respondsToSelector:sharedSel]) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:20 userInfo:@{
            NSLocalizedDescriptionKey: @"AXPTranslator/sharedInstance unavailable"}];
        return NO;
    }
    id translator = ((id (*)(id, SEL))objc_msgSend)(translatorClass, sharedSel);
    if (translator == nil) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:21 userInfo:@{
            NSLocalizedDescriptionKey: @"AXPTranslator sharedInstance returned nil"}];
        return NO;
    }
    // Configuration is done via KVC (the reference binary uses setValue:forKey:,
    // not the bridge*Delegate setters).
    [translator setValue:self forKey:@"bridgeTokenDelegate"];
    [translator setValue:@YES forKey:@"supportsDelegateTokens"];
    [translator setValue:@YES forKey:@"accessibilityEnabled"];
    _translator = translator;
    _loaded = YES;
    SPAXLog(@"ensureLoaded: translator=%@ bridgeTokenDelegate=%@ supportsDelegateTokens=%@",
            NSStringFromClass(object_getClass(translator)),
            [translator valueForKey:@"bridgeTokenDelegate"],
            [translator valueForKey:@"supportsDelegateTokens"]);
    return YES;
}

#pragma mark AXPTranslationTokenDelegateHelper

- (id)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token {
    __weak SPAccessibilityBridge *weakSelf = self;
    id (^callback)(id) = ^id(id request) {
        SPAccessibilityBridge *strongSelf = weakSelf;
        if (strongSelf == nil) return nil;
        id device = nil;
        [strongSelf->_lock lock];
        device = strongSelf->_tokenToDevice[token];
        [strongSelf->_lock unlock];
        if (device == nil) return [strongSelf emptyResponse];
        return [strongSelf runRequest:request onDevice:device];
    };
    return callback;
}

- (id)accessibilityTranslationRootParentWithToken:(NSString *)token {
    return nil;
}

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token {
    return rect; // identity, matching the reference implementation
}

#pragma mark Transport

- (id)runRequest:(id)request onDevice:(id)device {
    SEL transport = NSSelectorFromString(@"sendAccessibilityRequestAsync:completionQueue:completionHandler:");
    if (![device respondsToSelector:transport]) return [self emptyResponse];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block id result = nil;
    void (^handler)(id) = ^(id response) {
        result = response;
        dispatch_semaphore_signal(sem);
    };
    ((void (*)(id, SEL, id, dispatch_queue_t, id))objc_msgSend)(device, transport, request, _queue, handler);

    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))) != 0) {
        SPAXLog(@"runRequest: timed out waiting for SimDevice accessibility response");
        return [self emptyResponse];
    }
    return result ?: [self emptyResponse];
}

#pragma mark Tree

- (CGRect)frameOf:(id)element {
    SEL sel = NSSelectorFromString(@"accessibilityFrame");
    if (![element respondsToSelector:sel]) return CGRectZero;
    return ((CGRect (*)(id, SEL))objc_msgSend)(element, sel);
}

- (nullable NSDictionary<NSString *, id> *)serializeElement:(id)element
                                                    visited:(NSMutableSet *)visited
                                                  remaining:(NSInteger *)remaining
                                                      depth:(NSInteger)depth {
    if (element == nil) return nil;
    if (*remaining <= 0) return nil;
    if (depth > 80) return nil;
    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)element];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];
    (*remaining)--;

    NSMutableDictionary<NSString *, id> *node = [NSMutableDictionary dictionary];
    node[@"AXLabel"] = SPAXString(element, @"accessibilityLabel") ?: @"";
    node[@"AXValue"] = SPAXString(element, @"accessibilityValue") ?: @"";
    node[@"role_description"] = SPAXString(element, @"accessibilityRoleDescription") ?: @"";
    NSString *role = SPAXString(element, @"accessibilityRole") ?: @"";
    if ([role hasPrefix:@"AX"]) role = [role substringFromIndex:2];
    node[@"type"] = role;
    node[@"AXUniqueId"] = SPAXString(element, @"accessibilityIdentifier") ?: @"";
    node[@"enabled"] = @(SPAXBool(element, @"accessibilityEnabled"));

    CGRect frame = [self frameOf:element];
    node[@"frame"] = @{ @"x": @(frame.origin.x), @"y": @(frame.origin.y),
                        @"width": @(frame.size.width), @"height": @(frame.size.height) };

    NSMutableArray *children = [NSMutableArray array];
    id rawChildren = nil;
    @try { rawChildren = [element valueForKey:@"accessibilityChildren"]; } @catch (__unused id e) {}
    if ([rawChildren isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)rawChildren) {
            if (*remaining <= 0) break;
            NSDictionary *childNode = [self serializeElement:child visited:visited remaining:remaining depth:depth + 1];
            if (childNode) [children addObject:childNode];
        }
    }
    node[@"children"] = children;
    return node;
}

// Index an already-serialized node tree: record content keys (for dedupe) and
// frames (for grid coverage). Full-screen-ish containers are excluded from
// coverage so the grid still probes open areas they nominally "cover".
- (void)indexNode:(NSDictionary *)node
             keys:(NSMutableSet *)keys
          covered:(NSMutableArray<NSDictionary *> *)covered
       screenArea:(CGFloat)screenArea {
    [keys addObject:SPNodeKey(node)];
    if (SPIsCoverable(node, screenArea)) [covered addObject:node[@"frame"]];
    for (NSDictionary *child in node[@"children"]) {
        [self indexNode:child keys:keys covered:covered screenArea:screenArea];
    }
}

// serve-sim's discoverByGrid: many on-screen elements (status bar, map
// annotations, overlays from other processes) are not reachable through the
// frontmost app's accessibilityChildren tree. Hit-test a 16pt grid via
// objectAtPoint: to surface them, deduped against the tree walk.
- (void)discoverByGridForToken:(NSString *)token
                        screen:(CGRect)screen
                          into:(NSMutableArray *)rootChildren
                       visited:(NSMutableSet *)visited
                     remaining:(NSInteger *)remaining {
    SEL atPoint = NSSelectorFromString(@"objectAtPoint:displayId:bridgeDelegateToken:");
    SEL convert = NSSelectorFromString(@"macPlatformElementFromTranslation:");
    if (![_translator respondsToSelector:atPoint]) return;

    CGFloat screenArea = screen.size.width * screen.size.height;
    NSMutableSet *seenKeys = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *covered = [NSMutableArray array];
    for (NSDictionary *n in rootChildren) {
        [self indexNode:n keys:seenKeys covered:covered screenArea:screenArea];
    }

    const CGFloat step = 16.0; // matches the reference binary's grid pitch
    for (CGFloat y = screen.origin.y; y <= CGRectGetMaxY(screen) && *remaining > 0; y += step) {
        for (CGFloat x = screen.origin.x; x <= CGRectGetMaxX(screen) && *remaining > 0; x += step) {
            CGPoint p = CGPointMake(x, y);
            BOOL skip = NO;
            for (NSDictionary *f in covered) { if (SPFrameContainsPoint(f, p)) { skip = YES; break; } }
            if (skip) continue;

            id translation = ((id (*)(id, SEL, CGPoint, NSUInteger, id))objc_msgSend)(_translator, atPoint, p, (NSUInteger)0, token);
            if (translation == nil) continue;
            id el = [_translator respondsToSelector:convert]
                ? ((id (*)(id, SEL, id))objc_msgSend)(_translator, convert, translation)
                : translation;
            if (el == nil) continue;

            NSDictionary *node = [self serializeElement:el visited:visited remaining:remaining depth:0];
            if (node == nil) continue;
            NSString *key = SPNodeKey(node);
            if ([seenKeys containsObject:key]) {
                if (SPIsCoverable(node, screenArea)) [covered addObject:node[@"frame"]];
                continue;
            }
            [rootChildren addObject:node];
            [self indexNode:node keys:seenKeys covered:covered screenArea:screenArea];
        }
    }
    SPAXLog(@"discoverByGrid: rootChildren now %lu", (unsigned long)rootChildren.count);
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)treeForUDID:(NSString *)udid
                                                     developerDir:(NSString *)developerDir
                                                            error:(NSError **)error {
    if (![self ensureLoaded:error]) return nil;

    id device = SPCopySimDeviceForUDID(udid, developerDir, error);
    if (device == nil) return nil;

    SEL transport = NSSelectorFromString(@"sendAccessibilityRequestAsync:completionQueue:completionHandler:");
    if (![device respondsToSelector:transport]) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:23 userInfo:@{
            NSLocalizedDescriptionKey: @"SimDevice lacks sendAccessibilityRequestAsync"}];
        return nil;
    }

    NSString *token = [[NSUUID UUID] UUIDString];
    [_lock lock];
    _tokenToDevice[token] = device;
    [_lock unlock];

    @try {
        SEL frontmost = NSSelectorFromString(@"frontmostApplicationWithDisplayId:bridgeDelegateToken:");
        id translation = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(_translator, frontmost, (NSUInteger)0, token);
        if (translation == nil) {
            if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:24 userInfo:@{
                NSLocalizedDescriptionKey: @"frontmostApplicationWithDisplayId returned nil"}];
            return nil;
        }
        // frontmostApplicationWithDisplayId returns an AXPTranslationObject; turn
        // it into an NSAccessibility-walkable AXPMacPlatformElement.
        id root = translation;
        SEL convert = NSSelectorFromString(@"macPlatformElementFromTranslation:");
        if ([_translator respondsToSelector:convert]) {
            root = ((id (*)(id, SEL, id))objc_msgSend)(_translator, convert, translation);
        }
        if (root == nil) {
            if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:25 userInfo:@{
                NSLocalizedDescriptionKey: @"macPlatformElementFromTranslation returned nil"}];
            return nil;
        }
        NSMutableSet *visited = [NSMutableSet set];
        NSInteger remaining = 5000;
        NSMutableDictionary *rootNode = (NSMutableDictionary *)[self serializeElement:root visited:visited remaining:&remaining depth:0];
        if (rootNode == nil) return @[];
        // Augment the tree walk with grid-discovered elements (status bar, map
        // annotations, cross-process overlays) the accessibilityChildren tree misses.
        NSMutableArray *rootChildren = rootNode[@"children"];
        if ([rootChildren isKindOfClass:NSMutableArray.class]) {
            [self discoverByGridForToken:token screen:[self frameOf:root]
                                    into:rootChildren visited:visited remaining:&remaining];
        }
        return @[rootNode];
    } @finally {
        [_lock lock];
        [_tokenToDevice removeObjectForKey:token];
        [_lock unlock];
    }
}

@end

#pragma mark - In-process HID injection (SimulatorKit Indigo + SimDeviceLegacyHIDClient)
//
// Independent reimplementation of serve-sim's HIDInjector against the same Apple
// private APIs. Recipe (recovered by disassembly of the reference binary):
//   setup:  dlopen CoreSimulator + SimulatorKit; find SimDevice; dlsym the Indigo
//           message builders from SimulatorKit; create SimDeviceLegacyHIDClient
//           via -initWithDevice:error:; cache selector
//           sendWithMessage:freeWhenDone:completionQueue:completion:.
//   touch:  IndigoHIDMessageForMouseNSEvent(&pt, NULL, 50, phase, 1, 1, edge),
//           phase begin/move=1, end=2; send (freeWhenDone:YES).
//   button: IndigoHIDMessageForButton(source, direction, 0x33), press=1 then 2.

typedef void * (*SPIndigoMouseFunc)(CGPoint *, CGPoint *, uint32_t, int32_t, CGFloat, CGFloat, uint32_t);
typedef void * (*SPIndigoButtonFunc)(int32_t, int32_t, int32_t);
typedef void * (*SPIndigoKeyboardFunc)(uint32_t, uint32_t);
typedef void * (*SPIndigoCrownFunc)(double);

@implementation SPHIDInjector {
    id _simDevice;
    id _hidClient;
    SEL _sendSel;
    SPIndigoMouseFunc _mouseFunc;
    SPIndigoButtonFunc _buttonFunc;
    SPIndigoKeyboardFunc _keyboardFunc;
    SPIndigoCrownFunc _crownFunc;
    NSString *_loadedUDID;
}

+ (instancetype)shared {
    static SPHIDInjector *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SPHIDInjector new]; });
    return shared;
}

- (BOOL)setupForUDID:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    if (_hidClient != nil && [_loadedUDID isEqualToString:udid]) return YES;

    NSError *e = nil;
    if (!SPDlopen(kCoreSimulatorPath, @"CoreSimulator", &e)) { if (error) *error = e; return NO; }
    NSString *simKitPath = [developerDir stringByAppendingPathComponent:
                            @"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"];
    if (!SPDlopen(simKitPath, @"SimulatorKit", &e)) { if (error) *error = e; return NO; }

    id device = SPCopySimDeviceForUDID(udid, developerDir, error);
    if (device == nil) return NO;

    // Indigo message builders are exported C symbols once SimulatorKit is loaded.
    _mouseFunc = (SPIndigoMouseFunc)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForMouseNSEvent");
    _buttonFunc = (SPIndigoButtonFunc)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForButton");
    _keyboardFunc = (SPIndigoKeyboardFunc)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForKeyboardArbitrary");
    _crownFunc = (SPIndigoCrownFunc)dlsym(RTLD_DEFAULT, "IndigoHIDMessageForDigitalCrownEvent");
    if (_mouseFunc == NULL) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:30 userInfo:@{
            NSLocalizedDescriptionKey: @"IndigoHIDMessageForMouseNSEvent not found"}];
        return NO;
    }

    Class clientClass = NSClassFromString(@"_TtC12SimulatorKit24SimDeviceLegacyHIDClient");
    if (clientClass == nil) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:31 userInfo:@{
            NSLocalizedDescriptionKey: @"SimDeviceLegacyHIDClient not found"}];
        return NO;
    }
    id client = ((id (*)(id, SEL))objc_msgSend)(clientClass, @selector(alloc));
    SEL initSel = NSSelectorFromString(@"initWithDevice:error:");
    NSError *initError = nil;
    client = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(client, initSel, device, &initError);
    if (client == nil || initError != nil) {
        if (error) *error = initError ?: [NSError errorWithDomain:kBridgeErrorDomain code:32 userInfo:@{
            NSLocalizedDescriptionKey: @"SimDeviceLegacyHIDClient init failed"}];
        return NO;
    }

    _simDevice = device;
    _hidClient = client;
    _sendSel = NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    _loadedUDID = [udid copy];
    return YES;
}

- (void)sendMessage:(void *)message {
    if (message == NULL) return;
    if (_hidClient == nil || _sendSel == NULL) { free(message); return; }
    // freeWhenDone:YES — the client takes ownership and frees the message.
    ((void (*)(id, SEL, void *, BOOL, id, id))objc_msgSend)(_hidClient, _sendSel, message, YES, nil, nil);
}

- (void)sendTouchPhase:(int32_t)phase x:(double)x y:(double)y edge:(uint32_t)edge {
    if (_mouseFunc == NULL) return;
    CGPoint point = CGPointMake(x, y);
    void *message = _mouseFunc(&point, NULL, 50, phase, 1.0, 1.0, edge);
    [self sendMessage:message];
}

- (void)tapAbsoluteX:(double)x y:(double)y {
    [self sendTouchPhase:1 x:x y:y edge:0]; // begin
    usleep(40 * 1000);
    [self sendTouchPhase:2 x:x y:y edge:0]; // end
}

- (void)sendHIDButtonSource:(int32_t)source direction:(int32_t)direction {
    if (_buttonFunc == NULL) return;
    void *message = _buttonFunc(source, direction, 0x33);
    [self sendMessage:message];
}

- (void)swipeHome {
    // Edge-swipe up from the bottom (the reference binary's gesture path):
    // begin near the bottom, interpolate up, end mid-screen, all with edge=3.
    const uint32_t edge = 3;
    const double x = 0.5, y0 = 0.95, y1 = 0.35;
    [self sendTouchPhase:1 x:x y:y0 edge:edge];
    for (int i = 1; i <= 10; i++) {
        double t = (double)i / 10.0;
        [self sendTouchPhase:1 x:x y:(y0 + (y1 - y0) * t) edge:edge];
        usleep(8 * 1000);
    }
    [self sendTouchPhase:2 x:x y:y1 edge:edge];
}

- (BOOL)pressButton:(NSString *)name {
    // direction 1 = press, 2 = the reference binary's follow-up code.
    if ([name isEqualToString:@"home"]) {
        [self sendHIDButtonSource:0 direction:1];
        [self sendHIDButtonSource:0 direction:2];
        return YES;
    }
    if ([name isEqualToString:@"swipe_home"]) {
        [self swipeHome];
        return YES;
    }
    if ([name isEqualToString:@"lock"]) {
        [self sendHIDButtonSource:1 direction:1];
        [self sendHIDButtonSource:1 direction:2];
        return YES;
    }
    if ([name isEqualToString:@"side_button"]) {
        [self sendHIDButtonSource:3000 direction:1];
        [self sendHIDButtonSource:3000 direction:2];
        return YES;
    }
    if ([name isEqualToString:@"app_switcher"]) {
        // Double-press Home (the reference binary's app-switcher gesture).
        [self sendHIDButtonSource:0 direction:1];
        [self sendHIDButtonSource:0 direction:2];
        usleep(150 * 1000);
        [self sendHIDButtonSource:0 direction:1];
        [self sendHIDButtonSource:0 direction:2];
        return YES;
    }
    if ([name isEqualToString:@"siri"]) {
        // Press-and-hold the Siri button code.
        [self sendHIDButtonSource:0x400002 direction:1];
        usleep(300 * 1000);
        [self sendHIDButtonSource:0x400002 direction:2];
        return YES;
    }
    return NO;
}

// Keyboard: keyboardFunc(usage, isDown). HID usage codes per the USB HID spec.
- (void)sendKeyUsage:(uint32_t)usage down:(BOOL)down {
    if (_keyboardFunc == NULL) return;
    void *message = _keyboardFunc(usage, down ? 1 : 2);
    [self sendMessage:message];
}

// Digital Crown (Apple Watch simulators only). Delta is passed through unscaled.
- (void)sendDigitalCrown:(double)delta {
    if (_crownFunc == NULL || delta != delta) return; // NaN guard
    void *message = _crownFunc(delta);
    [self sendMessage:message];
}

// Two-finger touch (e.g. pinch): one message carries both points, flags 0x32.
- (void)sendMultiTouchPhase:(int32_t)phase x1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 {
    if (_mouseFunc == NULL) return;
    CGPoint p1 = CGPointMake(x1, y1);
    CGPoint p2 = CGPointMake(x2, y2);
    void *message = _mouseFunc(&p1, &p2, 0x32, phase, 1.0, 1.0, 0);
    [self sendMessage:message];
}

@end

#pragma mark - Framebuffer mirror (SimulatorKit display descriptor + IOSurface)
//
// Independent reimplementation of serve-sim's FrameCapture against the same
// Apple private APIs. Recipe (recovered by disassembly of the reference binary):
//   wire-up: io = [device io]; [io updateIOPorts]; ports = [io valueForKey:@"deviceIOPorts"];
//            keep ports whose -portIdentifier == "com.apple.framebuffer.display", take -descriptor.
//   register: -registerScreenCallbacksWithUUID:callbackQueue:frameCallback:
//             surfacesChangedCallback:propertiesChangedCallback: — the callbacks are bare
//             () -> () pings that schedule a capture.
//   capture: surface = [descriptor framebufferSurface] (IOSurface); dedupe via IOSurfaceGetSeed;
//            render zero-copy by assigning the IOSurface to a CALayer's contents.

static id SPPerformNoArg(id target, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

// A clickable mirror: maps mouse clicks/drags over the aspect-fit framebuffer to
// normalized 0...1 simulator coordinates and drives HID touch phases — so clicking
// the mirror taps the device, and dragging swipes.
@interface SPMirrorView : NSView
@property (nonatomic, copy) NSString *udid;
@property (nonatomic, copy) NSString *developerDir;
@property (nonatomic) double surfaceWidth;
@property (nonatomic) double surfaceHeight;
@end

@implementation SPMirrorView {
    dispatch_queue_t _hidQueue;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _hidQueue = dispatch_queue_create("com.simpilot.mirror.hid", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

// Normalized 0...1 point inside the aspect-fit surface rect, or {-1,-1} if the
// click is in the letterbox or the surface size isn't known yet.
- (CGPoint)normalizedPointForEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    double vw = self.bounds.size.width, vh = self.bounds.size.height;
    double sw = _surfaceWidth, sh = _surfaceHeight;
    if (vw < 1 || vh < 1 || sw < 1 || sh < 1) return CGPointMake(-1, -1);
    double scale = MIN(vw / sw, vh / sh);
    double dw = sw * scale, dh = sh * scale;
    double ox = (vw - dw) / 2.0, oy = (vh - dh) / 2.0;
    double nx = (p.x - ox) / dw;
    double nyFromBottom = (p.y - oy) / dh;
    double ny = 1.0 - nyFromBottom; // NSView is bottom-left; the simulator is top-left
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return CGPointMake(-1, -1);
    return CGPointMake(nx, ny);
}

- (void)sendTouchPhase:(NSInteger)phase forEvent:(NSEvent *)event {
    CGPoint n = [self normalizedPointForEvent:event];
    if (n.x < 0) return;
    NSString *udid = self.udid, *developerDir = self.developerDir;
    if (udid.length == 0) return;
    dispatch_async(_hidQueue, ^{
        [SPSimBridge touchUDID:udid phase:phase normalizedX:n.x y:n.y developerDir:developerDir error:NULL];
    });
}

- (void)mouseDown:(NSEvent *)event { [self sendTouchPhase:1 forEvent:event]; }    // begin
- (void)mouseDragged:(NSEvent *)event { [self sendTouchPhase:1 forEvent:event]; } // move
- (void)mouseUp:(NSEvent *)event { [self sendTouchPhase:2 forEvent:event]; }      // end

@end

@implementation SPFrameCapture {
    id _ioClient;
    NSMutableArray *_descriptors;
    NSMutableArray *_registrations; // @[descriptor, uuid] pairs, for unregister on stop
    dispatch_queue_t _queue;
    SPMirrorView *_view;
    NSString *_udid;
    NSString *_developerDir;
    dispatch_source_t _idleTimer;   // created/cancelled/niled only on _queue
    uint32_t _lastSeed;
    BOOL _hasSeed;
    BOOL _running;                  // mutated only on _queue
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.simpilot.framecapture", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)wireUpForUDID:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    _udid = [udid copy];
    _developerDir = [developerDir copy];
    NSError *e = nil;
    if (!SPDlopen(kCoreSimulatorPath, @"CoreSimulator", &e)) { if (error) *error = e; return NO; }
    NSString *simKitPath = [developerDir stringByAppendingPathComponent:
                            @"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"];
    if (!SPDlopen(simKitPath, @"SimulatorKit", &e)) { if (error) *error = e; return NO; }

    id device = SPCopySimDeviceForUDID(udid, developerDir, error);
    if (device == nil) return NO;

    _ioClient = SPPerformNoArg(device, @"io");
    if (_ioClient == nil) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:40 userInfo:@{
            NSLocalizedDescriptionKey: @"SimDevice -io returned nil"}];
        return NO;
    }
    SEL updatePorts = NSSelectorFromString(@"updateIOPorts");
    if ([_ioClient respondsToSelector:updatePorts]) ((void (*)(id, SEL))objc_msgSend)(_ioClient, updatePorts);

    id ports = nil;
    @try { ports = [_ioClient valueForKey:@"deviceIOPorts"]; } @catch (__unused id ex) {}
    if (![ports isKindOfClass:NSArray.class]) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:41 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to get IO ports"}];
        return NO;
    }

    SEL framebufferSurfaceSel = NSSelectorFromString(@"framebufferSurface");
    _descriptors = [NSMutableArray array];
    for (id port in (NSArray *)ports) {
        id identifier = SPPerformNoArg(port, @"portIdentifier");
        if (![identifier isKindOfClass:NSString.class] ||
            ![(NSString *)identifier isEqualToString:@"com.apple.framebuffer.display"]) continue;
        id descriptor = SPPerformNoArg(port, @"descriptor");
        if (descriptor != nil && [descriptor respondsToSelector:framebufferSurfaceSel]) {
            [_descriptors addObject:descriptor];
        }
    }
    if (_descriptors.count == 0) {
        if (error) *error = [NSError errorWithDomain:kBridgeErrorDomain code:42 userInfo:@{
            NSLocalizedDescriptionKey: @"No framebuffer display descriptor found"}];
        return NO;
    }
    return YES;
}

// Among the framebuffer descriptors, the live IOSurface with the largest area.
- (IOSurfaceRef)currentSurface {
    SEL sel = NSSelectorFromString(@"framebufferSurface");
    IOSurfaceRef best = NULL;
    size_t bestArea = 0;
    for (id descriptor in _descriptors) {
        if (![descriptor respondsToSelector:sel]) continue;
        IOSurfaceRef surface = ((IOSurfaceRef (*)(id, SEL))objc_msgSend)(descriptor, sel);
        if (surface == NULL) continue;
        size_t area = IOSurfaceGetWidth(surface) * IOSurfaceGetHeight(surface);
        if (area > bestArea) { bestArea = area; best = surface; }
    }
    return best;
}

- (nullable NSView *)startMirrorForUDID:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    if (![self wireUpForUDID:udid developerDir:developerDir error:error]) return nil;
    return [self makeMirrorView];
}

// Must be called on the main thread (creates an NSView); assumes wireUp succeeded.
- (nullable NSView *)makeMirrorView {
    if (_descriptors.count == 0) return nil;
    SPMirrorView *view = [[SPMirrorView alloc] initWithFrame:NSMakeRect(0, 0, 390, 844)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = NSColor.blackColor.CGColor;
    view.layer.contentsGravity = kCAGravityResizeAspect;
    view.udid = _udid;
    view.developerDir = _developerDir;
    _view = view;

    // Confine all capture-state mutation to _queue (stop() does the same), so
    // _running/_lastSeed/_idleTimer are single-threaded with no lock.
    dispatch_async(_queue, ^{
        self->_running = YES;
        [self registerCallbacks];
        [self captureFrame];
        [self startIdleTimer];
    });
    return _view;
}

- (void)registerCallbacks {
    SEL sel = NSSelectorFromString(@"registerScreenCallbacksWithUUID:callbackQueue:frameCallback:"
                                   @"surfacesChangedCallback:propertiesChangedCallback:");
    _registrations = [NSMutableArray array];
    __weak SPFrameCapture *weakSelf = self;
    void (^ping)(void) = ^{
        SPFrameCapture *strongSelf = weakSelf;
        if (strongSelf != nil) dispatch_async(strongSelf->_queue, ^{ [strongSelf captureFrame]; });
    };
    void (^noop)(void) = ^{};
    for (id descriptor in _descriptors) {
        if (![descriptor respondsToSelector:sel]) continue;
        NSUUID *uuid = [NSUUID UUID];
        ((void (*)(id, SEL, id, dispatch_queue_t, id, id, id))objc_msgSend)(
            descriptor, sel, uuid, _queue, ping, ping, noop);
        [_registrations addObject:@[descriptor, uuid]];
    }
}

// Best-effort: unregister the screen callbacks we registered so the descriptor
// stops pinging after capture ends. Guarded — the selector is only sent if present.
- (void)unregisterCallbacks {
    SEL sel = NSSelectorFromString(@"unregisterScreenCallbacksWithUUID:");
    for (NSArray *registration in _registrations) {
        id descriptor = registration.firstObject;
        id uuid = registration.lastObject;
        if ([descriptor respondsToSelector:sel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(descriptor, sel, uuid);
        }
    }
    [_registrations removeAllObjects];
}

- (void)captureFrame {
    if (!_running) return;
    IOSurfaceRef surface = [self currentSurface];
    if (surface == NULL) return;
    uint32_t seed = IOSurfaceGetSeed(surface);
    if (_hasSeed && seed == _lastSeed) return; // unchanged frame
    _lastSeed = seed;
    _hasSeed = YES;
    size_t width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface);
    if (width < 1 || height < 1) return;

    IOSurfaceRef retained = (IOSurfaceRef)CFRetain(surface);
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_view.surfaceWidth = (double)width;   // for click->normalized mapping
        self->_view.surfaceHeight = (double)height;
        self->_view.layer.contents = (__bridge id)retained; // zero-copy display
        CFRelease(retained);
    });
}

- (void)startIdleTimer {
    _idleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_idleTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              200 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
    __weak SPFrameCapture *weakSelf = self;
    dispatch_source_set_event_handler(_idleTimer, ^{ [weakSelf captureFrame]; });
    dispatch_resume(_idleTimer);
}

- (void)stop {
    // Tear down on _queue so _running/_idleTimer are only ever touched there
    // (captureFrame runs on _queue), avoiding a data race with the main thread.
    dispatch_async(_queue, ^{
        self->_running = NO;
        [self unregisterCallbacks];
        if (self->_idleTimer != NULL) {
            dispatch_source_cancel(self->_idleTimer);
            self->_idleTimer = NULL;
        }
    });
}

- (void)dealloc {
    // The timer/callbacks capture weakSelf, and any in-flight capture captures
    // self strongly — so by dealloc nothing else touches these. Cancel directly
    // (cannot dispatch capturing self here) so the timer source is released.
    if (_idleTimer != NULL) {
        dispatch_source_cancel(_idleTimer);
        _idleTimer = NULL;
    }
    [self unregisterCallbacks];
}

- (nullable CGImageRef)copyCurrentCGImage {
    IOSurfaceRef surface = [self currentSurface];
    if (surface == NULL) return NULL;
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    CIImage *image = [CIImage imageWithIOSurface:surface];
    CGImageRef cgImage = NULL;
    if (image != nil) {
        CIContext *context = [CIContext context];
        cgImage = [context createCGImage:image fromRect:image.extent];
    }
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    return cgImage;
}

@end

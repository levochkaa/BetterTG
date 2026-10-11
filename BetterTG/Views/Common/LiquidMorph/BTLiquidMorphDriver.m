// BTLiquidMorphDriver.m

// Port of Telegram iOS 7c2cfd6a1f
// submodules/TelegramUI/Components/LensTransition/Bridge/Sources/LensTransitionRuntime.m, with BetterTG names.
// No mangled-name lookup, dlsym, private memory offsets or copied Swift layouts: only Objective-C runtime calls whose
// complete signatures are checked first.

#import "BTLiquidMorphDriver.h"
#import "BTLiquidMorphIdentifiers.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Volatile encoded bytes keep optimized builds from folding decoded names into string or selector sections.
__attribute__((noinline)) static NSString *BTName(BTKey key) {
    char bytes[64];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) {
        bytes[i] = (char)(BTNames[key][i] ^ 0xa7);
        if (bytes[i] == 0) break;
    }
    return [NSString stringWithUTF8String:bytes];
}

static SEL BTSelector(BTKey key) {
    return NSSelectorFromString(BTName(key));
}

@interface BTLiquidMorphState : NSObject {
@public
    UITargetedPreview *origin;
    UITargetedPreview *destination;
    UITargetedPreview *pivot;
    UIView *host;
    UIView *detached;
    UIView *menu;
    void (^animations)(void);
    void (^completion)(void);
}
@end

@implementation BTLiquidMorphState
@end

static char BTStateKey;

static BTLiquidMorphState *BTState(id object) {
    return objc_getAssociatedObject(object, &BTStateKey);
}

static void BTAttach(id object, BTLiquidMorphState *state) {
    objc_setAssociatedObject(object, &BTStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id BTGetOrigin(id object, SEL selector) { return BTState(object)->origin; }
static id BTGetPivot(id object, SEL selector) { return BTState(object)->pivot; }
static id BTGetDestination(id object, SEL selector) { return BTState(object)->destination; }
static id BTGetHost(id object, SEL selector) { return BTState(object)->host; }
static id BTGetDetached(id object, SEL selector) { return BTState(object)->detached; }
static id BTGetMenu(id object, SEL selector) { return BTState(object)->menu; }
static id BTNil(id object, SEL selector) { return nil; }
static id BTEmpty(id object, SEL selector) { return @[]; }
static BOOL BTYes(id object, SEL selector) { return YES; }
static BOOL BTNo(id object, SEL selector) { return NO; }
static void BTIgnore(id object, SEL selector) {}
static void BTIgnoreBackground(id object, SEL selector, BOOL visible) {}

static void BTFinish(id object, SEL selector) {
    BTLiquidMorphState *state = BTState(object);
    void (^block)(void) = state->completion;
    state->completion = nil;
    state->animations = nil;
    if (block) block();
}

static void BTAnimate(id object, SEL selector) {
    void (^block)(void) = BTState(object)->animations;
    if (block) block();
}

// Compares complete ABI signatures, ignoring only numeric argument offsets.
static BOOL BTMatches(Class cls, BTKey key, const char *types) {
    Method method = class_getInstanceMethod(cls, BTSelector(key));
    if (!method) return NO;
    NSMethodSignature *actual = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSMethodSignature *expected = [NSMethodSignature signatureWithObjCTypes:types];
    if (strcmp(actual.methodReturnType, expected.methodReturnType) || actual.numberOfArguments != expected.numberOfArguments) {
        return NO;
    }
    for (NSUInteger i = 0; i < actual.numberOfArguments; i++) {
        if (strcmp([actual getArgumentTypeAtIndex:i], [expected getArgumentTypeAtIndex:i])) return NO;
    }
    return YES;
}

static Class BTCoordinatorClass, BTContextClass, BTMenuClass, BTActionsClass;

static BOOL BTAdd(Class cls, BTKey key, IMP imp, const char *types) {
    return class_addMethod(cls, BTSelector(key), imp, types);
}

static BOOL BTPrepare(void) {
    static dispatch_once_t once;
    static BOOL supported;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(BTName(BTCoordinator));
        struct {
            BTKey key;
            const char *types;
            IMP imp;
        } overrides[] = {
            {BTFrom, "@@:", (IMP)BTGetOrigin},
            {BTAttachment, "@@:", (IMP)BTGetOrigin},
            {BTPivot, "@@:", (IMP)BTGetPivot},
            {BTUsesDestination, "B@:", (IMP)BTYes},
            {BTContent, "@@:", (IMP)BTNil},
            {BTAccessories, "@@:", (IMP)BTEmpty},
            {BTDragging, "B@:", (IMP)BTNo},
            {BTBackground, "v@:B", (IMP)BTIgnoreBackground},
        };
        NSUInteger overrideCount = sizeof(overrides) / sizeof(overrides[0]);
        if (!base || !BTMatches(base, BTInitialize, "@@:@@") || !BTMatches(base, BTStart, "v@:") ||
            !BTMatches(base, BTAlongside, "v@:@") || !BTMatches(UIView.class, BTVisibility, "@@:d")) {
            return;
        }
        for (NSUInteger i = 0; i < overrideCount; i++) {
            if (!BTMatches(base, overrides[i].key, overrides[i].types)) return;
        }
        Class coordinator = objc_allocateClassPair(base, "BTLiquidMorphNativeTransition", 0);
        Class context = objc_allocateClassPair(NSObject.class, "BTLiquidMorphContext", 0);
        Class menu = objc_allocateClassPair(UIView.class, "BTLiquidMorphDestination", 0);
        Class actions = objc_allocateClassPair(NSObject.class, "BTLiquidMorphActions", 0);
        BOOL valid = coordinator && context && menu && actions;
        if (valid) {
            for (NSUInteger i = 0; i < overrideCount; i++) {
                valid &= BTAdd(coordinator, overrides[i].key, overrides[i].imp, overrides[i].types);
            }
            valid &= BTAdd(context, BTLayout, (IMP)BTNil, "@@:");
            valid &= BTAdd(context, BTFlock, (IMP)BTNil, "@@:");
            valid &= BTAdd(context, BTMenu, (IMP)BTGetMenu, "@@:");
            valid &= BTAdd(context, BTHost, (IMP)BTGetHost, "@@:");
            valid &= BTAdd(context, BTDetached, (IMP)BTGetDetached, "@@:");
            valid &= BTAdd(context, BTEndHiding, (IMP)BTIgnore, "v@:");
            valid &= BTAdd(menu, BTDestination, (IMP)BTGetDestination, "@@:");
            valid &= BTAdd(actions, BTRunAnimations, (IMP)BTAnimate, "v@:");
            valid &= BTAdd(actions, BTRunCompletions, (IMP)BTFinish, "v@:");
        }
        if (!valid) {
            if (coordinator) objc_disposeClassPair(coordinator);
            if (context) objc_disposeClassPair(context);
            if (menu) objc_disposeClassPair(menu);
            if (actions) objc_disposeClassPair(actions);
            return;
        }
        objc_registerClassPair(coordinator);
        objc_registerClassPair(context);
        objc_registerClassPair(menu);
        objc_registerClassPair(actions);
        BTCoordinatorClass = coordinator;
        BTContextClass = context;
        BTMenuClass = menu;
        BTActionsClass = actions;
        supported = YES;
    });
    return supported;
}

static NSMapTable<UIView *, BTLiquidMorphDriver *> *BTActiveTransitions;

@implementation BTLiquidMorphDriver {
    id _native;
    id _context;
    id _actions;
    BOOL _started;
}

+ (BOOL)isSupported {
    return BTPrepare();
}

+ (id)visibilityAssertionForView:(UIView *)view {
    if (!BTMatches(view.class, BTVisibility, "@@:d")) return nil;
    return ((id(*)(id, SEL, CGFloat))objc_msgSend)(view, BTSelector(BTVisibility), 0);
}

- (instancetype)initWithSource:(UITargetedPreview *)source
                   destination:(UITargetedPreview *)destination
                         pivot:(UITargetedPreview *)pivot
                     container:(UIView *)container
                sourceIdentity:(UIView *)sourceIdentity
                     alongside:(void (^)(void))alongside {
    NSAssert(NSThread.isMainThread, @"A liquid morph must be created on the main thread");
    if (!BTPrepare()) return nil;
    self = [super init];
    if (self) {
        BTLiquidMorphState *state = [BTLiquidMorphState new];
        state->origin = source;
        state->destination = destination;
        state->pivot = pivot;
        state->host = container;
        // Distinct from the source target's container, which selects UIKit's pivot path.
        state->detached = [UIView new];
        state->menu = [BTMenuClass new];
        // Separate state avoids a state -> menu -> state retain cycle.
        BTLiquidMorphState *menuState = [BTLiquidMorphState new];
        menuState->destination = destination;
        BTAttach(state->menu, menuState);
        state->animations = [alongside copy];
        _context = [BTContextClass new];
        BTAttach(_context, state);
        _actions = [BTActionsClass new];
        BTAttach(_actions, state);
        // Explicit init-family ownership across the dynamically resolved call.
        typedef id (*Initialize)(id __attribute__((ns_consumed)), SEL, id, id) __attribute__((ns_returns_retained));
        if (!BTActiveTransitions) BTActiveTransitions = [NSMapTable weakToWeakObjectsMapTable];
        UIView *identity = sourceIdentity ?: source.view;
        BTLiquidMorphDriver *previous = [BTActiveTransitions objectForKey:identity];
        id previousNative = previous && previous->_started && BTState(previous->_actions)->completion ? previous->_native : nil;
        _native = ((Initialize)objc_msgSend)([BTCoordinatorClass alloc], BTSelector(BTInitialize), _context, previousNative);
        if (!_native) return nil;
        // UIKit transfers the running morph, including its source-side portals, to the newer coordinator.
        [BTActiveTransitions setObject:self forKey:identity];
        if (!sourceIdentity) [BTActiveTransitions setObject:self forKey:destination.view];
        BTAttach(_native, state);
        ((void (*)(id, SEL, id))objc_msgSend)(_native, BTSelector(BTAlongside), _actions);
    }
    return self;
}

- (void)startWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread && !_started, @"A liquid morph starts once on the main thread");
    _started = YES;
    // Presentation semantics in both directions; a close reverses the previews. UIKit's dismissal mode would remove
    // the caller's host. Installed before starting: with animations disabled, the morph finishes synchronously.
    BTState(_actions)->completion = [completion copy];
    ((void (*)(id, SEL))objc_msgSend)(_native, BTSelector(BTStart));
}

@end

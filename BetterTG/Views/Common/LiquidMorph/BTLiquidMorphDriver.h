// BTLiquidMorphDriver.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Drives UIKit's own liquid morph between two targeted previews without a UIKit context-menu controller. Port of
/// Telegram iOS 7c2cfd6a1f LensTransitionRuntime (`LTTransitionDriver`): a dynamic subclass of the native
/// liquid-morph presentation animation, created with `initWithUIController:previousAnimation:` and started with
/// `performTransition`, whose source, pivot and accessory hooks are overridden. Every method it calls or overrides
/// is checked against its complete Objective-C signature first; otherwise `isSupported` is NO and callers keep
/// their own animation.
NS_SWIFT_UI_ACTOR
@interface BTLiquidMorphDriver : NSObject

+ (BOOL)isSupported;
/// UIView's alpha-override assertion: hides `view` while retained without touching its model alpha or hidden state.
+ (nullable id)visibilityAssertionForView:(UIView *)view;

- (nullable instancetype)initWithSource:(UITargetedPreview *)source
                            destination:(UITargetedPreview *)destination
                                  pivot:(UITargetedPreview *)pivot
                              container:(UIView *)container
                         sourceIdentity:(nullable UIView *)sourceIdentity
                              alongside:(nullable void (^)(void))alongside;
- (instancetype)init NS_UNAVAILABLE;
/// `completion` runs on the main thread before UIKit's own cleanup.
- (void)startWithCompletion:(void (^)(void))completion NS_SWIFT_DISABLE_ASYNC;

@end

NS_ASSUME_NONNULL_END

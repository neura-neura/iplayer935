#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, IPFadeCurve) { IPFadeCurveLinear, IPFadeCurveEqualPower };
/** Small persisted settings; gains are applied by the hardware audio engines. */
@interface IPCrossfade : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) BOOL enabled, manualSkip, automaticAdvance, sessionControl;
@property(nonatomic) double duration;
@property(nonatomic) IPFadeCurve curve;
@property(nonatomic) BOOL sessionSuspended;
@property(nonatomic,readonly) BOOL active;
- (BOOL)allowsAutomatic:(BOOL)automatic;
@end
void IPFadeGains(double progress, IPFadeCurve curve, float *outgoing, float *incoming);

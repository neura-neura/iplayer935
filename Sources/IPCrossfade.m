#import "IPCrossfade.h"
#include <math.h>
@interface IPCrossfade ()
@property(nonatomic,strong) NSUserDefaults *defaults;
@end
@implementation IPCrossfade
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if((self=[super init])){_defaults=defaults;[defaults registerDefaults:@{@"fade.enabled":@NO,@"fade.manual":@YES,@"fade.auto":@YES,@"fade.control":@YES,@"fade.duration":@4,@"fade.curve":@(IPFadeCurveEqualPower)}];}return self;
}
- (BOOL)enabled {return [self.defaults boolForKey:@"fade.enabled"];}
- (void)setEnabled:(BOOL)value {[self.defaults setBool:value forKey:@"fade.enabled"];}
- (BOOL)manualSkip {return [self.defaults boolForKey:@"fade.manual"];}
- (void)setManualSkip:(BOOL)value {[self.defaults setBool:value forKey:@"fade.manual"];}
- (BOOL)automaticAdvance {return [self.defaults boolForKey:@"fade.auto"];}
- (void)setAutomaticAdvance:(BOOL)value {[self.defaults setBool:value forKey:@"fade.auto"];}
- (BOOL)sessionControl {return [self.defaults boolForKey:@"fade.control"];}
- (void)setSessionControl:(BOOL)value {[self.defaults setBool:value forKey:@"fade.control"];if(!value)self.sessionSuspended=NO;}
- (double)duration {double d=[self.defaults doubleForKey:@"fade.duration"];return isfinite(d)?MAX(1,MIN(10,d)):4;}
- (void)setDuration:(double)value {[self.defaults setDouble:isfinite(value)?MAX(1,MIN(10,value)):4 forKey:@"fade.duration"];}
- (IPFadeCurve)curve {return [self.defaults integerForKey:@"fade.curve"]==IPFadeCurveLinear?IPFadeCurveLinear:IPFadeCurveEqualPower;}
- (void)setCurve:(IPFadeCurve)value {[self.defaults setInteger:value==IPFadeCurveLinear?IPFadeCurveLinear:IPFadeCurveEqualPower forKey:@"fade.curve"];}
- (BOOL)active {return self.enabled&&!self.sessionSuspended;}
- (BOOL)allowsAutomatic:(BOOL)automatic {return self.active&&(automatic?self.automaticAdvance:self.manualSkip);}
@end
void IPFadeGains(double progress, IPFadeCurve curve, float *outgoing, float *incoming) {
    double t=isfinite(progress)?MAX(0,MIN(1,progress)):0;
    if(outgoing)*outgoing=curve==IPFadeCurveEqualPower?cos(t*M_PI_2):1-t;
    if(incoming)*incoming=curve==IPFadeCurveEqualPower?sin(t*M_PI_2):t;
}

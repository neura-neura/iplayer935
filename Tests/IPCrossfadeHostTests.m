#import <Foundation/Foundation.h>
#import "IPCrossfade.h"
#include <math.h>
int main(){@autoreleasepool{
    NSString *suite=[@"org.neura.fade-test." stringByAppendingString:[NSUUID UUID].UUIDString];NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:suite];
    IPCrossfade *s=[[IPCrossfade alloc]initWithDefaults:defaults];
    NSCAssert(!s.active&&s.duration==4&&s.curve==IPFadeCurveEqualPower&&s.manualSkip&&s.automaticAdvance&&s.sessionControl,@"safe defaults failed");
    s.enabled=YES;NSCAssert([s allowsAutomatic:YES]&&[s allowsAutomatic:NO],@"enabled routes failed");
    s.manualSkip=NO;NSCAssert([s allowsAutomatic:YES]&&![s allowsAutomatic:NO],@"manual switch affects automatic advance");
    s.manualSkip=YES;s.automaticAdvance=NO;NSCAssert(![s allowsAutomatic:YES]&&[s allowsAutomatic:NO],@"automatic switch affects manual skip");
    s.sessionSuspended=YES;NSCAssert(!s.active&&![s allowsAutomatic:NO],@"session suspension failed");
    IPCrossfade *reopen=[[IPCrossfade alloc]initWithDefaults:defaults];NSCAssert(reopen.active&&!reopen.sessionSuspended&&!reopen.automaticAdvance,@"settings did not persist or session suspension persisted");
    s.sessionControl=NO;NSCAssert(!s.sessionSuspended,@"disabling gesture left crossfade suspended");
    s.duration=NAN;NSCAssert(s.duration==4,@"invalid duration escaped");s.duration=99;NSCAssert(s.duration==10,@"duration upper bound failed");s.duration=-2;NSCAssert(s.duration==1,@"duration lower bound failed");
    for(int curve=0;curve<2;curve++){float lastOut=1,lastIn=0;
        for(int i=0;i<=1000;i++){float out,in;IPFadeGains(i/1000.,curve,&out,&in);NSCAssert(out>=0&&out<=1&&in>=0&&in<=1&&out<=lastOut&&in>=lastIn,@"gain bounds or monotonicity failed");if(curve==IPFadeCurveEqualPower)NSCAssert(fabs(out*out+in*in-1)<.000001,@"equal-power energy changed");else NSCAssert(fabs(out+in-1)<.000001,@"linear gains changed");lastOut=out;lastIn=in;}
        NSCAssert(lastOut<.000001&&lastIn==1,@"fade did not finish at unity incoming");
    }
    float out,in;IPFadeGains(NAN,IPFadeCurveEqualPower,&out,&in);NSCAssert(out==1&&in==0,@"invalid progress created an audible jump");
    IPFadeGains(.5,IPFadeCurveEqualPower,&out,&in);NSCAssert(fabs(out-.70710678)<.000001&&fabs(in-.70710678)<.000001,@"equal-power midpoint failed");
    [defaults removePersistentDomainForName:suite];puts("Crossfade settings passed: persistent independent switches, transient session, duration limits, linear/equal-power energy, endpoints and monotonic gains");
}return 0;}

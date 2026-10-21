#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "IPPCMPlayer.h"
#include <stdlib.h>

struct IPFakeAudioQueue {
    AudioQueueOutputCallback callback; void *context;
    AudioQueueBufferRef allocated[3], pending[3];
    float volume; unsigned allocatedCount, count; BOOL running, disposed;
};
static AudioQueueRef latest;
static NSObject *queueLock;
OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *f, AudioQueueOutputCallback cb, void *ctx, void *rl, void *mode, UInt32 flags, AudioQueueRef *out) {
    (void)f;(void)rl;(void)mode;(void)flags;
    *out=calloc(1,sizeof(**out)); (*out)->callback=cb;(*out)->context=ctx; latest=*out;return 0;
}
OSStatus AudioQueueAllocateBuffer(AudioQueueRef q, UInt32 n, AudioQueueBufferRef *out) {
    *out=calloc(1,sizeof(**out)); (*out)->mAudioData=calloc(1,n);(*out)->mAudioDataBytesCapacity=n;
    q->allocated[q->allocatedCount++]=*out;return 0;
}
OSStatus AudioQueueFreeBuffer(AudioQueueRef q, AudioQueueBufferRef b) { (void)q;free(b->mAudioData);free(b);return 0; }
OSStatus AudioQueueEnqueueBuffer(AudioQueueRef q, AudioQueueBufferRef b, UInt32 n, const void *p) {
    (void)n;(void)p; @synchronized(queueLock) {
        NSCAssert(!q->disposed && q->count<3,@"invalid enqueue");
        for(unsigned i=0;i<q->count;i++) NSCAssert(q->pending[i]!=b,@"duplicate buffer enqueue");
        q->pending[q->count++]=b;
    }return 0;
}
OSStatus AudioQueueSetParameter(AudioQueueRef q,UInt32 parameter,float gain) {@synchronized(queueLock){NSCAssert(!q->disposed&&parameter==kAudioQueueParam_Volume,@"gain after dispose or wrong parameter");q->volume=gain;}return 0;}
OSStatus AudioQueueStart(AudioQueueRef q,const void *t) { (void)t;@synchronized(queueLock){NSCAssert(!q->disposed,@"start after dispose");q->running=YES;}return 0; }
OSStatus AudioQueuePause(AudioQueueRef q) { @synchronized(queueLock){NSCAssert(!q->disposed,@"pause after dispose");q->running=NO;}return 0; }
OSStatus AudioQueueStop(AudioQueueRef q,bool immediate) { @synchronized(queueLock){q->running=NO;if(immediate)q->count=0;}return 0; }
OSStatus AudioQueueReset(AudioQueueRef q) { @synchronized(queueLock){q->count=0;}return 0; }
OSStatus AudioQueueDispose(AudioQueueRef q,bool immediate) { (void)immediate;@synchronized(queueLock){q->disposed=YES;q->count=0;for(unsigned i=0;i<q->allocatedCount;i++)AudioQueueFreeBuffer(q,q->allocated[i]);}return 0; }
static void runFor(double seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static unsigned pending(AudioQueueRef q) { @synchronized(queueLock){return q->count;} }
static void completeOne(AudioQueueRef q) {
    AudioQueueBufferRef b;@synchronized(queueLock){NSCAssert(q->count>0,@"no queued audio");b=q->pending[0];for(unsigned i=1;i<q->count;i++)q->pending[i-1]=q->pending[i];q->count--;}
    q->callback(q->context,q,b);
}
int main(int argc,const char **argv) { @autoreleasepool {
    NSCAssert(argc==2,@"fixture path required");queueLock=[NSObject new];
    IPPCMPlayer *player=[[IPPCMPlayer alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
    player.volume=0;
    __block BOOL ready=NO,ended=NO;__block NSError *failure=nil;
    player.error=^(NSError *e){failure=e;};player.ended=^{NSCAssert(pending(latest)==0,@"ended before queued audio drained");ended=YES;};
    [player startWithCompletion:^(NSError *e){failure=e;ready=YES;}];
    for(int i=0;i<200&&!ready;i++)runFor(.01);
    NSCAssert(ready&&!failure&&player.playing&&pending(latest)==3,@"start failed %@",failure);
    NSCAssert(latest->volume==0,@"incoming PCM started audibly before fade");player.volume=.5;NSCAssert(latest->volume==.5,@"PCM hardware gain did not change");player.volume=1;
    [player pause];completeOne(latest);runFor(.05);
    NSCAssert(!player.playing&&pending(latest)==3,@"pause callback lost an audio buffer");
    [player play];runFor(.05);NSCAssert(player.playing,@"resume failed");
    [player seekFraction:.2];[player seekFraction:.6];
    for(int i=0;i<300&&(!player.playing||fabs(player.currentTime-player.duration*.6)>.1)&&!failure;i++)runFor(.01);
    NSCAssert(!failure&&player.playing&&fabs(player.currentTime-player.duration*.6)<.1,@"rapid seeks stopped playback or lost latest position: %@ %@",failure,player.diagnosticSnapshot);
    [player seekFraction:.4];[player pause];
    for(int i=0;i<300&&player.seeking&&!failure;i++)runFor(.01);
    NSCAssert(!failure&&!player.seeking&&!player.playing&&!latest->running&&fabs(player.currentTime-player.duration*.4)<.1,@"pause during seek restarted audio or lost target");
    [player seekFraction:.7];[player play];
    for(int i=0;i<300&&player.seeking&&!failure;i++)runFor(.01);
    NSCAssert(!failure&&player.playing&&latest->running&&fabs(player.currentTime-player.duration*.7)<.1,@"play during seek did not apply latest intent");
    puts("Interactive seeks passed: latest rapid request, pause during seek, play during seek and audio restart");
    for(int i=0;i<500&&!ended&&!failure;i++){if(pending(latest))completeOne(latest);runFor(.005);}
    NSCAssert(ended&&!failure,@"playback did not drain to EOF %@",failure);
    [player stop];runFor(.1);NSCAssert(latest->disposed,@"stop failed to dispose queue");
    free(latest);
    IPPCMPlayer *resumed=[[IPPCMPlayer alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];resumed.initialTime=2;ready=NO;failure=nil;
    [resumed startWithCompletion:^(NSError *e){failure=e;ready=YES;}];for(int i=0;i<200&&!ready;i++)runFor(.01);
    NSCAssert(ready&&!failure&&resumed.currentTime>=1.99&&resumed.currentTime<2.2,@"resume started at wrong offset: %f %@",resumed.currentTime,failure);
    [resumed seekFraction:.5];[resumed stop];runFor(.1);NSCAssert(latest->disposed&&!resumed.playing&&!resumed.seeking,@"resumed queue failed to stop");free(latest);puts("PCM initial-offset resume passed");
    IPPCMPlayer *outgoing=[[IPPCMPlayer alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];ready=NO;
    [outgoing startWithCompletion:^(NSError *e){NSCAssert(!e,@"outgoing failed");ready=YES;}];for(int i=0;i<200&&!ready;i++)runFor(.01);NSCAssert(ready,@"outgoing timed out");AudioQueueRef outgoingQueue=latest;
    IPPCMPlayer *incoming=[[IPPCMPlayer alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];incoming.volume=0;ready=NO;
    [incoming startWithCompletion:^(NSError *e){NSCAssert(!e,@"incoming failed");ready=YES;}];for(int i=0;i<200&&!ready;i++)runFor(.01);NSCAssert(ready,@"incoming timed out");AudioQueueRef incomingQueue=latest;
    NSCAssert(outgoing.playing&&incoming.playing&&outgoingQueue->volume==1&&incomingQueue->volume==0,@"starting an incoming deck interrupted or changed outgoing gain");
    outgoing.volume=.70710678;incoming.volume=.70710678;NSCAssert(outgoingQueue->volume==incomingQueue->volume,@"two deck gains interfered");
    [outgoing stop];runFor(.1);NSCAssert(outgoingQueue->disposed&&incoming.playing&&!incomingQueue->disposed,@"disposing outgoing stopped incoming");
    incoming.volume=1;NSCAssert(incomingQueue->volume==1,@"incoming did not return to unity gain");[incoming stop];runFor(.1);NSCAssert(incomingQueue->disposed,@"incoming leaked");free(outgoingQueue);free(incomingQueue);
    puts("Two PCM decks passed: silent incoming, independent hardware gain, overlap and outgoing cleanup");
    puts("AudioQueue simulation passed: start, paused callback refill, resume, drain EOF, stop");
}return 0;}

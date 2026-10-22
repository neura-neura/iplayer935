#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
static void CheckGain(AVPlayerItem *item,float expected){
    NSCAssert(item.audioMix.inputParameters.count==1,@"legacy item is missing its audio mix");
    float start=-1,end=-1;CMTimeRange range;
    BOOL found=[item.audioMix.inputParameters[0] getVolumeRampForTime:kCMTimeZero startVolume:&start endVolume:&end timeRange:&range];
    NSCAssert(found&&fabsf(start-expected)<.001,@"legacy gain differs from requested volume: %f != %f",start,expected);
}
int main(int argc,const char **argv){@autoreleasepool{
    NSCAssert(argc==2,@"expected MP3 fixture");
    NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    AVPlayer *first=[AVPlayer new],*second=[AVPlayer new];first.volume=0;second.volume=.7;
    AVURLAsset *a=[AVURLAsset URLAssetWithURL:url options:nil];AVPlayerItem *one=[AVPlayerItem playerItemWithAsset:a];
    [first replaceCurrentItemWithPlayerItem:one];NSCAssert(first.volume==0,@"pending incoming gain was lost");
    dispatch_semaphore_t loaded=dispatch_semaphore_create(0);
    [a loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{dispatch_semaphore_signal(loaded);}];
    NSCAssert(dispatch_semaphore_wait(loaded,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0,@"fixture tracks timed out");
    NSCAssert([a statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded,@"fixture tracks failed");
    first.volume=first.volume;CheckGain(one,0);
    AVPlayerItem *two=[AVPlayerItem playerItemWithAsset:a];[second replaceCurrentItemWithPlayerItem:two];CheckGain(two,.7);
    first.volume=.25;CheckGain(one,.25);CheckGain(two,.7);
    first.volume=1;CheckGain(one,1);
    [first replaceCurrentItemWithPlayerItem:nil];first.volume=0;
    AVPlayerItem *replacement=[AVPlayerItem playerItemWithAsset:a];[first replaceCurrentItemWithPlayerItem:replacement];CheckGain(replacement,0);CheckGain(two,.7);
    [first replaceCurrentItemWithPlayerItem:nil];[second replaceCurrentItemWithPlayerItem:nil];
    puts("Legacy player gains passed: deferred tracks, silent incoming, independent decks, fade updates and item replacement");
}return 0;}

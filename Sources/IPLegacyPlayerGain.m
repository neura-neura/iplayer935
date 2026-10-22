#if defined(IP_IOS6)
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
@implementation AVPlayer (IPLegacyVolume)
+ (void)load {
    Method original=class_getInstanceMethod(self,@selector(replaceCurrentItemWithPlayerItem:));
    Method legacy=class_getInstanceMethod(self,@selector(ip6_replaceCurrentItemWithPlayerItem:));method_exchangeImplementations(original,legacy);
}
- (void)ip6_replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    [self ip6_replaceCurrentItemWithPlayerItem:item];NSNumber *gain=objc_getAssociatedObject(self,@selector(volume));[self setVolume:gain?gain.floatValue:1];
}
- (void)setVolume:(float)volume {
    objc_setAssociatedObject(self,@selector(volume),@(volume),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AVPlayerItem *item=self.currentItem;if(!item)return;
    AVMutableAudioMix *mix=objc_getAssociatedObject(item,@selector(volume));
    if(!mix){
        // Asking for tracks synchronously can block the main thread on a remote asset.
        // The player reapplies the saved gain once its item reports ready.
        if([item.asset statusOfValueForKey:@"tracks" error:NULL]!=AVKeyValueStatusLoaded)return;
        NSMutableArray *parameters=[NSMutableArray new];
        for(AVAssetTrack *track in [item.asset tracksWithMediaType:AVMediaTypeAudio]){AVMutableAudioMixInputParameters *p=[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];[parameters addObject:p];}
        if(!parameters.count)return;
        mix=[AVMutableAudioMix audioMix];mix.inputParameters=parameters;objc_setAssociatedObject(item,@selector(volume),mix,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for(AVMutableAudioMixInputParameters *p in mix.inputParameters)[p setVolume:volume atTime:kCMTimeZero];
    item.audioMix=mix;
}
- (float)volume {NSNumber *gain=objc_getAssociatedObject(self,@selector(volume));return gain?gain.floatValue:1;}
@end
#endif

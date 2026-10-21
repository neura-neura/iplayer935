#import "IPCodecCheck.h"
#import "IPPCMServer.h"
#import "IPDiagnostics.h"
#import "IPLocalAudioFile.h"
#import <AVFoundation/AVFoundation.h>
static NSDictionary *IPCodecResults;
static NSDictionary *NativeAsset(NSURL *url){
    if(!url)return @{@"playable":@NO,@"error":@"source unavailable"};
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"playable",@"tracks"] completionHandler:^{dispatch_semaphore_signal(done);}];
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))){[asset cancelLoading];return @{@"playable":@NO,@"error":@"asset timeout"};}
    NSError *error=nil;AVKeyValueStatus status=[asset statusOfValueForKey:@"playable" error:&error];
    return @{@"playable":@(status==AVKeyValueStatusLoaded&&asset.playable),@"audioTracks":@([asset tracksWithMediaType:AVMediaTypeAudio].count),@"code":@(error.code)};
}
@implementation IPCodecCheck
+ (NSDictionary *)results { @synchronized(self) { return IPCodecResults ?: @{}; } }
+ (void)run {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *key = [@"CodecCheck-" stringByAppendingString:version ?: @"unknown"];
    NSDictionary *prior = [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
    if (prior) { @synchronized(self) { IPCodecResults = prior; } return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableDictionary *results = [NSMutableDictionary new];
        for (NSString *extension in @[@"flac", @"ogg", @"opus"]) {
            @autoreleasepool {
                NSURL *source = [[NSBundle mainBundle] URLForResource:@"tone" withExtension:extension subdirectory:@"CodecChecks"];
                if (!source) { results[extension] = @"fixture missing"; continue; }
                IPPCMServer *server = [[IPPCMServer alloc] initWithURL:source];
                NSError *error = nil;
                BOOL prepared = [server preparePCM:&error];
                NSData *data = prepared ? [server readPCMFrames:1024 error:&error] : nil;
                BOOL nonzero = NO;
                const unsigned char *bytes = data.bytes;
                for (NSUInteger i = 0; i < data.length; i++) if (bytes[i]) { nonzero = YES; break; }
                results[extension] = @{
                    @"decodedPCM":@(prepared && data.length > 0 && nonzero),
                    @"bytes":@(data.length), @"code":@(error.code), @"domain":error.domain ?: @"",
                    @"pcm":[server diagnosticSnapshot]};
                [server closePCM];
            }
        }
        @autoreleasepool {
            NSURL *fixture=[[NSBundle mainBundle]URLForResource:@"tone" withExtension:@"mp3" subdirectory:@"CodecChecks"];
            NSURL *directory=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:@"NativeCacheProbe"];
            [[NSFileManager defaultManager]createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            NSURL *cached=[directory URLByAppendingPathComponent:@"tone.media"];[[NSFileManager defaultManager]removeItemAtURL:cached error:NULL];
            NSError *error=nil;BOOL copied=fixture&&[[NSFileManager defaultManager]copyItemAtURL:fixture toURL:cached error:&error];
            IPLocalAudioFile *source=[[IPLocalAudioFile alloc]initWithDirectory:[directory URLByAppendingPathComponent:@"Links"]];NSURL *typed=copied?[source openFile:cached extension:@"mp3" error:&error]:nil;
            results[@"nativeCachedMP3"]=@{@"genericExtension":copied?NativeAsset(cached):@{},@"audioExtension":NativeAsset(typed),@"linkCreated":@(typed!=nil),@"code":@(error.code)};
            [source close];[[NSFileManager defaultManager]removeItemAtURL:cached error:NULL];
        }
        NSDictionary *snapshot = [results copy];
        @synchronized(self) { IPCodecResults = snapshot; }
        [[NSUserDefaults standardUserDefaults] setObject:snapshot forKey:key];
        [IPDiagnostics write];
    });
}
@end

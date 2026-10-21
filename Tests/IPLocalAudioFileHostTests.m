#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import "IPLocalAudioFile.h"
#include <sys/stat.h>
static BOOL Playable(NSURL *url){AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];dispatch_semaphore_t done=dispatch_semaphore_create(0);[asset loadValuesAsynchronouslyForKeys:@[@"playable",@"tracks"] completionHandler:^{dispatch_semaphore_signal(done);}];NSCAssert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0,@"asset load timeout");return asset.playable&&[asset tracksWithMediaType:AVMediaTypeAudio].count==1;}
int main(int argc,const char **argv){@autoreleasepool{
    NSCAssert(argc==2,@"MP3 fixture required");NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:[[NSUUID UUID]UUIDString]];[[NSFileManager defaultManager]createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *cache=[root URLByAppendingPathComponent:@"cached.media"];[[NSFileManager defaultManager]copyItemAtURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]] toURL:cache error:NULL];
    IPLocalAudioFile *source=[[IPLocalAudioFile alloc]initWithDirectory:[root URLByAppendingPathComponent:@"PlaybackLinks"]];NSError *error=nil;NSURL *typed=[source openFile:cache extension:@"mp3" error:&error];NSCAssert(typed&&!error&&[typed.pathExtension isEqual:@"mp3"],@"typed local source failed: %@",error);
    struct stat a,b;stat(cache.path.fileSystemRepresentation,&a);stat(typed.path.fileSystemRepresentation,&b);NSCAssert(a.st_ino==b.st_ino&&a.st_size==b.st_size,@"cached source was copied or changed");NSCAssert(Playable(typed),@"AVFoundation rejected typed MP3 link");
    [source close];NSCAssert(![[NSFileManager defaultManager]fileExistsAtPath:typed.path]&&[[NSFileManager defaultManager]fileExistsAtPath:cache.path],@"closing alias removed cached audio");
    typed=[source openFile:cache extension:@"mp3" error:&error];NSCAssert(Playable(typed),@"cache failed to reopen");
    // Simulate a previous process leaving a playback link; clean only the links directory.
    IPLocalAudioFile *restart=[[IPLocalAudioFile alloc]initWithDirectory:[root URLByAppendingPathComponent:@"PlaybackLinks"]];NSCAssert(![[NSFileManager defaultManager]fileExistsAtPath:typed.path]&&[[NSFileManager defaultManager]fileExistsAtPath:cache.path],@"restart cleanup damaged cache");[source close];
    NSCAssert(![restart openFile:cache extension:@"../mp3" error:&error],@"invalid extension accepted");
    [restart close];[[NSFileManager defaultManager]removeItemAtURL:root error:NULL];puts("Local cached MP3 passed: typed hard link, identical inode/bytes, AVFoundation audio, reopen and link cleanup");
}return 0;}

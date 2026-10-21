#import <Foundation/Foundation.h>
#import "IPPlaybackState.h"
#import "IPShuffleQueue.h"
#import "IPSmartCache.h"
#import "IPSMB.h"
#include <math.h>
static BOOL offline=NO,interruptRead=NO;
static NSUInteger reads=0;
@implementation IPSMB
- (instancetype)initWithProfile:(NSDictionary *)p password:(NSString *)password {return [super init];}
- (NSArray *)list:(NSString *)path error:(NSError **)error {return @[];}
- (BOOL)connect:(NSError **)error {return !offline;}
- (uint64_t)size:(NSString *)path error:(NSError **)error {return 400*1024;}
- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {reads++;if(offline||(interruptRead&&offset>0))return nil;NSMutableData *data=[NSMutableData dataWithLength:length];memset(data.mutableBytes,42,length);return data;}
- (void)disconnect {}
@end
static NSDictionary *Track(NSString *tid){return @{@"id":tid,@"profileID":@"p",@"endpointIdentity":@"e",@"path":tid,@"extension":@"mp3",@"size":@(400*1024),@"title":tid};}
int main(){@autoreleasepool{
    NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:[[NSUUID UUID]UUIDString]];
    IPPlaybackState *state=[[IPPlaybackState alloc]initWithDirectory:[root URLByAppendingPathComponent:@"state"]];NSArray *tracks=@[Track(@"a"),Track(@"b"),Track(@"c")];
    NSArray *queue=@[tracks[0],tracks[1],tracks[0],tracks[2]];[state saveQueue:queue index:2 elapsed:43.25 duration:180];[state flush];
    IPPlaybackState *reopen=[[IPPlaybackState alloc]initWithDirectory:[root URLByAppendingPathComponent:@"state"]];NSDictionary *restored=[reopen restoreWithTracks:tracks];NSCAssert([restored[@"queue"]count]==4&&[restored[@"index"]intValue]==2&&fabs([restored[@"elapsed"]doubleValue]-43.25)<.01,@"queue/duplicate/playhead restoration failed");
    NSDictionary *pruned=[reopen restoreWithTracks:@[tracks[0],tracks[2]]];NSCAssert([pruned[@"queue"]count]==3&&[pruned[@"index"]intValue]==1&&[pruned[@"elapsed"]doubleValue]>43,@"removal before current track lost the playhead");
    pruned=[reopen restoreWithTracks:@[tracks[1],tracks[2]]];NSCAssert([pruned[@"queue"]count]==2&&[pruned[@"index"]intValue]==1&&[pruned[@"elapsed"]doubleValue]==0,@"missing current track reused its timestamp");
    NSURL *queueURL=[[root URLByAppendingPathComponent:@"state"]URLByAppendingPathComponent:@"playback-queue.json"];NSData *before=[NSData dataWithContentsOfURL:queueURL];[reopen savePosition:3 elapsed:88 duration:180];[reopen flush];NSCAssert([before isEqual:[NSData dataWithContentsOfURL:queueURL]],@"small playhead updates rewrote queue");
    restored=[reopen restoreWithTracks:tracks];NSCAssert([restored[@"index"]intValue]==3&&[restored[@"elapsed"]intValue]==88,@"updated playhead lost");
    [reopen savePosition:0 elapsed:NAN duration:INFINITY];[reopen flush];restored=[reopen restoreWithTracks:tracks];NSCAssert([restored[@"elapsed"]intValue]==0,@"invalid time escaped persistence");
    NSMutableArray *large=[NSMutableArray new];for(int i=0;i<25154;i++)[large addObject:Track([NSString stringWithFormat:@"%d",i])];[state saveQueue:large index:25153 elapsed:15 duration:90];[state flush];restored=[state restoreWithTracks:large];NSCAssert([restored[@"queue"]count]==25154&&[restored[@"index"]intValue]==25153,@"large queue restoration failed");
    [[NSFileManager defaultManager]removeItemAtURL:[[root URLByAppendingPathComponent:@"state"]URLByAppendingPathComponent:@"playback-position.json"] error:NULL];restored=[state restoreWithTracks:large];NSCAssert([restored[@"index"]intValue]==25153&&[restored[@"elapsed"]intValue]==15,@"interrupted queue/position commit restored wrong track");
    for(NSUInteger current=0;current<queue.count;current++)for(int attempt=0;attempt<32;attempt++){
        IPShuffleQueue *random=[[IPShuffleQueue alloc]initWithQueue:queue currentIndex:current];
        NSCAssert(random.count==queue.count&&[random originalIndexAtIndex:0]==current&&[[NSSet setWithArray:random.order]count]==queue.count,@"shuffle dropped a position, repeated it or changed current song");
        NSCAssert([random[0]isEqual:queue[current]],@"shuffle changed the selected occurrence");
        for(NSUInteger i=0;i<random.count;i++)NSCAssert([random[i]isEqual:queue[[random originalIndexAtIndex:i]]],@"original order mapping lost");
    }
    IPShuffleQueue *shuffled=[[IPShuffleQueue alloc]initWithQueue:queue order:@[@2,@3,@0,@1]];
    [state saveQueue:shuffled index:2 elapsed:27 duration:90];[state flush];
    restored=[state restoreWithTracks:tracks];IPShuffleQueue *savedShuffle=restored[@"queue"];
    NSCAssert([savedShuffle isKindOfClass:[IPShuffleQueue class]]&&[savedShuffle.order isEqual:shuffled.order]&&[savedShuffle.originalQueue isEqual:queue]&&[restored[@"index"]intValue]==2&&[restored[@"elapsed"]intValue]==27,@"shuffle session lost history, duplicate occurrences, natural order or playhead");
    NSCAssert([savedShuffle originalIndexAtIndex:2]==0,@"turning shuffle off selected the other duplicate occurrence");
    restored=[state restoreWithTracks:@[tracks[0],tracks[2]]];savedShuffle=restored[@"queue"];
    NSCAssert([savedShuffle isKindOfClass:[IPShuffleQueue class]]&&([savedShuffle.order isEqual:@[@1,@2,@0]])&&([savedShuffle.originalQueue isEqual:@[tracks[0],tracks[0],tracks[2]]])&&[restored[@"index"]intValue]==2&&[restored[@"elapsed"]intValue]==27,@"pruning a shuffled session lost natural order or current occurrence");
    restored=[state restoreWithTracks:@[tracks[1],tracks[2]]];NSCAssert([restored[@"elapsed"]intValue]==0,@"missing shuffled current song inherited old playhead");
    IPShuffleQueue *empty=[[IPShuffleQueue alloc]initWithQueue:@[] currentIndex:0];NSCAssert(empty.count==0,@"empty shuffle failed");
    IPShuffleQueue *single=[[IPShuffleQueue alloc]initWithQueue:@[tracks[0]] currentIndex:0];NSCAssert(single.count==1&&[single[0]isEqual:tracks[0]],@"single-track shuffle failed");
    puts("Shuffle passed: full permutation, pinned current occurrence, original order, duplicates, session/playhead and missing tracks");
    puts("Session persistence passed: 25154 IDs, duplicate order, playhead, missing tracks and small position writes");
    NSDictionary *profile=@{@"id":@"p",@"endpointIdentity":@"e"};NSArray *profiles=@[profile];
    IPSmartCache *cache=[[IPSmartCache alloc]initWithDirectory:[root URLByAppendingPathComponent:@"cache"]];cache.limitBytes=1024*1024;[cache flush];
    [cache prefetchQueue:tracks index:0 profiles:profiles password:nil];[cache flush];NSCAssert([cache localURLForTrack:tracks[1]]&&[cache localURLForTrack:tracks[2]],@"next songs were not prioritized");NSCAssert(![cache localURLForTrack:tracks[0]]&&[cache.status[@"bytes"]unsignedLongLongValue]<=cache.limitBytes,@"quota was exceeded or next songs evicted for current");
    NSUInteger previousReads=reads;offline=YES;[cache prefetchQueue:tracks index:1 profiles:profiles password:nil];[cache flush];NSCAssert([cache localURLForTrack:tracks[1]]&&reads==previousReads,@"complete cache did not work offline");offline=NO;
    IPSmartCache *cacheReopen=[[IPSmartCache alloc]initWithDirectory:[root URLByAppendingPathComponent:@"cache"]];NSCAssert([cacheReopen localURLForTrack:tracks[1]]&&cacheReopen.limitBytes==1024*1024,@"cache/settings failed to survive restart");
    NSArray *newQueue=@[tracks[1],Track(@"d")];[cache prefetchQueue:newQueue index:0 profiles:profiles password:nil];[cache flush];NSCAssert([cache localURLForTrack:tracks[1]]&&[cache localURLForTrack:newQueue[1]]&&![cache localURLForTrack:tracks[2]],@"LRU eviction removed protected playback or retained old file");
    [cache clear];[cache flush];NSCAssert([cache localURLForTrack:tracks[1]]&&[cache.status[@"count"]intValue]==1,@"clear removed the song in use");
    interruptRead=YES;[cache prefetchQueue:@[tracks[1],Track(@"partial")] index:0 profiles:profiles password:nil];[cache flush];NSCAssert(![cache localURLForTrack:Track(@"partial")],@"partial download became playable");interruptRead=NO;
    NSMutableDictionary *changed=[tracks[1]mutableCopy];changed[@"modifiedAt"]=@123;NSCAssert(![cache localURLForTrack:changed],@"modified remote file reused stale cache");
    cache.enabled=NO;previousReads=reads;[cache prefetchQueue:@[Track(@"disabled")] index:0 profiles:profiles password:nil];[cache flush];NSCAssert(reads==previousReads,@"disabled cache still downloaded");
    puts("Smart cache passed: next-first order, quota/LRU, current protection, offline, restart, interrupted reads, revision and disable");
    [[NSFileManager defaultManager]removeItemAtURL:root error:NULL];
}return 0;}

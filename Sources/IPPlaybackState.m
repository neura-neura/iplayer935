#import "IPPlaybackState.h"
#import "IPLibraryDB.h"
#import "IPShuffleQueue.h"
#include <math.h>
static NSDictionary *Position(NSString *revision,NSInteger index,double elapsed,double duration){return @{@"revision":revision,@"index":@(MAX(0,index)),@"elapsed":@(isfinite(elapsed)?MAX(0,elapsed):0),@"duration":@(isfinite(duration)?MAX(0,duration):0)};}
@interface IPPlaybackState ()
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic,strong) dispatch_queue_t writer;
@property(nonatomic,copy) NSString *revision;
@end
@implementation IPPlaybackState
- (instancetype)initWithDirectory:(NSURL *)directory {
    if((self=[super init])){_directory=directory;_writer=dispatch_queue_create("org.neura.playback-state",DISPATCH_QUEUE_SERIAL);[[NSFileManager defaultManager]createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];}return self;
}
- (NSDictionary *)read:(NSString *)name {NSData *data=[NSData dataWithContentsOfURL:[self.directory URLByAppendingPathComponent:name]];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;return [value isKindOfClass:[NSDictionary class]]?value:@{};}
- (NSDictionary *)restoreWithTracks:(NSArray *)tracks {
    NSDictionary *saved=[self read:@"playback-queue.json"],*position=[self read:@"playback-position.json"];
    NSArray *ids=saved[@"ids"];if(![ids isKindOfClass:[NSArray class]]||![saved[@"revision"]isKindOfClass:[NSString class]])return nil;
    self.revision=saved[@"revision"];if(![position[@"revision"]isEqual:self.revision])position=[saved[@"initialPosition"]isKindOfClass:[NSDictionary class]]?saved[@"initialPosition"]:@{};
    BOOL lazy=[tracks respondsToSelector:@selector(trackIDs)]&&[tracks respondsToSelector:@selector(queueForIDs:)];
    NSSet *available=lazy?[NSSet setWithArray:[(id)tracks trackIDs]]:nil;
    NSMutableDictionary *byID=[NSMutableDictionary new];if(!lazy)for(NSDictionary *t in tracks)if(t[@"id"])byID[t[@"id"]]=t;
    NSInteger original=[position[@"index"] respondsToSelector:@selector(integerValue)]?MAX(0,[position[@"index"]integerValue]):0,index=0;BOOL selectedFound=NO;NSMutableArray *queue=[NSMutableArray new];
    for(NSUInteger i=0;i<ids.count;i++){id tid=ids[i];id track=[tid isKindOfClass:[NSString class]]?(lazy?([available containsObject:tid]?tid:nil):byID[tid]):nil;if(!track)continue;if((NSInteger)i<original)index++;if((NSInteger)i==original)selectedFound=YES;[queue addObject:track];}
    if(!queue.count)return nil;index=MIN(index,(NSInteger)queue.count-1);
    NSArray *resolved=lazy?[(id)tracks queueForIDs:queue]:queue;
    NSArray *baseIDs=saved[@"originalIDs"],*order=saved[@"shuffleOrder"];
    if([baseIDs isKindOfClass:[NSArray class]]&&[order isKindOfClass:[NSArray class]]&&baseIDs.count==ids.count&&order.count==ids.count){
        NSMutableIndexSet *seen=[NSMutableIndexSet new];BOOL valid=YES;
        for(NSUInteger i=0;i<order.count;i++){id value=order[i];if(![value isKindOfClass:[NSNumber class]]){valid=NO;break;}NSUInteger n=[value unsignedIntegerValue];if(n>=baseIDs.count||[seen containsIndex:n]||![ids[i]isEqual:baseIDs[n]]){valid=NO;break;}[seen addIndex:n];}
        if(valid){
            NSMutableArray *base=[NSMutableArray new],*remap=[NSMutableArray new],*filteredOrder=[NSMutableArray new];
            for(id tid in baseIDs){id t=lazy?([available containsObject:tid]?tid:nil):byID[tid];[remap addObject:t?@(base.count):@(-1)];if(t)[base addObject:t];}
            for(NSNumber *n in order){NSNumber *mapped=remap[n.unsignedIntegerValue];if(mapped.integerValue>=0)[filteredOrder addObject:mapped];}
            NSArray *original=lazy?[(id)tracks queueForIDs:base]:base;
            resolved=[[IPShuffleQueue alloc]initWithQueue:original order:filteredOrder];
        }
    }
    double elapsed=[position[@"elapsed"] respondsToSelector:@selector(doubleValue)]?[position[@"elapsed"]doubleValue]:0,duration=[position[@"duration"] respondsToSelector:@selector(doubleValue)]?[position[@"duration"]doubleValue]:0;
    if(!selectedFound)duration=[resolved[index][@"duration"]doubleValue];
    if(!selectedFound||!isfinite(elapsed)||elapsed<0)elapsed=0;if(!isfinite(duration)||duration<0)duration=0;
    if(duration>0)elapsed=MIN(elapsed,MAX(0,duration-.1));
    return @{@"queue":resolved,@"index":@(index),@"elapsed":@(elapsed),@"duration":@(duration)};
}
- (void)write:(NSDictionary *)value name:(NSString *)name {NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];if(data)[data writeToURL:[self.directory URLByAppendingPathComponent:name] options:NSDataWritingAtomic error:NULL];}
- (void)saveQueue:(NSArray *)tracks index:(NSInteger)index elapsed:(double)elapsed duration:(double)duration {
    NSArray *ids;
    if([tracks respondsToSelector:@selector(trackIDs)])ids=[(id)tracks trackIDs];
    else {NSMutableArray *collected=[NSMutableArray arrayWithCapacity:tracks.count];for(NSDictionary *track in tracks)if([track[@"id"]isKindOfClass:[NSString class]])[collected addObject:track[@"id"]];ids=collected;}
    self.revision=[[NSUUID UUID]UUIDString];NSMutableDictionary *queue=[@{@"ids":ids,@"revision":self.revision,@"initialPosition":Position(self.revision,index,elapsed,duration)} mutableCopy];
    if([tracks isKindOfClass:[IPShuffleQueue class]]){IPShuffleQueue *shuffled=(id)tracks;NSArray *original=shuffled.originalQueue;queue[@"originalIDs"]=[original respondsToSelector:@selector(trackIDs)]?[(id)original trackIDs]:[original valueForKey:@"id"];queue[@"shuffleOrder"]=shuffled.order;}
    dispatch_async(self.writer,^{[self write:queue name:@"playback-queue.json"];});[self savePosition:index elapsed:elapsed duration:duration];
}
- (void)savePosition:(NSInteger)index elapsed:(double)elapsed duration:(double)duration {
    if(!self.revision)return;NSDictionary *position=Position(self.revision,index,elapsed,duration);
    dispatch_async(self.writer,^{[self write:position name:@"playback-position.json"];});
}
- (void)flush {dispatch_sync(self.writer,^{});}
@end

#import "IPLibraryIndex.h"
static NSString *Fold(NSString *s) {return [[s?:@"" stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:[NSLocale currentLocale]] lowercaseString];}
@implementation IPLibraryIndex {
    dispatch_queue_t _queue;
    NSMutableDictionary *_documents,*_models,*_cache;
}
- (instancetype)init {if((self=[super init])){_queue=dispatch_queue_create("org.neura.iplayer935.library-index",DISPATCH_QUEUE_SERIAL);_documents=[NSMutableDictionary new];_models=[NSMutableDictionary new];_cache=[NSMutableDictionary new];}return self;}
- (void)replaceTracks:(NSArray *)tracks {[self capture:tracks replace:YES];}
- (void)updateTracks:(NSArray *)tracks {[self capture:tracks replace:NO];}
- (void)capture:(NSArray *)tracks replace:(BOOL)replace {
    NSAssert([NSThread isMainThread],@"Index models belong to the main thread");
    if(replace)[_models removeAllObjects];
    NSMutableArray *snapshots=[NSMutableArray arrayWithCapacity:tracks.count];
    for(NSDictionary *t in tracks)if([t[@"id"] length]){_models[t[@"id"]]=t;[snapshots addObject:[t copy]];}
    dispatch_async(_queue,^{@autoreleasepool{
        if(replace)[self->_documents removeAllObjects];
        for(NSDictionary *t in snapshots){
            NSMutableDictionary *d=[NSMutableDictionary new];
            for(NSString *k in @[@"id",@"profileID",@"endpointIdentity",@"favorite",@"downloaded",@"metadataPending",@"unsupportedReason",@"trackNumber",@"addedAt",@"modifiedAt",@"path"])if(t[k])d[k]=t[k];
            for(NSString *k in @[@"title",@"artist",@"album",@"genre"])d[k]=Fold(t[k]);
            d[@"search"]=[NSString stringWithFormat:@"%@ %@ %@ %@",d[@"title"],d[@"artist"],d[@"album"],d[@"genre"]];
            self->_documents[d[@"id"]]=[d copy];
        }
        [self->_cache removeAllObjects];
    }});
}
- (void)rowsForProfile:(NSDictionary *)profile mode:(NSString *)mode playlistIDs:(NSArray *)playlistIDs sort:(NSString *)sort query:(NSString *)query completion:(void (^)(NSArray *,NSUInteger))completion {
    NSString *pid=[profile[@"id"] copy],*endpoint=[profile[@"endpointIdentity"] copy];
    NSArray *order=[playlistIDs copy];NSString *q=[query copy]?:@"",*key=[sort copy]?:@"title",*kind=[mode copy]?:@"";
    dispatch_async(_queue,^{@autoreleasepool{
        NSString *normalized=Fold(q);
        NSArray *cacheKey=@[pid?:@"",endpoint?:@"",kind,key,normalized,order?:@[]];
        NSDictionary *cached=self->_cache[cacheKey];
        NSArray *ids=cached[@"ids"];NSUInteger pending=[cached[@"pending"] unsignedIntegerValue];
        if(!ids){
            NSMutableArray *docs=[NSMutableArray new];NSSet *members=order?[NSSet setWithArray:order]:nil;
            for(NSDictionary *d in self->_documents.allValues){
                if(pid && (![pid isEqual:d[@"profileID"]]||![endpoint isEqual:d[@"endpointIdentity"]]))continue;
                if(members && ![members containsObject:d[@"id"]])continue;
                if([kind isEqual:@"favorites"]&&![d[@"favorite"] boolValue])continue;
                if([kind isEqual:@"downloads"]&&![d[@"downloaded"] boolValue])continue;
                if([d[@"metadataPending"] boolValue]&&!d[@"unsupportedReason"])pending++;
                if(normalized.length&&[d[@"search"] rangeOfString:normalized].location==NSNotFound)continue;
                [docs addObject:d];
            }
            NSMutableArray *result=[NSMutableArray arrayWithCapacity:docs.count];
            if(order&&[key isEqual:@"playlist"]){NSSet *included=[NSSet setWithArray:[docs valueForKey:@"id"]];for(NSString *tid in order)if([included containsObject:tid])[result addObject:tid];}
            else {
                [docs sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
                    NSComparisonResult r=NSOrderedSame;
                    if([key isEqual:@"recent"]){double av=[a[@"modifiedAt"] doubleValue]?:[a[@"addedAt"] doubleValue],bv=[b[@"modifiedAt"] doubleValue]?:[b[@"addedAt"] doubleValue];r=av>bv?NSOrderedAscending:av<bv?NSOrderedDescending:NSOrderedSame;}
                    else if([key isEqual:@"trackNumber"])r=[a[@"trackNumber"]?:@0 compare:b[@"trackNumber"]?:@0];
                    else r=[a[key]?:@"" compare:b[key]?:@"" options:NSNumericSearch];
                    if(r==NSOrderedSame)r=[a[@"title"] compare:b[@"title"] options:NSNumericSearch];
                    if(r==NSOrderedSame)r=[a[@"id"] compare:b[@"id"]];return r;
                }];
                for(NSDictionary *d in docs)[result addObject:d[@"id"]];
            }
            ids=[result copy];if(self->_cache.count>=8)[self->_cache removeAllObjects];self->_cache[cacheKey]=@{@"ids":ids,@"pending":@(pending)};
        }
        dispatch_async(dispatch_get_main_queue(),^{NSMutableArray *rows=[NSMutableArray arrayWithCapacity:ids.count];for(NSString *tid in ids)if(self->_models[tid])[rows addObject:self->_models[tid]];if(completion)completion(rows,pending);});
    }});
}
@end

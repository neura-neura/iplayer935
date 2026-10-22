#import "IPLibraryDB.h"
#import "IPPlaybackState.h"
#import "IPShuffleQueue.h"
#import <Foundation/Foundation.h>
#import <sqlite3.h>
static void Wait(BOOL *done) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!*done && end.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(*done, @"SQLite query timeout");
}
static NSArray *Query(IPLibraryDB *db, NSDictionary *profile, NSString *mode, NSArray *members,
                      NSString *sort, NSString *q, NSUInteger offset, NSUInteger limit,
                      NSUInteger expected) {
    __block BOOL done = NO;
    __block NSArray *result;
    [db queryProfile:profile
                mode:mode
         playlistIDs:members
                sort:sort
               query:q
              offset:offset
               limit:limit
          completion:^(NSArray *ids, NSUInteger total, NSUInteger pending, NSArray *records) {
              NSCAssert([NSThread isMainThread] && total == expected,
                        @"count or callback thread incorrect: %lu expected %lu",
                        (unsigned long)total, (unsigned long)expected);
              NSCAssert(!limit || records.count == ids.count, @"page failed to read its metadata");
              result = ids;
              done = YES;
          }];
    Wait(&done);
    return result;
}
static int Collate(void *ctx, int an, const void *a, int bn, const void *b) { return 0; }
int main() {
    @autoreleasepool {
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSURL *url = [root URLByAppendingPathComponent:@"library.sqlite"];
        IPLibraryDB *db = [[IPLibraryDB alloc] initWithURL:url];
        NSCAssert(!db.error && !db.ready, @"SQLite open failed: %@", db.error);
        NSDictionary *profile = @{@"id" : @"p", @"endpointIdentity" : @"e"};
        NSMutableArray *tracks = [NSMutableArray new], *ids = [NSMutableArray new];
        for (NSUInteger n = 0; n < 25154; n++) {
            NSString *tid = [NSString stringWithFormat:@"%05lu", (unsigned long)n];
            [ids addObject:tid];
            [tracks addObject:@{
                @"id" : tid,
                @"profileID" : @"p",
                @"endpointIdentity" : @"e",
                @"title" : [NSString stringWithFormat:@"Song %lu", (unsigned long)n],
                @"artist" : @"Árbol",
                @"album" : @"Álbum",
                @"genre" : @"Rock",
                @"extension" : @"mp3",
                @"path" : @"song.mp3",
                @"modifiedAt" : @(n),
                @"trackNumber" : @(n),
                @"favorite" : @(n == 3),
                @"downloaded" : @(n == 4),
                @"metadataAutoVersion" : @14,
                @"artworkAutoVersion" : @15,
                @"duration" : @60
            }];
        }
        NSDate *start = [NSDate date];
        NSDictionary *state = @{
            @"profiles" : @[ profile ],
            @"playlists" : @[
                @{@"id" : @"list",
                  @"trackIDs" : @[ @"00003", @"00001", @"00003" ]}
            ],
            @"cacheLimitBytes" : @123456789
        };
        NSCAssert([db commitState:state tracks:tracks IDs:ids] && [db buildImportIndexes] && db.ready,
                  @"migration transaction failed: %@", db.error);
        printf("SQLite migration of 25154 records: %.3fs (Mac host)\n",
               -[start timeIntervalSinceNow]);
        IPLibraryDB *reopen = [[IPLibraryDB alloc] initWithURL:url];
        NSCAssert(reopen.ready && [[reopen state] isEqual:state] && [[reopen trackIDs] isEqual:ids],
                  @"state, order or playlist duplicates lost on reopening");
        IPTrackCollection *collection =
            [[IPTrackCollection alloc] initWithDatabase:reopen IDs:[reopen trackIDs]];
        NSCAssert(collection.materializedTracks.count == 0 && collection.count == 25154,
                  @"reopening eagerly read all metadata");
        start = [NSDate date];
        NSArray *page = Query(reopen, profile, @"library", nil, @"title", nil, 0, 200, 25154);
        NSCAssert(page.count == 200 && [page[2] isEqual:@"00002"],
                  @"natural title ordering failed");
        [collection materializeIDs:page];
        NSCAssert(collection.materializedTracks.count == 200 && collection.changedTracks.count == 0,
                  @"paging hydrated more than its first block or dirtied clean records");
        printf("Indexed first 200 title rows + metadata: %.3fs (Mac host)\n",
               -[start timeIntervalSinceNow]);
        NSArray *second = Query(reopen, profile, @"library", nil, @"title", nil, 200, 200, 25154);
        NSMutableSet *unique = [NSMutableSet setWithArray:page];
        [unique addObjectsFromArray:second];
        NSCAssert(unique.count == 400, @"pages overlap or skip positions");
        for (NSString *sort in @[ @"artist", @"album", @"genre", @"trackNumber" ]) {
            NSArray *p = Query(reopen, profile, @"library", nil, sort, @"arbol", 0, 200, 25154);
            NSCAssert(p.count == 200 && [p[2] isEqual:@"00002"],
                      @"metadata sort/accent search failed: %@", sort);
        }
        NSCAssert(
            [Query(reopen, profile, @"library", nil, @"recent", nil, 0, 200, 25154).firstObject
                isEqual:@"25153"],
            @"recent ordering failed");
        NSCAssert([Query(reopen, nil, @"favorites", nil, @"title", nil, 0, 200, 1).firstObject
                      isEqual:@"00003"],
                  @"favorite filter failed");
        NSCAssert([Query(reopen, nil, @"downloads", nil, @"title", nil, 0, 200, 1).firstObject
                      isEqual:@"00004"],
                  @"download filter failed");
        NSCAssert(Query(reopen, @{@"id" : @"p", @"endpointIdentity" : @"retired"}, @"library", nil,
                        @"title", nil, 0, 200, 0)
                          .count == 0,
                  @"retired endpoint leaked");
        NSArray *members = @[ @"00003", @"00001", @"00003", @"missing" ];
        NSArray *playlist = Query(reopen, nil, @"songs", members, @"playlist", nil, 0, 200, 3);
        NSCAssert(([playlist isEqual:@[ @"00003", @"00001", @"00003" ]]),
                  @"playlist duplicate/order lost");
        NSCAssert(Query(reopen, nil, @"songs", members, @"title", nil, 0, 200, 2).count == 2,
                  @"sorted membership should deduplicate");
        NSArray *all = Query(reopen, profile, @"library", nil, @"title", nil, 0, 0, 25154);
        NSArray *queue = [collection queueForIDs:all];
        NSCAssert(queue.count == 25154 && collection.materializedTracks.count == 200,
                  @"full playback queue eagerly hydrated all tracks");
        IPPlaybackState *session = [[IPPlaybackState alloc] initWithDirectory:root];
        [session saveQueue:queue index:13000 elapsed:12 duration:60];
        [session flush];
        NSDictionary *restored =
            [[[IPPlaybackState alloc] initWithDirectory:root] restoreWithTracks:collection];
        NSCAssert([restored[@"queue"] count] == 25154 &&
                      [restored[@"index"] integerValue] == 13000 &&
                      [restored[@"elapsed"] doubleValue] == 12 &&
                      collection.materializedTracks.count == 200,
                  @"session restore lost queue or eagerly read metadata");
        NSCAssert([restored[@"queue"][13000][@"id"] isEqual:all[13000]] &&
                      collection.materializedTracks.count <= 201,
                  @"restored queue resolves the wrong current song");
        NSUInteger modelsBeforeShuffle=collection.materializedTracks.count;
        IPShuffleQueue *shuffled=[[IPShuffleQueue alloc]initWithQueue:queue currentIndex:13000];
        NSCAssert(shuffled.count==25154&&[shuffled originalIndexAtIndex:0]==13000&&collection.materializedTracks.count==modelsBeforeShuffle,@"shuffle eagerly materialized the library");
        [session saveQueue:shuffled index:100 elapsed:23 duration:60];[session flush];
        restored=[session restoreWithTracks:collection];IPShuffleQueue *restoredShuffle=restored[@"queue"];
        NSCAssert([restoredShuffle isKindOfClass:[IPShuffleQueue class]]&&[restoredShuffle.order isEqual:shuffled.order]&&[restoredShuffle.originalQueue respondsToSelector:@selector(trackIDs)]&&collection.materializedTracks.count==modelsBeforeShuffle,@"shuffle save/restore lost lazy queue or read all metadata");
        NSMutableDictionary *changed = [collection trackForID:@"00003"];
        changed[@"title"] = @"¡Nuevo título!";
        changed[@"favorite"] = @NO;
        NSCAssert(collection.changedTracks.count == 1 &&
                      [reopen updateTracks:collection.changedTracks],
                  @"incremental update failed");
        [collection acknowledgeTracks:@[ [changed copy] ]];
        NSCAssert(collection.changedTracks.count == 0 &&
                      Query(reopen, nil, @"favorites", nil, @"title", nil, 0, 200, 0).count == 0 &&
                      Query(reopen, profile, @"library", nil, @"title", @"nuevo titulo", 0, 200, 1)
                              .count == 1,
                  @"incremental sort/search/favorite invalidation failed");
        NSArray *sameRecords = [reopen recordsForProfileID:@"p"];
        NSMutableDictionary *previous = [NSMutableDictionary new];
        for (NSDictionary *t in sameRecords)
            previous[t[@"id"]] = t;
        NSUInteger materializedBefore = collection.materializedTracks.count;
        [collection replaceProfileRecords:sameRecords previous:previous];
        NSCAssert(collection.changedTracks.count == 0 &&
                      collection.materializedTracks.count == materializedBefore,
                  @"unchanged automatic refresh loaded or dirtied every track");
        [collection removeObjectAtIndex:0];
        NSCAssert([reopen commitState:state
                               tracks:collection.changedTracks
                                  IDs:collection.trackIDs] &&
                      ![reopen track:@"00000"] && [reopen trackIDs].count == 25153,
                  @"structural deletion did not persist");
        NSDictionary *before = [reopen state];
        NSDictionary *invalid = @{@"id" : @"bad", @"title" : [NSDate date]};
        NSCAssert(![reopen commitState:@{
            @"invalid" : @YES
        }
                                tracks:@[ invalid ]
                                   IDs:@[ @"bad" ]] &&
                      [[reopen state] isEqual:before] && [reopen trackIDs].count == 25153,
                  @"failed transaction replaced prior library");
        sqlite3 *raw = NULL;
        NSCAssert(sqlite3_open(url.path.UTF8String, &raw) == SQLITE_OK,
                  @"could not inspect query plan");
        sqlite3_create_collation(raw, "IPNATURAL", SQLITE_UTF8, NULL, Collate);
        sqlite3_stmt *s = NULL;
        sqlite3_prepare_v2(raw,
                           "EXPLAIN QUERY PLAN SELECT id FROM tracks WHERE profile='p' AND "
                           "endpoint='e' ORDER BY title,id LIMIT 200",
                           -1, &s, NULL);
        BOOL indexed = NO, temp = NO;
        while (sqlite3_step(s) == SQLITE_ROW) {
            NSString *plan =
                [NSString stringWithUTF8String:(const char *)sqlite3_column_text(s, 3)];
            indexed |= [plan rangeOfString:@"sort_title"].location != NSNotFound;
            temp |= [plan rangeOfString:@"TEMP B-TREE"].location != NSNotFound;
        }
        sqlite3_finalize(s);
        sqlite3_close(raw);
        NSCAssert(indexed && !temp,
                  @"title query rebuilt a temporary sort rather than using its persistent index");
#if defined(IP_IOS6)
        sqlite3_open(url.path.UTF8String,&raw);
        sqlite3_prepare_v2(raw,"PRAGMA journal_mode",-1,&s,NULL);
        NSCAssert(sqlite3_step(s)==SQLITE_ROW&&strcmp((const char *)sqlite3_column_text(s,0),"delete")==0,@"legacy bulk writes must not use amplifying WAL mode");
        sqlite3_finalize(s);sqlite3_close(raw);
        NSCAssert(![[NSFileManager defaultManager]fileExistsAtPath:[url.path stringByAppendingString:@"-wal"]],@"legacy import left a large WAL");
        NSCAssert(Query(reopen,profile,@"library",nil,@"title",@"%",0,200,0).count==0,@"legacy substring search treated percent as wildcard");
        puts("Legacy rollback journal, bounded WAL storage and literal substring search passed");
#endif
        puts("SQLite persistence, paging, natural metadata sorts, search, filters, duplicate "
             "playlists, lazy full queue/session, incremental changes, transaction rollback and "
             "indexed query plan passed");
        // Shuffled identifiers and multilingual titles exercise the ordinal pass skipped by
        // the original sequential fixture, and the bounded Unicode comparison path.
        NSURL *mixedURL=[root URLByAppendingPathComponent:@"mixed.sqlite"];
        NSMutableArray *mixed=[NSMutableArray new],*mixedIDs=[NSMutableArray new];
        for(NSUInteger n=0;n<8192;n++){
            NSString *tid=[NSString stringWithFormat:@"%08llx-id",(n*2654435761ULL)&0xffffffffULL];
            NSString *title=n%3==0?[NSString stringWithFormat:@"中文 %lu",(unsigned long)n]:[NSString stringWithFormat:@"Canción %lu",(unsigned long)n];
            [mixedIDs addObject:tid];[mixed addObject:@{@"id":tid,@"profileID":@"p",@"endpointIdentity":@"e",@"title":title,@"artist":@"Árbol",@"album":@"Colección",@"extension":@"mp3",@"metadataAutoVersion":@14,@"artworkAutoVersion":@15}];
        }
        IPLibraryDB *interrupted=[[IPLibraryDB alloc]initWithURL:mixedURL];
        __block NSUInteger progressEvents=0;interrupted.importProgress=^BOOL(NSUInteger completed,NSString *phase){progressEvents++;return completed<256;};
        NSCAssert([interrupted beginImport]&&![interrupted commitState:state tracks:mixed IDs:mixedIDs]&&!interrupted.ready&&[interrupted recordsForProfileID:@"p"].count==0&&progressEvents>=3,@"cancelled import exposed a partial library or ignored cancellation");
        IPLibraryDB *retry=[[IPLibraryDB alloc]initWithURL:mixedURL];NSCAssert(!retry.ready,@"interrupted marker was ignored after reopening");start=[NSDate date];
        NSCAssert([retry beginImport]&&[retry commitState:state tracks:mixed IDs:mixedIDs]&&!retry.ready,@"bulk records were exposed before index preparation");
        IPLibraryDB *unfinished=[[IPLibraryDB alloc]initWithURL:mixedURL];NSCAssert(!unfinished.ready,@"a process restart exposed an unfinished import");
        NSCAssert([retry buildImportIndexes]&&[retry finishImport]&&retry.ready&&[[retry trackIDs]isEqual:mixedIDs],@"restart/index finish lost shuffled record order");
        printf("Shuffled multilingual 8192-record import + indexes: %.3fs (Mac host)\n",-[start timeIntervalSinceNow]);
        NSArray *titles=@[@"Song 2",@"Song 02",@"Song 10",@"Song 000",@"Song 0",@"-2",@"2",@"2.5",@"02.05",@"a_",@"a-",@"a ",@"Straße",@"straße",@"å",@"Ａ２",@"中文2",@"中文10",@"A❤️2"];
        NSMutableArray *ordering=[NSMutableArray new],*orderIDs=[NSMutableArray new];
        for(NSUInteger n=0;n<titles.count;n++){NSString *tid=[NSString stringWithFormat:@"%03lu",(unsigned long)n];[orderIDs addObject:tid];[ordering addObject:@{@"id":tid,@"title":titles[n]}];}
        IPLibraryDB *collation=[[IPLibraryDB alloc]initWithURL:[root URLByAppendingPathComponent:@"collation.sqlite"]];NSCAssert([collation commitState:@{} tracks:ordering IDs:orderIDs]&&[collation buildImportIndexes],@"collation fixture failed");
        NSArray *expected=[ordering sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSString *(^fold)(NSString *)=^NSString *(NSString *t){return [[t stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]]lowercaseString];};NSComparisonResult r=[fold(a[@"title"])compare:fold(b[@"title"]) options:NSNumericSearch];return r==NSOrderedSame?[a[@"id"]compare:b[@"id"]]:r;}];
        NSCAssert([Query(collation,nil,@"library",nil,@"title",nil,0,200,titles.count)isEqual:[expected valueForKey:@"id"]],@"optimized collation differs from the previous Foundation order");
        puts("Cancelled/restarted import, readiness marker, shuffled multilingual records and natural collation parity passed");
        IPLibraryDB *localDB=[[IPLibraryDB alloc]initWithURL:[root URLByAppendingPathComponent:@"local.sqlite"]];
        NSArray *localRecords=@[
            @{@"id":@"native",@"profileID":@"local-library-v1",@"endpointIdentity":@"local-library-v1",@"title":@"A local",@"favorite":@YES},
            @{@"id":@"manual",@"profileID":@"remote",@"title":@"B download",@"downloaded":@YES},
            @{@"id":@"auto",@"profileID":@"remote",@"title":@"C cached"},
            @{@"id":@"online",@"profileID":@"remote",@"title":@"D remote"},
            @{@"id":@"missing",@"profileID":@"local-library-v1",@"endpointIdentity":@"local-library-v1",@"unavailableRemote":@YES,@"title":@"E missing"}];
        NSCAssert([localDB commitState:@{} tracks:localRecords IDs:[localRecords valueForKey:@"id"]]&&[localDB buildImportIndexes],@"local fixture failed");
        NSMutableDictionary *localProfile=[@{@"id":@"local-library-v1",@"endpointIdentity":@"local-library-v1",@"isLocal":@YES,@"localCacheIDs":@[@"auto",@"manual"]}mutableCopy];
        NSCAssert(([Query(localDB,localProfile,@"library",nil,@"title",nil,0,20,1)isEqual:@[@"native"]]),@"local must exclude player downloads/cache and missing or remote tracks");
        NSCAssert([Query(localDB,localProfile,@"library",nil,@"title",@"cached",0,20,0)isEqual:@[]],@"remote cached track leaked into local search");
        localProfile[@"localCacheIDs"]=@[];
        NSCAssert([Query(localDB,localProfile,@"library",nil,@"title",nil,0,1,1)isEqual:@[@"native"]],@"local paging failed");
        puts("Local SQLite isolation from manual/automatic downloads, missing files, search and paging passed");
        [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
    }
    return 0;
}

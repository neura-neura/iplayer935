#import "IPStrings.h"
#import "IPLibraryDB.h"
#import <sqlite3.h>
static NSString *Fold(NSString *s) {
    static NSLocale *locale;static NSCache *cache;static dispatch_once_t once;
    dispatch_once(&once,^{locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];cache=[NSCache new];cache.countLimit=2048;});
    if(!s.length)return @"";NSString *folded=[cache objectForKey:s];if(!folded){folded=[[s stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:locale]lowercaseString];[cache setObject:folded forKey:s];}return folded;
}
static int Natural(void *ctx,int an,const void *a,int bn,const void *b) {
    const unsigned char *aa=a,*bb=b;BOOL ascii=YES;
    for(int n=0;n<an;n++)if(aa[n]>=128){ascii=NO;break;}
    if(ascii)for(int n=0;n<bn;n++)if(bb[n]>=128){ascii=NO;break;}
    if(ascii){
        int i=0,j=0;
        while(i<an&&j<bn){
            if(aa[i]>='0'&&aa[i]<='9'&&bb[j]>='0'&&bb[j]<='9'){
                int ae=i,be=j;while(ae<an&&aa[ae]>='0'&&aa[ae]<='9')ae++;while(be<bn&&bb[be]>='0'&&bb[be]<='9')be++;
                while(i<ae&&aa[i]=='0')i++;while(j<be&&bb[j]=='0')j++;
                if(ae-i!=be-j)return ae-i<be-j?-1:1;
                while(i<ae&&j<be){if(aa[i]!=bb[j])return aa[i]<bb[j]?-1:1;i++;j++;}i=ae;j=be;
            }else{if(aa[i]!=bb[j])return aa[i]<bb[j]?-1:1;i++;j++;}
        }return i<an?1:j<bn?-1:0;
    }
    // CREATE INDEX may compare millions of Unicode titles; never retain its temporary strings.
    @autoreleasepool {
        NSString *left=[[NSString alloc]initWithBytes:a length:an encoding:NSUTF8StringEncoding]?:@"",*right=[[NSString alloc]initWithBytes:b length:bn encoding:NSUTF8StringEncoding]?:@"";
        return (int)[left compare:right options:NSNumericSearch];
    }
}
static void Bind(sqlite3_stmt *stmt, int i, id value) {
    if ([value isKindOfClass:[NSNumber class]])
        sqlite3_bind_double(stmt, i, [value doubleValue]);
    else
        sqlite3_bind_text(stmt, i, [value ?: @"" UTF8String], -1, SQLITE_TRANSIENT);
}
static BOOL NeedsTags(NSDictionary *t) {
    if (t[@"unsupportedReason"] || [t[@"unavailableRemote"] boolValue])
        return NO;
    NSInteger v = [t[@"metadataAutoVersion"] integerValue];
    BOOL mp3 = [[t[@"extension"] lowercaseString] isEqual:@"mp3"];
    if (mp3 && ![t[@"artwork"] length] && ![t[@"metadataCacheState"] isEqual:@"empty"] &&
        [t[@"artworkAutoVersion"] integerValue] < 15)
        return YES;
    if (v >= 14)
        return NO;
    if (!mp3 && (v >= 13 || [t[@"metadataLoaded"] boolValue]))
        return NO;
    if (mp3 && [t[@"metadataLoaded"] boolValue] && [t[@"artist"] length] && [t[@"album"] length])
        return NO;
    return YES;
}
@interface IPLibraryDB ()
@property(nonatomic, strong) NSError *error;
@end
@implementation IPLibraryDB {
    sqlite3 *_db;
    NSRecursiveLock *_lock;
    dispatch_queue_t _reader;
    NSArray *_ids, *_members;
    NSMutableDictionary *_counts;
}
- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _lock = [NSRecursiveLock new];
        _counts = [NSMutableDictionary new];
        _reader = dispatch_queue_create("org.neura.library-sqlite", DISPATCH_QUEUE_SERIAL);
        [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];
        if (sqlite3_open_v2(url.path.UTF8String, &_db,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                            NULL) != SQLITE_OK) {
            [self failure];
            return self;
        }
        sqlite3_busy_timeout(_db, 5000);
        sqlite3_create_collation(_db, "IPNATURAL", SQLITE_UTF8, NULL, Natural);
        [self exec:@"PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-2048; "
                   @"CREATE TABLE IF NOT EXISTS info (key TEXT PRIMARY KEY,json BLOB NOT NULL); "
                   @"CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY, ordinal INTEGER NOT "
                   @"NULL, profile TEXT, endpoint TEXT, title TEXT COLLATE IPNATURAL, artist TEXT "
                   @"COLLATE IPNATURAL, album TEXT COLLATE IPNATURAL, genre TEXT COLLATE "
                   @"IPNATURAL, search TEXT, recent REAL, number REAL, favorite INTEGER, "
                   @"downloaded INTEGER, pending INTEGER, needed INTEGER, emptyTag INTEGER, "
                   @"failedTag INTEGER, unsupported INTEGER, unavailable INTEGER, extension "
                   @"TEXT,json BLOB NOT NULL); CREATE TEMP TABLE query_members(position INTEGER "
                   @"PRIMARY KEY,id TEXT); CREATE INDEX query_member_id ON query_members(id);"];
        if([self ready])[self buildImportIndexes];
    }
    return self;
}
- (BOOL)beginImport {
    [_lock lock];BOOL ok=[self exec:@"INSERT OR REPLACE INTO info VALUES('importing','1'); DROP INDEX IF EXISTS needed_tags; DROP INDEX IF EXISTS track_favorites; DROP INDEX IF EXISTS track_downloads; DROP INDEX IF EXISTS library_order;"];
    for(NSString *key in @[@"title",@"artist",@"album",@"genre",@"recent",@"number"]){
        ok=ok&&[self exec:[NSString stringWithFormat:@"DROP INDEX IF EXISTS sort_%@; DROP INDEX IF EXISTS global_%@;",key,key]];
    }
    [_lock unlock];return ok;
}
- (BOOL)buildImportIndexes {
    [_lock lock];
        for (NSString *key in @[ @"title", @"artist", @"album", @"genre", @"recent", @"number" ]) {
            if(self.importProgress&&!self.importProgress(NSUIntegerMax,[NSString stringWithFormat:IPL(@"Preparando orden: %@"),IPL((@{@"title":@"Título (A–Z)",@"artist":@"Artista",@"album":@"Álbum",@"genre":@"Género",@"recent":@"Más recientes",@"number":@"Número de pista"})[key])])){[_lock unlock];return NO;}
            NSString *direction = [key isEqual:@"recent"] ? @" DESC" : @"",
                     *tail = [key isEqual:@"title"] ? @",id" : @",title,id";
            [self exec:[NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS sort_%@ ON "
                                                  @"tracks(profile,endpoint,%@%@%@); CREATE INDEX "
                                                  @"IF NOT EXISTS global_%@ ON tracks(%@%@%@);",
                                                  key, key, direction, tail, key, key, direction,
                                                  tail]];
        }
        [self exec:@"CREATE INDEX IF NOT EXISTS library_order ON tracks(ordinal,id); CREATE INDEX IF NOT EXISTS needed_tags ON tracks(profile,endpoint,needed); "
                   @"CREATE INDEX IF NOT EXISTS track_favorites ON tracks(favorite,title,id); "
                   @"CREATE INDEX IF NOT EXISTS track_downloads ON tracks(downloaded,title,id);"];
    BOOL ok=self.error==nil;
    [_lock unlock];return ok;
}
- (BOOL)finishImport {[_lock lock];BOOL ok=[self exec:@"DELETE FROM info WHERE key='importing'"];[_lock unlock];return ok;}
- (void)dealloc {
    if (_db)
        sqlite3_close(_db);
}
- (void)failure {
    self.error = [NSError
        errorWithDomain:@"IPLibrarySQLite"
                   code:_db ? sqlite3_errcode(_db) : 1
               userInfo:@{
                   NSLocalizedDescriptionKey : _db
                       ? ([NSString stringWithUTF8String:sqlite3_errmsg(_db)] ?: IPL(@"SQLite error"))
                       : IPL(@"Could not open library database")
               }];
}
- (BOOL)exec:(NSString *)sql {
    if (!_db || sqlite3_exec(_db, sql.UTF8String, NULL, NULL, NULL) != SQLITE_OK) {
        [self failure];
        return NO;
    }
    return YES;
}
- (sqlite3_stmt *)prepare:(NSString *)sql values:(NSArray *)values {
    sqlite3_stmt *s = NULL;
    if (!_db || sqlite3_prepare_v2(_db, sql.UTF8String, -1, &s, NULL) != SQLITE_OK) {
        [self failure];
        return NULL;
    }
    for (NSUInteger i = 0; i < values.count; i++)
        Bind(s, (int)i + 1, values[i]);
    return s;
}
- (NSDictionary *)json:(sqlite3_stmt *)s column:(int)c {
    const void *bytes = sqlite3_column_blob(s, c);
    int n = sqlite3_column_bytes(s, c);
    id value = bytes ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:n]
                                                       options:NSJSONReadingMutableContainers
                                                         error:NULL]
                     : nil;
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}
- (NSDictionary *)state {
    [_lock lock];
    sqlite3_stmt *s = [self prepare:@"SELECT json FROM info WHERE key='state'" values:@[]];
    NSDictionary *state = sqlite3_step(s) == SQLITE_ROW ? [self json:s column:0] : nil;
    sqlite3_finalize(s);
    [_lock unlock];
    return state;
}
- (BOOL)ready {
    [_lock lock];sqlite3_stmt *s=[self prepare:@"SELECT 1 FROM info WHERE key='importing'" values:@[]];BOOL importing=sqlite3_step(s)==SQLITE_ROW;sqlite3_finalize(s);BOOL ready=!importing&&[self state]!=nil;[_lock unlock];return ready;
}
- (NSArray *)trackIDs {
    [_lock lock];
    if (!_ids) {
        NSMutableArray *ids = [NSMutableArray new];
        sqlite3_stmt *s = [self prepare:@"SELECT id FROM tracks ORDER BY ordinal,id" values:@[]];
        while (sqlite3_step(s) == SQLITE_ROW)
            [ids addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s, 0)]];
        sqlite3_finalize(s);
        _ids = [ids copy];
    }
    NSArray *result = _ids;
    [_lock unlock];
    return result;
}
- (NSDictionary *)track:(NSString *)tid {
    [_lock lock];
    sqlite3_stmt *s = [self prepare:@"SELECT json FROM tracks WHERE id=?" values:@[ tid ?: @"" ]];
    NSDictionary *t = sqlite3_step(s) == SQLITE_ROW ? [self json:s column:0] : nil;
    sqlite3_finalize(s);
    [_lock unlock];
    return t;
}
- (NSArray *)recordsForIDs:(NSArray *)ids {
    [_lock lock];
    NSMutableArray *result = [NSMutableArray new];
    sqlite3_stmt *s = [self prepare:@"SELECT json FROM tracks WHERE id=?" values:@[]];
    for (NSString *tid in ids) {
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        Bind(s, 1, tid);
        if (sqlite3_step(s) == SQLITE_ROW) {
            NSDictionary *t = [self json:s column:0];
            if (t)
                [result addObject:t];
        }
    }
    sqlite3_finalize(s);
    [_lock unlock];
    return result;
}
- (NSArray *)recordsForProfileID:(NSString *)pid {
    [_lock lock];
    sqlite3_stmt *s = [self prepare:@"SELECT json FROM tracks WHERE profile=?" values:@[ pid ]];
    NSMutableArray *records = [NSMutableArray new];
    while (sqlite3_step(s) == SQLITE_ROW) {
        NSDictionary *t = [self json:s column:0];
        if (t)
            [records addObject:t];
    }
    sqlite3_finalize(s);
    [_lock unlock];
    return records;
}
- (BOOL)writeTracks:(NSArray *)tracks {
    sqlite3_stmt *s =
        [self prepare:@"INSERT OR REPLACE INTO tracks VALUES(?,COALESCE((SELECT ordinal FROM "
                      @"tracks WHERE id=?),2147483647),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
               values:@[]];
    if (!s)
        return NO;
    BOOL ok = YES;
    NSUInteger completed=0;
    for (NSDictionary *t in tracks) {
        if(self.importProgress&&completed%128==0&&!self.importProgress(completed,IPL(@"Convirtiendo canciones"))){ok=NO;break;}
        completed++;
        @autoreleasepool {
            if (![t[@"id"] length])
                continue;
            if (![NSJSONSerialization isValidJSONObject:t]) {
                ok = NO;
                break;
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:t options:0 error:NULL];
            if (!json) {
                ok = NO;
                break;
            }
            NSString *title = Fold(t[@"title"]), *artist = Fold(t[@"artist"]),
                     *album = Fold(t[@"album"]), *genre = Fold(t[@"genre"]);
            NSArray *values = @[
                t[@"id"],
                t[@"id"],
                t[@"profileID"] ?: @"",
                t[@"endpointIdentity"] ?: @"",
                title,
                artist,
                album,
                genre,
                [NSString stringWithFormat:@"%@ %@ %@ %@", title, artist, album, genre],
                @([t[@"modifiedAt"] doubleValue] ?: [t[@"addedAt"] doubleValue]),
                t[@"trackNumber"] ?: @0,
                @([t[@"favorite"] boolValue]),
                @([t[@"downloaded"] boolValue]),
                @([t[@"metadataPending"] boolValue] && !t[@"unsupportedReason"]),
                @(NeedsTags(t)),
                @([t[@"metadataCacheState"] isEqual:@"empty"]),
                @([t[@"metadataCacheState"] isEqual:@"error"]),
                @(t[@"unsupportedReason"] != nil),
                @([t[@"unavailableRemote"] boolValue]),
                t[@"extension"] ?: @"unknown"
            ];
            sqlite3_reset(s);
            sqlite3_clear_bindings(s);
            for (NSUInteger i = 0; i < values.count; i++)
                Bind(s, (int)i + 1, values[i]);
            sqlite3_bind_blob(s, 21, json.bytes, (int)json.length, SQLITE_TRANSIENT);
            if (sqlite3_step(s) != SQLITE_DONE) {
                [self failure];
                ok = NO;
                break;
            }
        }
    }
    sqlite3_finalize(s);
    return ok;
}
- (BOOL)updateState:(NSDictionary *)state {
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:0 error:NULL];
    if (!json) return NO;
    [_lock lock];
    sqlite3_stmt *s = [self prepare:@"INSERT OR REPLACE INTO info VALUES('state',?)" values:@[]];
    BOOL ok = s != NULL;
    if (ok) {
        sqlite3_bind_blob(s, 1, json.bytes, (int)json.length, SQLITE_TRANSIENT);
        ok = sqlite3_step(s) == SQLITE_DONE;
    }
    sqlite3_finalize(s);
    if (!ok) [self failure];
    [_lock unlock];
    return ok;
}
- (BOOL)updateTracks:(NSArray *)tracks {
    [_lock lock];
    BOOL ok = [self exec:@"BEGIN IMMEDIATE"];
    if (ok)
        ok = [self writeTracks:tracks];
    if (ok) {
        ok = [self exec:@"COMMIT"];
        if (!ok)
            [self exec:@"ROLLBACK"];
    } else
        [self exec:@"ROLLBACK"];
    if (ok)
        [_counts removeAllObjects];
    [_lock unlock];
    return ok;
}
- (BOOL)commitState:(NSDictionary *)state tracks:(NSArray *)tracks IDs:(NSArray *)ids {
    [_lock lock];
    BOOL ok = [self exec:@"BEGIN IMMEDIATE"];
    if (ok)
        ok = [self writeTracks:tracks];
    if (ok && ![[self trackIDs] isEqual:ids]) {
        NSSet *retained = [NSSet setWithArray:ids];
        sqlite3_stmt *del = [self prepare:@"DELETE FROM tracks WHERE id=?" values:@[]];
        for (NSString *tid in [self trackIDs])
            if (![retained containsObject:tid]) {
                sqlite3_reset(del);
                Bind(del, 1, tid);
                if (sqlite3_step(del) != SQLITE_DONE)
                    ok = NO;
            }
        sqlite3_finalize(del);
        sqlite3_stmt *order = [self prepare:@"UPDATE tracks SET ordinal=? WHERE id=?" values:@[]];
        NSUInteger n = 0;
        for (NSString *tid in ids) {
            sqlite3_reset(order);
            sqlite3_bind_int64(order, 1, n++);
            Bind(order, 2, tid);
            if (sqlite3_step(order) != SQLITE_DONE)
                ok = NO;
        }
        sqlite3_finalize(order);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:0 error:NULL];
    sqlite3_stmt *s = [self prepare:@"INSERT OR REPLACE INTO info VALUES('state',?)" values:@[]];
    sqlite3_bind_blob(s, 1, json.bytes, (int)json.length, SQLITE_TRANSIENT);
    if (!json || sqlite3_step(s) != SQLITE_DONE)
        ok = NO;
    sqlite3_finalize(s);
    if (ok) {
        ok = [self exec:@"COMMIT"];
        if (!ok)
            [self exec:@"ROLLBACK"];
    } else
        [self exec:@"ROLLBACK"];
    if (ok) {
        _ids = [ids copy];
        [_counts removeAllObjects];
    } else
        [self failure];
    [_lock unlock];
    return ok;
}
- (NSDictionary *)metadataStatus:(NSDictionary *)p {
    [_lock lock];
    sqlite3_stmt *s =
        [self prepare:@"SELECT count(*),COALESCE(sum(needed),0),COALESCE(sum(CASE WHEN needed=0 "
                      @"THEN emptyTag ELSE 0 END),0),COALESCE(sum(CASE WHEN needed=1 THEN "
                      @"failedTag ELSE 0 END),0) FROM tracks WHERE profile=? AND endpoint=? AND "
                      @"unsupported=0 AND unavailable=0"
               values:@[ p[@"id"] ?: @"", p[@"endpointIdentity"] ?: @"" ]];
    NSDictionary *r = @{};
    if (sqlite3_step(s) == SQLITE_ROW)
        r = @{
            @"total" : @(sqlite3_column_int64(s, 0)),
            @"pending" : @(sqlite3_column_int64(s, 1)),
            @"cached" : @(sqlite3_column_int64(s, 0) - sqlite3_column_int64(s, 1)),
            @"empty" : @(sqlite3_column_int64(s, 2)),
            @"failed" : @(sqlite3_column_int64(s, 3))
        };
    sqlite3_finalize(s);
    [_lock unlock];
    return r;
}
- (NSArray *)pendingMetadata:(NSDictionary *)p before:(double)date limit:(NSUInteger)limit {
    [_lock lock];
    sqlite3_stmt *s =
        [self prepare:@"SELECT json FROM tracks WHERE profile=? AND endpoint=? AND needed=1"
               values:@[ p[@"id"] ?: @"", p[@"endpointIdentity"] ?: @"" ]];
    NSMutableArray *tracks = [NSMutableArray new];
    while (sqlite3_step(s) == SQLITE_ROW) {
        NSDictionary *t = [self json:s column:0];
        if ([t[@"metadataRetryAfter"] doubleValue] <= date)
            [tracks addObject:t];
        if (tracks.count >= limit)
            break;
    }
    sqlite3_finalize(s);
    [_lock unlock];
    return tracks;
}
- (NSDictionary *)diagnosticCounts {
    [_lock lock];
    sqlite3_stmt *s =
        [self prepare:@"SELECT extension,count(*),sum(downloaded),sum(unsupported),sum(pending) "
                      @"FROM tracks GROUP BY extension"
               values:@[]];
    NSMutableDictionary *ext = [NSMutableDictionary new];
    NSUInteger offline = 0, unsupported = 0, pending = 0;
    while (sqlite3_step(s) == SQLITE_ROW) {
        ext[[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s, 0)]] =
            @(sqlite3_column_int64(s, 1));
        offline += sqlite3_column_int64(s, 2);
        unsupported += sqlite3_column_int64(s, 3);
        pending += sqlite3_column_int64(s, 4);
    }
    sqlite3_finalize(s);
    [_lock unlock];
    return @{
        @"extensions" : ext,
        @"offline" : @(offline),
        @"unsupported" : @(unsupported),
        @"pending" : @(pending)
    };
}
- (void)queryProfile:(NSDictionary *)profile
                mode:(NSString *)mode
         playlistIDs:(NSArray *)playlistIDs
                sort:(NSString *)sort
               query:(NSString *)query
              offset:(NSUInteger)offset
               limit:(NSUInteger)limit
          completion:(void (^)(NSArray *, NSUInteger, NSUInteger, NSArray *))completion {
    NSDictionary *p = [profile copy];
    NSArray *members = [playlistIDs copy];
    NSString *kind = [mode copy], *key = [sort copy] ?: @"title", *search = Fold(query);
    dispatch_async(_reader, ^{
        @autoreleasepool {
            [self->_lock lock];
            if (members && ![self->_members isEqual:members]) {
                [self exec:@"DELETE FROM query_members"];
                sqlite3_stmt *s = [self prepare:@"INSERT INTO query_members VALUES(?,?)"
                                         values:@[]];
                NSUInteger n = 0;
                for (NSString *tid in members) {
                    sqlite3_reset(s);
                    sqlite3_bind_int64(s, 1, n++);
                    Bind(s, 2, tid);
                    sqlite3_step(s);
                }
                sqlite3_finalize(s);
                self->_members = members;
            }
            BOOL local=[p[@"isLocal"]boolValue];
            BOOL playlist = members && [key isEqual:@"playlist"];
            NSMutableArray *where = [NSMutableArray new], *values = [NSMutableArray new];
            if (p) {
                [where addObject:local?@"t.profile=? AND t.endpoint=? AND t.unavailable=0":@"t.profile=? AND t.endpoint=?"];
                [values addObjectsFromArray:@[ p[@"id"] ?: @"", p[@"endpointIdentity"] ?: @"" ]];
            }
            if (members && !playlist)
                [where addObject:@"EXISTS (SELECT 1 FROM query_members m WHERE m.id=t.id)"];
            if ([kind isEqual:@"favorites"])
                [where addObject:@"t.favorite=1"];
            if ([kind isEqual:@"downloads"])
                [where addObject:@"t.downloaded=1"];
            if (search.length) {
                [where addObject:@"instr(t.search,?)>0"];
                [values addObject:search];
            }
            NSString *from = [NSString
                stringWithFormat:@"FROM tracks t%@%@",
                                 playlist ? @" JOIN query_members m ON m.id=t.id" : @"",
                                 where.count
                                     ? [@" WHERE " stringByAppendingString:
                                                       [where componentsJoinedByString:@" AND "]]
                                     : @""];
            NSString *column = [@[ @"title", @"artist", @"album", @"genre" ] containsObject:key]
                                   ? key
                               : [key isEqual:@"recent"]      ? @"recent"
                               : [key isEqual:@"trackNumber"] ? @"number"
                                                              : @"title";
            NSString *order =
                playlist ? @"m.position"
                         : [NSString stringWithFormat:@"t.%@%@,t.title,t.id", column,
                                                      [key isEqual:@"recent"] ? @" DESC" : @""];
            NSArray *countKey = @[
                p[@"id"] ?: @"", p[@"endpointIdentity"] ?: @"", kind ?: @"", search, members ?: @[],
                @(playlist)
            ];
            NSArray *counts = self->_counts[countKey];
            NSUInteger total = 0, pending = 0;
            sqlite3_stmt *s = NULL;
            if (counts) {
                total = [counts[0] unsignedIntegerValue];
                pending = [counts[1] unsignedIntegerValue];
            } else {
                s = [self prepare:[@"SELECT count(*),COALESCE(sum(t.pending),0) "
                                      stringByAppendingString:from]
                           values:values];
                if (sqlite3_step(s) == SQLITE_ROW) {
                    total = sqlite3_column_int64(s, 0);
                    pending = sqlite3_column_int64(s, 1);
                }
                sqlite3_finalize(s);
                if (self->_counts.count >= 8)
                    [self->_counts removeAllObjects];
                self->_counts[countKey] = @[ @(total), @(pending) ];
            }
            NSMutableArray *args = [values mutableCopy];
            [args addObjectsFromArray:@[ limit ? @(limit) : @(-1), @(offset) ]];
            s = [self
                prepare:[NSString stringWithFormat:@"SELECT t.id %@ ORDER BY %@ LIMIT ? OFFSET ?",
                                                   from, order]
                 values:args];
            NSMutableArray *ids = [NSMutableArray new];
            while (sqlite3_step(s) == SQLITE_ROW)
                [ids addObject:[NSString
                                   stringWithUTF8String:(const char *)sqlite3_column_text(s, 0)]];
            sqlite3_finalize(s);
            NSArray *records = limit ? [self recordsForIDs:ids] : @[];
            [self->_lock unlock];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion)
                    completion(ids, total, pending, records);
            });
        }
    });
}
@end

@implementation IPTrackCollection {
    IPLibraryDB *_database;
    NSMutableArray *_trackIDs;
    NSMutableSet *_members;
    NSMutableDictionary *_models, *_saved;
}
- (instancetype)initWithDatabase:(IPLibraryDB *)db IDs:(NSArray *)ids {
    if ((self = [super init])) {
        _database = db;
        _trackIDs = [ids mutableCopy];
        _members = [NSMutableSet setWithArray:ids];
        _models = [NSMutableDictionary new];
        _saved = [NSMutableDictionary new];
    }
    return self;
}
- (NSUInteger)count {
    return _trackIDs.count;
}
- (NSArray *)trackIDs {
    return [_trackIDs copy];
}
- (NSArray *)materializedTracks {
    return _models.allValues;
}
- (NSArray *)changedTracks {
    NSMutableArray *changed = [NSMutableArray new];
    for (NSString *tid in _models)
        if (![_models[tid] isEqual:_saved[tid]])
            [changed addObject:_models[tid]];
    return changed;
}
- (void)acknowledgeTracks:(NSArray *)records {
    for (NSDictionary *t in records)
        if ([_members containsObject:t[@"id"]])
            _saved[t[@"id"]] = [t copy];
}
- (NSMutableDictionary *)trackForID:(NSString *)tid {
    if (!_members || ![_members containsObject:tid])
        return nil;
    NSMutableDictionary *t = _models[tid];
    if (!t) {
        t = [[_database track:tid] mutableCopy];
        if (t) {
            _models[tid] = t;
            _saved[tid] = [t copy];
        }
    }
    return t;
}
- (NSArray *)materializeRecords:(NSArray *)records {
    NSMutableArray *rows = [NSMutableArray new];
    for (NSDictionary *t in records) {
        NSString *tid = t[@"id"];
        if (![_members containsObject:tid])
            continue;
        if (!_models[tid]) {
            _models[tid] = [t mutableCopy];
            _saved[tid] = [t copy];
        }
        [rows addObject:_models[tid]];
    }
    return rows;
}
- (NSArray *)materializeIDs:(NSArray *)ids {
    NSMutableArray *missing = [NSMutableArray new];
    for (NSString *tid in ids)
        if (!_models[tid] && [_members containsObject:tid])
            [missing addObject:tid];
    for (NSDictionary *t in [_database recordsForIDs:missing]) {
        _models[t[@"id"]] = [t mutableCopy];
        _saved[t[@"id"]] = [t copy];
    }
    NSMutableArray *rows = [NSMutableArray new];
    for (NSString *tid in ids)
        if ([self trackForID:tid])
            [rows addObject:_models[tid]];
    return rows;
}
- (id)objectAtIndex:(NSUInteger)i {
    NSString *tid = _trackIDs[i];
    return [self trackForID:tid];
}
- (void)insertObject:(id)obj atIndex:(NSUInteger)i {
    NSString *tid = obj[@"id"];
    NSParameterAssert(tid);
    NSAssert(![_members containsObject:tid], IPL(@"Duplicate library ID"));
    [_trackIDs insertObject:tid atIndex:i];
    [_members addObject:tid];
    _models[tid] = [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [obj mutableCopy];
}
- (void)removeObjectAtIndex:(NSUInteger)i {
    NSString *tid = _trackIDs[i];
    [_trackIDs removeObjectAtIndex:i];
    [_members removeObject:tid];
    [_models removeObjectForKey:tid];
    [_saved removeObjectForKey:tid];
}
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)obj {
    [self removeObjectAtIndex:i];
    [self insertObject:obj atIndex:i];
}
- (void)replaceProfileRecords:(NSArray *)records previous:(NSDictionary *)previous {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSString *tid in _trackIDs)
        if (!previous[tid])
            [ids addObject:tid];
    for (NSDictionary *record in records) {
        NSString *tid = record[@"id"];
        [ids addObject:tid];
        if (_models[tid]) {
            if (![_models[tid] isEqual:record])
                [_models[tid] setDictionary:record];
        } else if (![record isEqual:previous[tid]]) {
            _models[tid] = [record mutableCopy];
            if (previous[tid])
                _saved[tid] = [previous[tid] copy];
        }
    }
    _trackIDs = ids;
    _members = [NSMutableSet setWithArray:ids];
    for (NSString *tid in [_models.allKeys copy])
        if (![_members containsObject:tid]) {
            [_models removeObjectForKey:tid];
            [_saved removeObjectForKey:tid];
        }
}
- (id)copyWithZone:(NSZone *)zone {
    return [self queueForIDs:_trackIDs];
}
- (NSArray *)queueForIDs:(NSArray *)ids {
    return [[IPTrackList alloc] initWithIDs:ids collection:self];
}
@end
@implementation IPTrackList {
    IPTrackCollection *_collection;
    NSArray *_trackIDs;
}
- (instancetype)initWithIDs:(NSArray *)ids collection:(IPTrackCollection *)collection {
    if ((self = [super init])) {
        _trackIDs = [ids copy];
        _collection = collection;
    }
    return self;
}
- (NSArray *)trackIDs {
    return _trackIDs;
}
- (NSUInteger)count {
    return _trackIDs.count;
}
- (id)objectAtIndex:(NSUInteger)i {
    return [_collection trackForID:_trackIDs[i]] ?: @{
        @"id" : _trackIDs[i],
        @"title" : IPL(@"Canción no disponible"),
        @"unsupportedReason" : IPL(@"La canción ya no está en la biblioteca.")
    };
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}
@end

#import "IPStrings.h"
#import "IPStore.h"
#import "IPLocalLibrary.h"
#import "IPLibraryDB.h"
#import "IPLibraryIndex.h"
#import "IPSMB.h"
#import "IPHTTPServer.h"
#import "IPID3.h"
#import "IPSmartCache.h"
#import "IPPCMServer.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#endif
#import <ImageIO/ImageIO.h>

static NSString * const IPStoreErrorDomain = @"IPStoreErrorDomain";
static NSString * const IPStoreKeychainService = @"com.codex.iplayer935.smb";
static const NSUInteger IPStoreChunkSize = 256 * 1024;
static void *IPStoreQueueKey = &IPStoreQueueKey;
static BOOL IPNeedsTags(NSDictionary *track) {
    if(track[@"unsupportedReason"]||[track[@"unavailableRemote"]boolValue])return NO;
    NSInteger version=[track[@"metadataAutoVersion"]integerValue];
    BOOL mp3=[[track[@"extension"]lowercaseString]isEqual:@"mp3"];
    // Old readers could finish text before reaching APIC. Repair only missing covers once.
    if(mp3&&![track[@"artwork"]length]&&![track[@"metadataCacheState"]isEqual:@"empty"]&&[track[@"artworkAutoVersion"]integerValue]<15)return YES;
    if(version>=14)return NO;
    if(!mp3&&(version>=13||[track[@"metadataLoaded"]boolValue]))return NO;
    if(mp3&&[track[@"metadataLoaded"]boolValue]&&[track[@"artist"]length]&&[track[@"album"]length])return NO;
    return YES;
}

static NSError *IPStoreError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:IPStoreErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: IPL(@"Store operation failed.")}];
}

static id IPStoreFreeze(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:[value count]];
        [value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) { if (key && object) copy[[key copy]] = IPStoreFreeze(object); }];
        return [copy copy];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray arrayWithCapacity:[value count]];
        for (id object in value) [copy addObject:IPStoreFreeze(object) ?: [NSNull null]];
        return [copy copy];
    }
    return [value copy];
}

static NSString *IPStoreHash(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

static NSArray *IPMetadataItems(AVAsset *asset) {
    NSMutableArray *items=[NSMutableArray arrayWithArray:asset.commonMetadata?:@[]];
    for(NSString *format in asset.availableMetadataFormats) [items addObjectsFromArray:[asset metadataForFormat:format]];
    return items;
}

static NSData *IPSmallArtwork(NSData *data) {
    if(!data.length || data.length>16*1024*1024)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    if(!source)return nil;
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@320,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES});
    CFRelease(source);if(!image)return nil;
    #if TARGET_OS_IPHONE
    NSData *small=UIImageJPEGRepresentation([UIImage imageWithCGImage:image],0.8);
#else
    NSMutableData *small=[NSMutableData data];
    CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)small,CFSTR("public.jpeg"),1,NULL);
    if(dest){CGImageDestinationAddImage(dest,image,NULL);CGImageDestinationFinalize(dest);CFRelease(dest);}
#endif
    CGImageRelease(image);return small;
}

@interface IPStore ()
@property(nonatomic,strong,readwrite) IPLibraryDB *database;
@property(nonatomic,readwrite) BOOL libraryLoaded;
@property(nonatomic) BOOL libraryLoading;
@property(nonatomic,strong) NSMutableDictionary *builtInLocalProfile;
@property(nonatomic) BOOL localScanRunning;
@property(nonatomic) BOOL observingLocalMedia;
@property(nonatomic) NSTimeInterval lastLocalScan;
@property(nonatomic) BOOL exampleProfileSeeded;
@property(nonatomic,copy,readwrite) NSDictionary *preparationStatus;
@property(nonatomic,strong) IPLibraryIndex *legacyIndex;
@property(nonatomic,strong) NSDictionary *preparationSnapshot;
@property(nonatomic,strong) NSDictionary *preparationLatest;
@property(nonatomic,strong) NSMutableDictionary *preparationUpdates;
@property(nonatomic,strong) IPLibraryDB *preparingDatabase;
@property(nonatomic,strong) dispatch_queue_t preparationQueue;
@property(nonatomic) NSUInteger preparationRevision;
@property(atomic) BOOL preparationCancelled;
@property(nonatomic) BOOL preparationWantsRunning;
@property(nonatomic) BOOL preparationRunning;
@property(nonatomic) NSTimeInterval preparationStarted;
@property (nonatomic, strong, readwrite) NSMutableArray<NSMutableDictionary *> *profiles;
@property (nonatomic, strong, readwrite) NSMutableArray<NSMutableDictionary *> *tracks;
@property (nonatomic, strong, readwrite) NSMutableArray<NSMutableDictionary *> *playlists;
@property (nonatomic, readwrite) unsigned long long cacheBytes;
@property (nonatomic, copy, readwrite) NSString *lastScanWarning;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_queue_t metadataQueue;
@property (nonatomic, strong) dispatch_queue_t persistenceQueue;
@property (nonatomic, strong) NSURL *supportURL;
@property (nonatomic, strong) NSURL *cacheURL;
@property (nonatomic, strong) NSURL *artworkURL;
@property (nonatomic, strong) NSURL *favoritesURL;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *favoriteOverrides;
@property (nonatomic, strong) NSMutableDictionary *decodedMetadata;
@property (nonatomic, strong) NSMutableDictionary *trackLookup;
@property (nonatomic) BOOL metadataWritePending;
@property (atomic) NSUInteger automaticGeneration;
@property (atomic) BOOL automaticRunning;
@property (nonatomic, copy) NSString *automaticProfile;
@property (nonatomic, copy) NSArray *priorityIDs;
@property (nonatomic, strong) NSMutableSet *refreshingProfiles;
@property (atomic, copy) NSString *automaticCurrent;
@property (atomic, copy) NSString *automaticError;
@property (atomic) NSTimeInterval automaticRetryAfter;
@property (nonatomic) unsigned long long storedCacheLimit;
@property (nonatomic, strong) IPHTTPServer *activeMetadataServer;
@property (nonatomic, strong) AVURLAsset *activeMetadataAsset;
@property (nonatomic) NSUInteger metadataGeneration;
- (BOOL)loadMetadataForTrack:(NSMutableDictionary *)track profile:(NSDictionary *)profile generation:(NSUInteger)generation;
- (NSArray *)importPlaylists:(NSArray *)m3us profile:(NSDictionary *)profile root:(NSString *)root tracks:(NSArray *)tracks progress:(IPStoreProgress)progress;
- (NSString *)resolvePlaylistReference:(NSString *)reference base:(NSString *)base root:(NSString *)root profile:(NSDictionary *)profile knownPaths:(NSSet *)knownPaths;
- (NSString *)identityForProfile:(NSDictionary *)profile;
- (instancetype)initWithSupportURL:(NSURL *)supportURL;
- (instancetype)initWithSupportURL:(NSURL *)supportURL deferred:(BOOL)deferred;
- (instancetype)initWithSupportURL:(NSURL *)supportURL deferred:(BOOL)deferred migrate:(BOOL)migrate;
@end

@implementation IPStore {
    unsigned long long _cacheBytes;
}

+ (instancetype)sharedStore { static IPStore *store; static dispatch_once_t once; dispatch_once(&once, ^{ store = [[self alloc] initPrivate]; }); return store; }
+ (instancetype)shared { return [self sharedStore]; }

- (instancetype)init { return [IPStore sharedStore]; }

- (NSMutableDictionary *)localProfile {
    if(!self.builtInLocalProfile){
        self.builtInLocalProfile=[@{@"id":IPLocalProfileID,@"endpointIdentity":IPLocalProfileID,@"isLocal":@YES,@"name":@"Local"}mutableCopy];
    }
    self.builtInLocalProfile[@"name"]=IPL(@"Local");return self.builtInLocalProfile;
}
- (void)localMediaChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(),^{self.lastLocalScan=0;[[NSNotificationCenter defaultCenter]postNotificationName:@"IPLocalLibraryChanged" object:self];});
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self];
#if TARGET_OS_IPHONE
    if(self.observingLocalMedia)[[MPMediaLibrary defaultMediaLibrary]endGeneratingLibraryChangeNotifications];
#endif
}
- (instancetype)initPrivate {
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSURL *base = urls.firstObject ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    return [self initWithSupportURL:[base URLByAppendingPathComponent:@"IPStore" isDirectory:YES] deferred:YES];
}

- (instancetype)initWithSupportURL:(NSURL *)supportURL {return [self initWithSupportURL:supportURL deferred:NO];}

- (instancetype)initWithSupportURL:(NSURL *)supportURL deferred:(BOOL)deferred {return [self initWithSupportURL:supportURL deferred:deferred migrate:YES];}
- (instancetype)initWithSupportURL:(NSURL *)supportURL deferred:(BOOL)deferred migrate:(BOOL)migrate {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.codex.iplayer935.store", DISPATCH_QUEUE_SERIAL);
        _metadataQueue = dispatch_queue_create("com.codex.iplayer935.store.metadata", DISPATCH_QUEUE_SERIAL);
        _persistenceQueue = dispatch_queue_create("com.codex.iplayer935.store.persistence", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, IPStoreQueueKey, IPStoreQueueKey, NULL);
        _supportURL = supportURL;
        if(deferred){
            NSData *data=[NSData dataWithContentsOfURL:[supportURL URLByAppendingPathComponent:@"startup-profiles.json"]];
            id profiles=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
            _profiles=[self mutableDictionaries:profiles];_tracks=[NSMutableArray new];_playlists=[NSMutableArray new];
            return self;
        }
        _libraryLoaded=YES;
        _smartCache=[[IPSmartCache alloc]initWithDirectory:[_supportURL URLByAppendingPathComponent:@"SmartCache" isDirectory:YES]];
        _cacheURL = [_supportURL URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
        _artworkURL = [_supportURL URLByAppendingPathComponent:@"Artwork" isDirectory:YES];
        _favoritesURL = [_supportURL URLByAppendingPathComponent:@"favorites.json"];
        [[NSFileManager defaultManager] createDirectoryAtURL:_cacheURL withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtURL:_artworkURL withIntermediateDirectories:YES attributes:nil error:NULL];
        NSArray *oldCacheFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL includingPropertiesForKeys:nil options:0 error:NULL];
        for (NSURL *oldFile in oldCacheFiles) if ([[oldFile.pathExtension lowercaseString] isEqualToString:@"part"]) [[NSFileManager defaultManager] removeItemAtURL:oldFile error:NULL];
        _storedCacheLimit = 2ULL * 1024 * 1024 * 1024;
        _database=[[IPLibraryDB alloc]initWithURL:[_supportURL URLByAppendingPathComponent:@"library.sqlite"]];
        if(_database.ready){
            NSDictionary *state=[_database state];
            _profiles=[self mutableDictionaries:state[@"profiles"]];_playlists=[self mutableDictionaries:state[@"playlists"]];
            _tracks=(id)[[IPTrackCollection alloc]initWithDatabase:_database IDs:[_database trackIDs]];
            _favoriteOverrides=[NSMutableDictionary new];_decodedMetadata=[NSMutableDictionary new];
            _storedCacheLimit=[state[@"cacheLimitBytes"]unsignedLongLongValue]?:2ULL*1024*1024*1024;
            _exampleProfileSeeded=[state[@"exampleProfileSeeded"]boolValue];
            if ([self ensureExampleProfile]) {
                NSMutableDictionary *updated=[state mutableCopy];
                updated[@"profiles"]=_profiles;updated[@"exampleProfileSeeded"]=@YES;
                [_database updateState:updated];
            }
            [self recalculateCacheBytes];return self;
        }
        NSURL *dataURL = [_supportURL URLByAppendingPathComponent:@"library.json"];
        NSData *savedData = [NSData dataWithContentsOfURL:dataURL];
        NSDictionary *saved = savedData ? [NSJSONSerialization JSONObjectWithData:savedData options:NSJSONReadingMutableContainers error:NULL] : nil;
        _profiles = [self mutableDictionaries:saved[@"profiles"]];
        _tracks = [self mutableDictionaries:saved[@"tracks"]];
        _playlists = [self mutableDictionaries:saved[@"playlists"]];
        NSData *favoriteData = [NSData dataWithContentsOfURL:_favoritesURL];
        id favoriteObject = favoriteData ? [NSJSONSerialization JSONObjectWithData:favoriteData options:0 error:NULL] : nil;
        _favoriteOverrides = [favoriteObject isKindOfClass:[NSDictionary class]] ? [favoriteObject mutableCopy] : [NSMutableDictionary dictionary];
        NSData *tagData = [NSData dataWithContentsOfURL:[_supportURL URLByAppendingPathComponent:@"decoded-metadata.json"]];
        id tagObject = tagData ? [NSJSONSerialization JSONObjectWithData:tagData options:0 error:NULL] : nil;
        _decodedMetadata = [tagObject isKindOfClass:[NSDictionary class]] ? [tagObject mutableCopy] : [NSMutableDictionary dictionary];
        /* Keep legacy favorites and apply the small override map on top of the library snapshot. */
        for (NSMutableDictionary *track in _tracks) {
            NSString *trackID = [track[@"id"] isKindOfClass:[NSString class]] ? track[@"id"] : nil;
            NSString *ext = [track[@"extension"] lowercaseString];
            if (trackID.length && [self.decodedMetadata[trackID] isKindOfClass:[NSDictionary class]]) [track addEntriesFromDictionary:self.decodedMetadata[trackID]];
            if ([trackID length] && !self.favoriteOverrides[trackID] && [track[@"favorite"] boolValue]) self.favoriteOverrides[trackID] = @YES;
            if ([trackID length] && self.favoriteOverrides[trackID]) track[@"favorite"] = self.favoriteOverrides[trackID];
            if ([trackID length] && ([ext isEqualToString:@"flac"] || [ext isEqualToString:@"ogg"] || [ext isEqualToString:@"opus"])) {
                [track removeObjectForKey:@"unsupportedReason"];
                if (![track[@"metadataLoaded"] boolValue]) track[@"metadataPending"] = @YES;
            }
        }
        if ([saved[@"cacheLimitBytes"] respondsToSelector:@selector(unsignedLongLongValue)]) _storedCacheLimit = [saved[@"cacheLimitBytes"] unsignedLongLongValue];
        _exampleProfileSeeded=[saved[@"exampleProfileSeeded"]boolValue];
        [self ensureExampleProfile];
        if (!saved) [self save];
        [self recalculateCacheBytes];
        if(!migrate){_database=nil;return self;}
        NSArray *ids=[_tracks valueForKey:@"id"];
        NSDictionary *state=@{@"profiles":_profiles,@"playlists":_playlists,@"cacheLimitBytes":@(_storedCacheLimit),@"exampleProfileSeeded":@(_exampleProfileSeeded)};
        if([_database commitState:state tracks:_tracks IDs:ids]&&[_database buildImportIndexes]&&[_database finishImport]){
            _tracks=(id)[[IPTrackCollection alloc]initWithDatabase:_database IDs:ids];
            _decodedMetadata=[NSMutableDictionary new];_favoriteOverrides=[NSMutableDictionary new];
        }else _database=nil; // Retain the legacy model if migration could not commit.
    }
    return self;
}

// Called only on the fully loaded store, never on the startup mirror.
- (BOOL)ensureExampleProfile {
    if (self.exampleProfileSeeded) return NO;
    self.exampleProfileSeeded=YES;
    for (NSDictionary *profile in self.profiles) if ([profile[@"id"]isEqual:@"example-music-server-v1"]) return YES;
    [self.profiles addObject:[@{@"id":@"example-music-server-v1",@"endpointIdentity":[NSUUID UUID].UUIDString,
        @"name":@"Example Music Server",@"host":@"music.example.invalid",@"share":@"Music",
        @"root":@"Sample Library",@"username":@"music-user",@"isExample":@YES}mutableCopy]];
    return YES;
}

// The loader owns its mutable models until this single main-thread handoff.
- (void)loadLibrary {
    NSAssert([NSThread isMainThread],@"Load library from the UI thread");
    if(self.libraryLoaded||self.libraryLoading)return;
    self.libraryLoading=YES;
    [self publishPreparation:IPL(@"Abriendo biblioteca guardada") completed:0 running:YES error:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
        @autoreleasepool {
            IPStore *loaded=[[IPStore alloc]initWithSupportURL:self.supportURL deferred:NO migrate:NO];
            // Capture before handing mutable dictionaries to UIKit. No foreground copying is needed.
            NSDictionary *initial=loaded.database?nil:@{@"profiles":IPStoreFreeze(loaded.profiles),@"trackIDs":[loaded.tracks valueForKey:@"id"],@"playlists":IPStoreFreeze(loaded.playlists),@"cacheLimitBytes":@(loaded.cacheLimitBytes),@"exampleProfileSeeded":@(loaded.exampleProfileSeeded)};
            dispatch_async(dispatch_get_main_queue(),^{
                // A server screen may already hold a bootstrap profile; keep its identity.
                for(NSUInteger i=0;i<loaded.profiles.count;i++)for(NSMutableDictionary *profile in self.profiles)
                    if([profile[@"id"]isEqual:loaded.profiles[i][@"id"]]){[profile setDictionary:loaded.profiles[i]];loaded.profiles[i]=profile;break;}
                self.profiles=loaded.profiles;self.tracks=loaded.tracks;self.playlists=loaded.playlists;self.database=loaded.database;
                self.favoriteOverrides=loaded.favoriteOverrides;self.decodedMetadata=loaded.decodedMetadata;
                self.cacheURL=loaded.cacheURL;self.artworkURL=loaded.artworkURL;self.favoritesURL=loaded.favoritesURL;
                self.storedCacheLimit=loaded.storedCacheLimit;self.cacheBytes=loaded.cacheBytes;
                self->_smartCache=loaded.smartCache;self.preparationSnapshot=initial;
                self.exampleProfileSeeded=loaded.exampleProfileSeeded;
                self.libraryLoaded=YES;self.libraryLoading=NO;
                [self persistStartupProfiles];
                [[NSNotificationCenter defaultCenter]postNotificationName:@"IPLibraryLoaded" object:self];
                [[NSNotificationCenter defaultCenter]postNotificationName:@"IPStoreChanged" object:self];
                if(!initial)[self publishPreparation:IPL(@"Biblioteca optimizada") completed:self.tracks.count running:NO error:nil];
                if(initial){self.preparationWantsRunning=YES;[self publishPreparation:IPL(@"Biblioteca disponible; preparación pendiente") completed:0 running:YES error:nil];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.75*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.preparationWantsRunning)[self resumePreparation];});}
            });
        }
    });
}
- (void)publishPreparation:(NSString *)phase completed:(NSUInteger)completed running:(BOOL)running error:(NSString *)error {
    self.preparationStatus=@{@"phase":phase?:@"",@"completed":@(completed),@"total":@(self.preparationSnapshot?[self.preparationSnapshot[@"trackIDs"]count]:self.tracks.count),@"running":@(running),@"error":error?:@"",@"updatedAt":@([NSDate date].timeIntervalSince1970),@"build":[[NSBundle mainBundle]objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"host"};
    [[NSNotificationCenter defaultCenter]postNotificationName:@"IPLibraryPreparationChanged" object:self];
    // Available even before the full diagnostic report. Contains no paths or credentials.
    NSURL *url=[[[NSFileManager defaultManager]URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"preparation.json"];
    NSDictionary *status=self.preparationStatus;dispatch_async(self.persistenceQueue,^{NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:NULL];if(data)[data writeToURL:url atomically:YES];});
}
- (void)pausePreparation {self.preparationWantsRunning=NO;self.preparationCancelled=YES;if(self.preparationSnapshot)[self publishPreparation:IPL(@"Preparación en pausa") completed:[self.preparationStatus[@"completed"]unsignedIntegerValue] running:NO error:nil];}
- (void)resumePreparation {
    self.preparationWantsRunning=YES;
    if(self.database||!self.preparationSnapshot||self.preparationRunning)return;
    self.preparationCancelled=NO;self.preparationRunning=YES;self.preparationStarted=[NSDate date].timeIntervalSince1970;
    if(!self.preparationQueue){self.preparationQueue=dispatch_queue_create("org.neura.library-preparation",DISPATCH_QUEUE_SERIAL);dispatch_set_target_queue(self.preparationQueue,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0));}
    if(self.preparationLatest){NSDictionary *latest=self.preparationLatest;self.preparationSnapshot=@{@"profiles":latest[@"profiles"],@"trackIDs":[latest[@"tracks"]valueForKey:@"id"],@"playlists":latest[@"playlists"],@"cacheLimitBytes":latest[@"cacheLimitBytes"],@"exampleProfileSeeded":latest[@"exampleProfileSeeded"]?:@NO};self.preparationLatest=nil;[self.preparationUpdates removeAllObjects];}
    NSDictionary *snapshot=self.preparationSnapshot;
    [self publishPreparation:IPL(@"Preparando sin bloquear la biblioteca") completed:0 running:YES error:nil];
    dispatch_async(self.preparationQueue,^{@autoreleasepool{
        IPLibraryDB *db=[[IPLibraryDB alloc]initWithURL:[self.supportURL URLByAppendingPathComponent:@"library.sqlite"]];
        __weak IPStore *weak=self;
        __block NSTimeInterval lastProgress=0;__block BOOL timedOut=NO;
        db.importProgress=^BOOL(NSUInteger n,NSString *phase){
            IPStore *store=weak;if(!store||store.preparationCancelled)return NO;
            if([NSDate date].timeIntervalSince1970-store.preparationStarted>180){timedOut=YES;return NO;}
            NSUInteger done=n==NSUIntegerMax?[snapshot[@"trackIDs"]count]:n;
            NSTimeInterval now=[NSDate date].timeIntervalSince1970;
            if(n==NSUIntegerMax||now-lastProgress>=.3){lastProgress=now;dispatch_async(dispatch_get_main_queue(),^{if(!store.preparationCancelled)[store publishPreparation:phase completed:done running:YES error:nil];});}
            if(n!=NSUIntegerMax)[NSThread sleepForTimeInterval:.003];
            return YES;
        };
        BOOL (^progress)(NSUInteger,NSString *)=db.importProgress;db.importProgress=nil;
        BOOL ok=[db beginImport];NSArray *ids=snapshot[@"trackIDs"];
        for(NSUInteger offset=0;ok&&offset<ids.count;offset+=256){@autoreleasepool{
            if(!progress(offset,IPL(@"Convirtiendo canciones"))){ok=NO;break;}
            NSArray *part=[ids subarrayWithRange:NSMakeRange(offset,MIN((NSUInteger)256,ids.count-offset))];
            __block NSArray *records=nil;
            dispatch_sync(dispatch_get_main_queue(),^{
                NSMutableArray *copies=[NSMutableArray new];
                if(!self.preparationCancelled)for(NSDictionary *track in [self materializeTrackIDs:part])[copies addObject:[track copy]];
                records=copies;
            });
            if(self.preparationCancelled){ok=NO;break;}
            ok=[db updateTracks:records];
        }}
        db.importProgress=progress;
        if(ok)ok=[db commitState:@{@"profiles":snapshot[@"profiles"],@"playlists":snapshot[@"playlists"],@"cacheLimitBytes":snapshot[@"cacheLimitBytes"],@"exampleProfileSeeded":snapshot[@"exampleProfileSeeded"]?:@NO} tracks:@[] IDs:ids]&&[db buildImportIndexes];
        db.importProgress=nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(ok&&!self.preparationCancelled){self.preparingDatabase=db;[self reconcilePreparation];}
            else {self.preparationRunning=NO;[self publishPreparation:self.preparationCancelled?IPL(@"Preparación en pausa"):IPL(@"Puedes seguir usando la biblioteca") completed:[self.preparationStatus[@"completed"]unsignedIntegerValue] running:NO error:self.preparationCancelled?nil:timedOut?IPL(@"La preparación superó el tiempo disponible. Puedes seguir usando la biblioteca y reintentar."):db.error.localizedDescription?:IPL(@"No se pudo preparar la biblioteca. Puedes reintentar.")];if(self.preparationWantsRunning&&self.preparationCancelled)[self resumePreparation];}
        });
    }});
}
- (void)reconcilePreparation {
    NSDictionary *snapshot=self.preparationLatest;
    NSArray *updates=self.preparationUpdates.allValues?:@[];
    NSUInteger revision=self.preparationRevision;IPLibraryDB *db=self.preparingDatabase;
    [self publishPreparation:IPL(@"Guardando cambios recientes") completed:[self.preparationSnapshot[@"trackIDs"]count] running:YES error:nil];
    dispatch_async(self.preparationQueue,^{
        BOOL ok=YES;
        if(snapshot)ok=[db commitState:@{@"profiles":snapshot[@"profiles"],@"playlists":snapshot[@"playlists"],@"cacheLimitBytes":snapshot[@"cacheLimitBytes"],@"exampleProfileSeeded":snapshot[@"exampleProfileSeeded"]?:@NO} tracks:snapshot[@"tracks"] IDs:[snapshot[@"tracks"]valueForKey:@"id"]];
        if(ok&&updates.count)ok=[db updateTracks:updates];
        dispatch_async(self.persistenceQueue,^{dispatch_async(dispatch_get_main_queue(),^{
            if(!ok||self.preparationCancelled){self.preparationRunning=NO;[self publishPreparation:IPL(@"Preparación en pausa") completed:0 running:NO error:db.error.localizedDescription];if(self.preparationWantsRunning&&self.preparationCancelled)[self resumePreparation];return;}
            if(revision!=self.preparationRevision){[self reconcilePreparation];return;}
            if(![db finishImport]){self.preparationRunning=NO;[self publishPreparation:IPL(@"No se pudo finalizar") completed:0 running:NO error:db.error.localizedDescription];return;}
            NSArray *ids=[db trackIDs];
            self.database=db;self.tracks=(id)[[IPTrackCollection alloc]initWithDatabase:db IDs:ids];self.trackLookup=nil;self.legacyIndex=nil;
            self.preparationRunning=NO;self.preparingDatabase=nil;
            [self publishPreparation:IPL(@"Biblioteca optimizada") completed:ids.count running:NO error:nil];
            self.preparationSnapshot=nil;self.preparationLatest=nil;self.preparationUpdates=nil;
            [[NSNotificationCenter defaultCenter]postNotificationName:@"IPStoreChanged" object:self];
        });});
    });
}
- (void)persistStartupProfiles {
    NSArray *profiles=IPStoreFreeze(self.profiles);
    NSURL *url=[self.supportURL URLByAppendingPathComponent:@"startup-profiles.json"];
    dispatch_async(self.persistenceQueue,^{NSData *data=[NSJSONSerialization dataWithJSONObject:profiles options:0 error:NULL];if(data)[data writeToURL:url options:NSDataWritingAtomic error:NULL];});
}

- (NSMutableArray *)mutableDictionaries:(id)objects {
    NSMutableArray *result = [NSMutableArray array];
    if ([objects isKindOfClass:[NSArray class]]) for (id object in objects) if ([object isKindOfClass:[NSDictionary class]]) [result addObject:[object mutableCopy]];
    return result;
}

- (NSURL *)dataURL { return [self.supportURL URLByAppendingPathComponent:@"library.json"]; }
- (void)save {
    if(!self.libraryLoaded)return; // Never overwrite disk with the bootstrap model.
    self.trackLookup=nil;
    __block NSDictionary *snapshot = nil;
    __block unsigned long long limitSnapshot = 0;
    __block NSArray *ids=nil;
    dispatch_block_t capture = ^{
        [self persistStartupProfiles];
        NSMutableArray *profiles = [NSMutableArray array], *tracks = [NSMutableArray array], *playlists = [NSMutableArray array];
        for (NSDictionary *value in self.profiles) [profiles addObject:IPStoreFreeze(value)];
        NSArray *models=[self.tracks isKindOfClass:[IPTrackCollection class]]?[(IPTrackCollection *)self.tracks changedTracks]:self.tracks;
        for (NSDictionary *value in models) [tracks addObject:IPStoreFreeze(value)];
        for (NSDictionary *value in self.playlists) [playlists addObject:IPStoreFreeze(value)];
        ids=[self.tracks isKindOfClass:[IPTrackCollection class]]?[(IPTrackCollection *)self.tracks trackIDs]:[self.tracks valueForKey:@"id"];
        limitSnapshot = self.cacheLimitBytes;
        snapshot = @{@"profiles":profiles, @"tracks":tracks, @"playlists":playlists, @"cacheLimitBytes":@(limitSnapshot),@"exampleProfileSeeded":@(self.exampleProfileSeeded)};
        if(!self.database){self.legacyIndex=nil;if(self.preparationSnapshot){self.preparationLatest=snapshot;[self.preparationUpdates removeAllObjects];self.preparationRevision++;}}
    };
    if ([NSThread isMainThread]) capture(); else dispatch_sync(dispatch_get_main_queue(), capture);
    NSURL *url = [self dataURL];
    dispatch_async(self.persistenceQueue, ^{
        if(self.database.ready){BOOL ok=[self.database commitState:@{@"profiles":snapshot[@"profiles"],@"playlists":snapshot[@"playlists"],@"cacheLimitBytes":snapshot[@"cacheLimitBytes"],@"exampleProfileSeeded":snapshot[@"exampleProfileSeeded"]?:@NO} tracks:snapshot[@"tracks"] IDs:ids];if(ok)dispatch_async(dispatch_get_main_queue(),^{if([self.tracks isKindOfClass:[IPTrackCollection class]])[(IPTrackCollection *)self.tracks acknowledgeTracks:snapshot[@"tracks"]];});return;}
        NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        if (json) [json writeToURL:url options:NSDataWritingAtomic error:NULL];
    });
}
- (BOOL)setFavorite:(BOOL)favorite forTrack:(NSDictionary *)track {
    if(![track[@"id"]isKindOfClass:[NSString class]]||![track[@"id"]length])return NO;
    [self setFavorite:favorite forTracks:@[track]];return YES;
}
- (void)setFavorite:(BOOL)favorite forTracks:(NSArray *)tracks {
    void (^update)(void)=^{
        NSMutableArray *changed=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
        for(NSDictionary *track in tracks){NSString *tid=track[@"id"];if(![tid isKindOfClass:[NSString class]]||!tid.length||[seen containsObject:tid])continue;[seen addObject:tid];
            self.favoriteOverrides[tid]=@(favorite);
            if([track isKindOfClass:[NSMutableDictionary class]])((NSMutableDictionary *)track)[@"favorite"]=@(favorite);
            NSMutableDictionary *canonical=[self trackWithID:tid]?:[track mutableCopy];canonical[@"favorite"]=@(favorite);[changed addObject:canonical];
            if(!self.database&&self.preparationSnapshot){if(!self.preparationUpdates)self.preparationUpdates=[NSMutableDictionary new];self.preparationUpdates[tid]=IPStoreFreeze(canonical);self.preparationRevision++;}
        }
        if(!changed.count)return;
        [self.legacyIndex updateTracks:changed];
        if(self.database){NSArray *records=IPStoreFreeze(changed);dispatch_async(self.persistenceQueue,^{[self.database updateTracks:records];});}
        else {NSDictionary *snapshot=[self.favoriteOverrides copy];dispatch_async(self.persistenceQueue,^{NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];if(json)[json writeToURL:self.favoritesURL options:NSDataWritingAtomic error:NULL];});}
        [[NSNotificationCenter defaultCenter]postNotificationName:@"IPFavoriteChanged" object:self userInfo:@{@"tracks":changed}];
    };
    if([NSThread isMainThread])update();else dispatch_sync(dispatch_get_main_queue(),update);
}
- (void)queryProfile:(NSDictionary *)profile mode:(NSString *)mode playlistIDs:(NSArray *)playlistIDs sort:(NSString *)sort query:(NSString *)query offset:(NSUInteger)offset limit:(NSUInteger)limit completion:(void (^)(NSArray *,NSUInteger,NSUInteger,NSArray *))completion {
    if(!self.database){
        // While preparing SQLite (or if unavailable), reuse the usable legacy index.
        if(!self.legacyIndex){self.legacyIndex=[IPLibraryIndex new];[self.legacyIndex replaceTracks:self.tracks];}
        IPLibraryIndex *legacy=self.legacyIndex;
        [legacy rowsForProfile:profile mode:mode playlistIDs:playlistIDs sort:sort query:query completion:^(NSArray *rows,NSUInteger pending){
            NSUInteger begin=MIN(offset,rows.count),count=limit?MIN(limit,rows.count-begin):rows.count-begin;
            NSArray *page=[rows subarrayWithRange:NSMakeRange(begin,count)];completion([page valueForKey:@"id"],rows.count,pending,page);
        }];return;
    }
    NSDictionary *p=[profile copy];NSArray *ids=[playlistIDs copy];NSString *kind=[mode copy],*key=[sort copy],*q=[query copy];
    // A change notification can arrive before its queued write; order reads after that commit.
    dispatch_async(self.persistenceQueue,^{[self.database queryProfile:p mode:kind playlistIDs:ids sort:key query:q offset:offset limit:limit completion:completion];});
}
- (NSArray *)materializeTrackRecords:(NSArray *)records {return [self.tracks isKindOfClass:[IPTrackCollection class]]?[(IPTrackCollection *)self.tracks materializeRecords:records]:[self materializeTrackIDs:[records valueForKey:@"id"]];}
- (NSArray *)materializeTrackIDs:(NSArray *)ids {
    if([self.tracks isKindOfClass:[IPTrackCollection class]])return [(IPTrackCollection *)self.tracks materializeIDs:ids];
    NSMutableArray *rows=[NSMutableArray new];for(NSString *tid in ids)if([self trackWithID:tid])[rows addObject:[self trackWithID:tid]];return rows;
}
- (NSArray *)queueForTrackIDs:(NSArray *)ids {
    if([self.tracks isKindOfClass:[IPTrackCollection class]])return [(IPTrackCollection *)self.tracks queueForIDs:ids];
    return [self materializeTrackIDs:ids];
}
- (NSMutableDictionary *)trackWithID:(NSString *)tid {
    if([self.tracks isKindOfClass:[IPTrackCollection class]])return [(IPTrackCollection *)self.tracks trackForID:tid];
    return [self trackMap][tid];
}
- (NSMutableDictionary *)trackMap {
    if(!self.trackLookup){self.trackLookup=[NSMutableDictionary dictionaryWithCapacity:self.tracks.count];for(NSMutableDictionary *t in self.tracks)if(t[@"id"])self.trackLookup[t[@"id"]]=t;}
    return self.trackLookup;
}
- (void)persistMetadataNow {
    if(!self.metadataWritePending)return;self.metadataWritePending=NO;
    if(self.database){[self save];return;}
    NSDictionary *snapshot=[self.decodedMetadata copy];
    dispatch_async(self.persistenceQueue,^{NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];if(json)[json writeToURL:[self.supportURL URLByAppendingPathComponent:@"decoded-metadata.json"] options:NSDataWritingAtomic error:NULL];});
}
- (void)flushPersistence {
    if([NSThread isMainThread])[self persistMetadataNow];else dispatch_sync(dispatch_get_main_queue(),^{[self persistMetadataNow];});
    dispatch_sync(self.persistenceQueue,^{});
}
- (void)applyDecodedMetadata:(NSDictionary *)metadata toTrack:(NSDictionary *)track completion:(IPStoreCompletion)completion {
    if(![track[@"id"] length]){if(completion)completion(nil);return;}
    [self applyMetadataBatch:@[@{@"id":track[@"id"],@"tags":[metadata copy]}] completion:completion];
}
- (void)applyMetadataBatch:(NSArray *)batch completion:(IPStoreCompletion)completion {
    dispatch_async(self.persistenceQueue,^{@autoreleasepool{
        NSMutableArray *updates=[NSMutableArray new];
        for(NSDictionary *item in batch){
            NSString *trackID=item[@"id"];NSDictionary *source=item[@"tags"];NSMutableDictionary *tags=[NSMutableDictionary new];
            for(NSString *key in @[@"title",@"artist",@"album",@"genre"]){id value=source[key];if([value isKindOfClass:[NSString class]]&&[value length])tags[key]=value;}
            for(NSString *key in @[@"duration",@"trackNumber",@"metadataAutoVersion",@"artworkAutoVersion",@"metadataRetryAfter"]){id value=source[key];if([value isKindOfClass:[NSNumber class]]&&[value doubleValue]>=0)tags[key]=value;}
            if([source[@"metadataCacheState"]isKindOfClass:[NSString class]])tags[@"metadataCacheState"]=source[@"metadataCacheState"];
            NSString *existing=source[@"artwork"];if([existing isKindOfClass:[NSString class]]&&existing.length&&[existing.lastPathComponent isEqual:existing])tags[@"artwork"]=existing;
            NSData *art=[source[@"artworkData"] isKindOfClass:[NSData class]]?IPSmallArtwork(source[@"artworkData"]):nil;
            if(art.length){NSString *name=[NSString stringWithFormat:@"%@.artwork",IPStoreHash(trackID)];if([art writeToURL:[self.artworkURL URLByAppendingPathComponent:name] atomically:YES])tags[@"artwork"]=name;}
            tags[@"metadataLoaded"]=@(![source[@"metadataCacheState"]isEqual:@"error"]);tags[@"metadataPending"]=@([source[@"metadataCacheState"]isEqual:@"error"]);
            [updates addObject:@{@"id":trackID,@"tags":[tags copy]}];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            NSMutableArray *changed=[NSMutableArray new];
            for(NSDictionary *item in updates){NSMutableDictionary *stored=[self trackWithID:item[@"id"]];if(!stored)continue;[stored addEntriesFromDictionary:item[@"tags"]];NSMutableDictionary *merged=[self.decodedMetadata[item[@"id"]] mutableCopy]?:[NSMutableDictionary new];[merged addEntriesFromDictionary:item[@"tags"]];self.decodedMetadata[item[@"id"]]=[merged copy];[changed addObject:stored];}
            if(changed.count){
                [self.legacyIndex updateTracks:changed];
                if(!self.database&&self.preparationSnapshot){if(!self.preparationUpdates)self.preparationUpdates=[NSMutableDictionary new];for(NSDictionary *t in changed)self.preparationUpdates[t[@"id"]]=IPStoreFreeze(t);self.preparationRevision++;}
                if(self.database){NSArray *records=IPStoreFreeze(changed);dispatch_async(self.persistenceQueue,^{[self.database updateTracks:records];});}
                if(!self.metadataWritePending){self.metadataWritePending=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self persistMetadataNow];});}
                [[NSNotificationCenter defaultCenter]postNotificationName:@"IPTrackMetadataChanged" object:self userInfo:@{@"tracks":changed}];
            }
            if(completion)completion(nil);
        });
    }});
}

- (void)preparePlaybackCacheForQueue:(NSArray *)queue index:(NSInteger)index {
    [self.smartCache prefetchQueue:queue index:index profiles:self.profiles password:^NSString *(NSDictionary *profile){return [self passwordForProfile:profile error:NULL]?:@"";}];
}
- (unsigned long long)cacheLimitBytes { @synchronized (self) { return self.storedCacheLimit; } }
- (void)setCacheLimitBytes:(unsigned long long)value { @synchronized (self) { self.storedCacheLimit = value; } [self save]; }
- (unsigned long long)cacheBytes { @synchronized (self) { return _cacheBytes; } }
- (void)setCacheBytes:(unsigned long long)value { @synchronized (self) { _cacheBytes = value; } }
- (void)recalculateCacheBytes {
    unsigned long long total = 0;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.cacheURL includingPropertiesForKeys:@[NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *url in files) if ([[url.pathExtension lowercaseString] isEqualToString:@"media"]) total += [[url resourceValuesForKeys:@[NSURLFileSizeKey] error:NULL][NSURLFileSizeKey] unsignedLongLongValue];
    self.cacheBytes = total;
}

- (NSMutableDictionary *)profileForTrack:(NSDictionary *)track {
    NSString *profileID = track[@"profileID"];
    if([profileID isEqual:IPLocalProfileID])return self.localProfile;
    if (![profileID isKindOfClass:[NSString class]]) return nil;
    for (NSMutableDictionary *profile in self.profiles) {
        NSString *trackIdentity = [track[@"endpointIdentity"] length] ? track[@"endpointIdentity"] : profileID;
        NSString *profileIdentity = [self identityForProfile:profile];
        if ([profile[@"id"] isEqual:profileID] && [trackIdentity isEqual:profileIdentity]) return profile;
    }
    return nil;
}
- (NSURL *)localURL:(NSDictionary *)track { return [self localURLForTrack:track]; }
- (NSURL *)artworkURLForTrack:(NSDictionary *)track {
    NSString *name = [track[@"artwork"] isKindOfClass:[NSString class]] ? track[@"artwork"] : nil;
    if (!name.length) return nil;
    NSURL *url = [self.artworkURL URLByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:url.path] ? url : nil;
}
- (NSURL *)manualURLForTrack:(NSDictionary *)track {
    if(![track[@"id"]isKindOfClass:[NSString class]])return nil;NSURL *url=[self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.media",IPStoreHash(track[@"id"])]];return [[NSFileManager defaultManager]fileExistsAtPath:url.path]?url:nil;
}
- (NSURL *)localURLForTrack:(NSDictionary *)track {
    if([track[@"profileID"]isEqual:IPLocalProfileID]){
        if([track[@"unavailableRemote"]boolValue])return nil;
        NSURL *url=[NSURL URLWithString:track[@"localURL"]?:@""];
        if(url.isFileURL)return [[NSFileManager defaultManager]isReadableFileAtPath:url.path]?url:nil;
        return [url.scheme isEqual:@"ipod-library"]?url:nil;
    }
    return [self manualURLForTrack:track]?:[self.smartCache localURLForTrack:track];
}

- (OSStatus)keychainStatusForPassword:(NSString *)password profileID:(NSString *)profileID deleting:(BOOL)deleting output:(NSString **)output {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: IPStoreKeychainService,
                            (__bridge id)kSecAttrAccount: profileID};
    if([profileID isEqual:IPLocalProfileID])return errSecParam;
    if (deleting) return SecItemDelete((__bridge CFDictionaryRef)query);
    if (password) {
        NSDictionary *update = @{(__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding]};
        OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
        if (updateStatus == errSecSuccess) return updateStatus;
        if (updateStatus != errSecItemNotFound) return updateStatus;
        NSMutableDictionary *item = [query mutableCopy];
        item[(__bridge id)kSecValueData] = update[(__bridge id)kSecValueData];
        return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    NSDictionary *lookup = [query mutableCopy];
    NSMutableDictionary *lookupOptions = [lookup mutableCopy];
    lookupOptions[(__bridge id)kSecReturnData] = @YES;
    lookupOptions[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)lookupOptions, &result);
    if (status == errSecSuccess && output) {
        NSData *data = CFBridgingRelease(result);
        *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return status;
    }
    if (result) CFRelease(result);
    return status;
}

- (BOOL)setPassword:(NSString *)password forProfileID:(NSString *)profileID error:(NSError **)error {
    OSStatus status = [self keychainStatusForPassword:password profileID:profileID deleting:NO output:NULL];
    if (status != errSecSuccess) { if(error)*error=IPStoreError(status,IPL(@"Could not save SMB password to Keychain.")); return NO; } return YES;
}
- (NSString *)passwordForProfileID:(NSString *)profileID error:(NSError **)error {
    NSString *value = nil; OSStatus status = [self keychainStatusForPassword:nil profileID:profileID deleting:NO output:&value];
    if (status != errSecSuccess && status != errSecItemNotFound) { if(error)*error=IPStoreError(status,IPL(@"Could not read SMB password from Keychain.")); }
    return value;
}
- (NSString *)passwordForProfile:(NSDictionary *)profile error:(NSError **)error { return [self passwordForProfileID:profile[@"id"] error:error]; }
- (BOOL)deletePasswordForProfileID:(NSString *)profileID error:(NSError **)error {
    OSStatus status = [self keychainStatusForPassword:nil profileID:profileID deleting:YES output:NULL];
    if (status != errSecSuccess && status != errSecItemNotFound) { if(error)*error=IPStoreError(status,IPL(@"Could not delete SMB password from Keychain.")); return NO; } return YES;
}

- (BOOL)deleteProfile:(NSMutableDictionary *)profile error:(NSError **)error {
    if(IPIsLocalProfile(profile)){if(error)*error=IPStoreError(15,IPL(@"Local is a built-in library and cannot be edited or deleted."));return NO;}
    if (![NSThread isMainThread]) { __block BOOL result; __block NSError *mainError = nil; dispatch_sync(dispatch_get_main_queue(), ^{ result = [self deleteProfile:profile error:&mainError]; }); if (error) *error = mainError; return result; }
    if ([profile[@"isExample"]boolValue]) {
        [self.profiles removeObject:profile];
        BOOL ok=[self deletePasswordForProfileID:profile[@"id"] error:error];
        [self save];return ok;
    }
    [self cancelMetadata];
    NSString *pid = profile[@"id"];
    for (NSDictionary *track in [self.tracks copy]) if ([track[@"profileID"] isEqual:pid]) [self removeDownloadForTrack:track error:NULL];
    [self.tracks filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *track, NSDictionary *bindings) { return ![track[@"profileID"] isEqual:pid]; }]];
    for (NSMutableDictionary *playlist in self.playlists) {
        NSMutableArray *ids = [NSMutableArray array];
        for (NSString *tid in playlist[@"trackIDs"] ?: @[]) {
            BOOL found = NO; for (NSDictionary *track in self.tracks) if ([track[@"id"] isEqual:tid]) { found=YES; break; }
            if (found) [ids addObject:tid];
        }
        playlist[@"trackIDs"] = ids;
    }
    [self.profiles removeObject:profile];
    BOOL ok = [self deletePasswordForProfileID:pid error:error]; [self save]; return ok;
}

- (BOOL)setEndpoint:(NSDictionary *)endpoint forProfileID:(NSString *)profileID error:(NSError **)error {
    if([profileID isEqual:IPLocalProfileID]){if(error)*error=IPStoreError(15,IPL(@"Local is a built-in library and cannot be edited or deleted."));return NO;}
    if (![NSThread isMainThread]) { __block BOOL result; __block NSError *mainError = nil; dispatch_sync(dispatch_get_main_queue(), ^{ result = [self setEndpoint:endpoint forProfileID:profileID error:&mainError]; }); if (error) *error = mainError; return result; }
    [self cancelMetadata];
    NSMutableDictionary *profile = nil;
    for (NSMutableDictionary *candidate in self.profiles) if ([candidate[@"id"] isEqual:profileID]) { profile=candidate; break; }
    if (!profile) { if(error)*error=IPStoreError(1,IPL(@"Profile was not found.")); return NO; }
    BOOL endpointChanged = NO;
    for (NSString *key in @[@"host",@"share",@"root"]) if (endpoint[key] && ![profile[key] isEqual:endpoint[key]]) endpointChanged = YES;
    if (endpointChanged) {
        for (NSMutableDictionary *track in self.tracks) if ([track[@"profileID"] isEqual:profileID]) {
            if (!track[@"sourceName"]) track[@"sourceName"] = profile[@"name"] ?: profile[@"host"] ?: IPL(@"Server");
            if (!track[@"sourceHost"]) track[@"sourceHost"] = profile[@"host"] ?: @"";
            track[@"unavailableRemote"] = @YES;
        }
    }
    for (NSString *key in @[@"name",@"host",@"share",@"root",@"username"]) if (endpoint[key]) profile[key]=endpoint[key];
    if (endpointChanged) profile[@"endpointIdentity"] = [[NSUUID UUID] UUIDString];
    if ([profile[@"isExample"]boolValue] && ![profile[@"host"]isEqual:@"music.example.invalid"]) [profile removeObjectForKey:@"isExample"];
    [self save]; return YES;
}

- (BOOL)removeDownloadForTrack:(NSDictionary *)track error:(NSError **)error {
    if (![NSThread isMainThread]) { __block BOOL result; __block NSError *mainError = nil; dispatch_sync(dispatch_get_main_queue(), ^{ result = [self removeDownloadForTrack:track error:&mainError]; }); if (error) *error = mainError; return result; }
    NSString *trackID = [track[@"id"] isKindOfClass:[NSString class]] ? track[@"id"] : @"";
    NSURL *url = [self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.media", IPStoreHash(trackID)]];
    BOOL result = ![[NSFileManager defaultManager] fileExistsAtPath:url.path] || [[NSFileManager defaultManager] removeItemAtURL:url error:error];
    if (result) {
        for (NSMutableDictionary *stored in self.tracks) if ([stored[@"id"] isEqual:trackID]) [stored removeObjectForKey:@"downloaded"];
        [self recalculateCacheBytes];
        [self save];
    }
    return result;
}
- (BOOL)clearCache:(NSError **)error {
    if (![NSThread isMainThread]) { __block BOOL result; __block NSError *mainError = nil; dispatch_sync(dispatch_get_main_queue(), ^{ result = [self clearCache:&mainError]; }); if (error) *error = mainError; return result; }
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.cacheURL includingPropertiesForKeys:nil options:0 error:error];
    if (!files) return NO;
    for (NSURL *url in files) if (![[NSFileManager defaultManager] removeItemAtURL:url error:error]) return NO;
    for (NSMutableDictionary *track in self.tracks) [track removeObjectForKey:@"downloaded"];
    self.cacheBytes = 0; [self save]; return YES;
}

- (NSString *)normalizedRoot:(NSString *)root {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [root componentsSeparatedByString:@"/"]) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."] || [part containsString:@"\\"] || [part containsString:@":"]) return nil;
        [parts addObject:part];
    }
    return [parts componentsJoinedByString:@"/"];
}
- (NSString *)identityForProfile:(NSDictionary *)profile { return profile[@"endpointIdentity"] ?: profile[@"id"] ?: @""; }
- (NSString *)relativePathForListedPath:(NSString *)path root:(NSString *)root {
    NSString *prefix = root.length ? [root stringByAppendingString:@"/"] : @"";
    if ([path isEqualToString:root]) return @"";
    if (![path hasPrefix:prefix]) return nil;
    NSString *relative = [path substringFromIndex:prefix.length];
    if (!relative.length || [relative containsString:@"\\"] || [relative containsString:@":"]) return nil;
    for (NSString *part in [relative componentsSeparatedByString:@"/"]) if ([part isEqualToString:@".."] || !part.length) return nil;
    return relative;
}
- (NSString *)trackIDForProfile:(NSDictionary *)profile relativePath:(NSString *)path {
    NSString *identity = [self identityForProfile:profile];
    return IPStoreHash([NSString stringWithFormat:@"%@\n%@\n%@\n%@", profile[@"id"] ?: @"", identity, [self normalizedRoot:profile[@"root"] ?: @""] ?: @"", path]);
}

- (void)sendProgress:(IPStoreProgress)progress message:(NSString *)message { if(progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(message); }); }
- (void)finish:(IPStoreCompletion)completion error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IPStoreChanged" object:self];
        if (completion) completion(error);
    });
}

- (void)scanProfile:(NSMutableDictionary *)profile progress:(IPStoreProgress)progress completion:(IPStoreCompletion)completion {
    if(IPIsLocalProfile(profile)){[self scanLocalLibraryWithProgress:progress completion:completion];return;}
    if ([profile[@"isExample"]boolValue]) { [self finish:completion error:IPStoreError(14,IPL(@"This is a fictional example. Edit the profile with your own server details before connecting."))]; return; }
    [self cancelMetadata];
    NSDictionary *target = [profile copy];
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSString *root = [self normalizedRoot:target[@"root"] ?: @""];
        if (!root) { [self finish:completion error:IPStoreError(2,IPL(@"Profile root contains an unsafe path."))]; return; }
        NSString *password = [self passwordForProfile:target error:&error]; if (!password) password=@"";
        IPSMB *client = [[IPSMB alloc] initWithProfile:target password:password];
        if (![client connect:&error]) { [self finish:completion error:error]; return; }
        NSMutableArray *audio = [NSMutableArray array], *m3us = [NSMutableArray array];
        NSMutableArray *pending = [NSMutableArray arrayWithObject:@""];
        NSMutableSet *visited = [NSMutableSet set];
        /* FFmpeg-backed playback supports these in addition to AVFoundation formats. */
        NSSet *audioExt = [NSSet setWithArray:@[@"mp3",@"m4a",@"aac",@"wav",@"aiff",@"caf",@"m4b",@"mp4",@"flac",@"ogg",@"opus"]];
        NSSet *audioCandidateExt = [NSSet setWithArray:@[@"mp3",@"m4a",@"aac",@"wav",@"aiff",@"caf",@"m4b",@"mp4",@"flac",@"ogg",@"opus",@"wma",@"alac"]];
        while (pending.count && !error) {
            NSString *directory = pending.lastObject; [pending removeLastObject];
            if ([visited containsObject:directory]) continue; [visited addObject:directory];
            [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Scanning %@"), directory.length ? directory : IPL(@"music folder")]];
            @autoreleasepool {
                NSArray *entries = [client list:directory error:&error]; if (!entries) continue;
                for (NSDictionary *entry in entries) {
                    NSString *relative = [self relativePathForListedPath:entry[@"path"] root:root];
                    if (!relative) continue;
                    if ([entry[@"directory"] boolValue]) { [pending addObject:relative]; continue; }
                    if ([relative.lastPathComponent hasPrefix:@"."] || [relative.lastPathComponent isEqualToString:@"Thumbs.db"]) continue;
                    NSString *ext = [[relative pathExtension] lowercaseString];
                    if ([ext isEqualToString:@"m3u"] || [ext isEqualToString:@"m3u8"]) [m3us addObject:@{@"path":relative,@"size":entry[@"size"] ?: @0}];
                    if ([ext isEqualToString:@"m3u"] || [ext isEqualToString:@"m3u8"]) continue;
                    if (![audioCandidateExt containsObject:ext]) continue;
                    NSString *title = [[relative.lastPathComponent stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
                    NSMutableDictionary *track = [@{@"id":[self trackIDForProfile:target relativePath:relative], @"profileID":target[@"id"] ?: @"",
                                                    @"endpointIdentity":[self identityForProfile:target], @"path":relative,
                                                    @"sourceName":target[@"name"] ?: target[@"host"] ?: IPL(@"Server"), @"sourceHost":target[@"host"] ?: @"",
                                                    @"title":title ?: @"", @"artist":@"", @"album":@"", @"genre":@"",
                                                    @"duration":@0, @"trackNumber":@0, @"artwork":@"", @"favorite":@NO,
                                                    @"extension":ext, @"size":entry[@"size"] ?: @0, @"modifiedAt":entry[@"modifiedAt"]?:@0, @"addedAt":@([NSDate date].timeIntervalSince1970), @"metadataPending":@YES} mutableCopy];
                    if (![audioExt containsObject:ext]) { track[@"unsupportedReason"] = @"This file type is not supported by the player."; track[@"metadataPending"] = @NO; }
                    [audio addObject:track];
                }
            }
        }
        [client disconnect];
        if (error) { [self finish:completion error:error]; return; }
        /* Playlist references are track IDs. Existing imported playlists stay ordered and resolve by identity. */
        dispatch_semaphore_t playlistDone = dispatch_semaphore_create(0);
        __block NSArray *importedPlaylists = nil;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            importedPlaylists = [self importPlaylists:m3us profile:target root:root tracks:audio progress:progress];
            dispatch_semaphore_signal(playlistDone);
        });
        dispatch_semaphore_wait(playlistDone, DISPATCH_TIME_FOREVER);
        NSUInteger skippedPlaylistEntries = 0, unsupportedTracks = 0;
        for (NSDictionary *playlist in importedPlaylists) skippedPlaylistEntries += [playlist[@"skippedEntries"] unsignedIntegerValue];
        for (NSDictionary *track in audio) if (track[@"unsupportedReason"]) unsupportedTracks++;
        NSMutableArray *warningParts = [NSMutableArray array];
        if (unsupportedTracks) [warningParts addObject:[NSString stringWithFormat:IPL(@"%lu unsupported audio files"), (unsigned long)unsupportedTracks]];
        if (skippedPlaylistEntries) [warningParts addObject:[NSString stringWithFormat:IPL(@"%lu unmatched playlist references"), (unsigned long)skippedPlaylistEntries]];
        NSString *scanWarning = warningParts.count ? [warningParts componentsJoinedByString:@"; "] : nil;
        if (scanWarning) [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Library scan complete: %@."), scanWarning]];
        // Deserialize prior records off main; the handoff below only merges changed values.
        NSMutableDictionary *priorRecords=[NSMutableDictionary new];
        if(self.database)for(NSDictionary *old in [self.database recordsForProfileID:target[@"id"]])priorRecords[old[@"id"]]=old;
        dispatch_semaphore_t scanCommitDone = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL profileStillCurrent = NO;
            for (NSDictionary *candidate in self.profiles) if ([candidate[@"id"] isEqual:target[@"id"]] && [[self identityForProfile:candidate] isEqual:[self identityForProfile:target]]) { profileStillCurrent = YES; break; }
            if (!profileStillCurrent) {
                [self finish:completion error:IPStoreError(9,IPL(@"The profile changed while its library was scanning."))];
                dispatch_semaphore_signal(scanCommitDone);
                return;
            }
            NSMutableDictionary *oldByID = [priorRecords mutableCopy];
            NSArray *current=[self.tracks isKindOfClass:[IPTrackCollection class]]?[(IPTrackCollection *)self.tracks materializedTracks]:self.tracks;
            for (NSDictionary *old in current) if ([old[@"profileID"] isEqual:target[@"id"]]) oldByID[old[@"id"]]=old;
            NSMutableSet *foundIDs = [NSMutableSet set];
            for (NSMutableDictionary *track in audio) {
                NSDictionary *old = oldByID[track[@"id"]];
                [foundIDs addObject:track[@"id"]];
                BOOL sameSize = old && [old[@"size"] unsignedLongLongValue] == [track[@"size"] unsignedLongLongValue] && (![old[@"modifiedAt"] doubleValue] || ![track[@"modifiedAt"] doubleValue] || [old[@"modifiedAt"] isEqual:track[@"modifiedAt"]]);
                if(old[@"addedAt"])track[@"addedAt"]=old[@"addedAt"];
                if(!sameSize)[self.decodedMetadata removeObjectForKey:track[@"id"]];
                if (old && !sameSize) {
                    NSURL *cached = [self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.media", IPStoreHash(track[@"id"])]];
                    [[NSFileManager defaultManager] removeItemAtURL:cached error:NULL];
                    NSURL *oldArtwork = [self.artworkURL URLByAppendingPathComponent:old[@"artwork"] ?: @""];
                    if ([old[@"artwork"] length]) [[NSFileManager defaultManager] removeItemAtURL:oldArtwork error:NULL];
                }
                NSNumber *favoriteOverride = self.favoriteOverrides[track[@"id"]];
                if (favoriteOverride) track[@"favorite"] = favoriteOverride;
                else if (old[@"favorite"]) track[@"favorite"] = old[@"favorite"];
                if ([audioExt containsObject:[track[@"extension"] lowercaseString]]) [track removeObjectForKey:@"unsupportedReason"];
                if (sameSize) {
                    for (NSString *key in @[@"artist",@"album",@"genre",@"duration",@"trackNumber",@"artwork"]) {
                        id prior = old[key];
                        if ([prior isKindOfClass:[NSString class]] ? [prior length] > 0 : [prior respondsToSelector:@selector(doubleValue)] ? [prior doubleValue] > 0 : NO) track[key] = prior;
                    }
                    if ([old[@"metadataLoaded"] boolValue] && old[@"title"]) track[@"title"] = old[@"title"];
                    for(NSString *key in @[@"metadataAutoVersion",@"artworkAutoVersion",@"metadataCacheState",@"metadataRetryAfter"])if(old[key])track[key]=old[key];
                    if ([old[@"metadataLoaded"] boolValue]) { track[@"metadataLoaded"] = @YES; track[@"metadataPending"] = @NO; }
                    else if (old[@"metadataPending"] && ![old[@"metadataPending"] boolValue]) track[@"metadataPending"] = @NO;
                }
                [track removeObjectForKey:@"unavailableRemote"];
                if (sameSize && [old[@"downloaded"] boolValue]) track[@"downloaded"] = @YES;
            }
            NSMutableArray *retained = [NSMutableArray array];
            NSMutableDictionary *retainedByID = [NSMutableDictionary dictionary];
            for (NSDictionary *old in oldByID.allValues) {
                if ([foundIDs containsObject:old[@"id"]]) continue;
                NSMutableDictionary *offline = [old mutableCopy];
                offline[@"unavailableRemote"] = @YES;
                if ([self manualURLForTrack:offline]) offline[@"downloaded"] = @YES;
                [retained addObject:offline];
                retainedByID[offline[@"id"]] = offline;
            }
            if([self.tracks isKindOfClass:[IPTrackCollection class]])[(IPTrackCollection *)self.tracks replaceProfileRecords:[audio arrayByAddingObjectsFromArray:retained] previous:oldByID];
            else {NSIndexSet *indices = [self.tracks indexesOfObjectsPassingTest:^BOOL(NSDictionary *track, NSUInteger idx, BOOL *stop) { return [track[@"profileID"] isEqual:target[@"id"]]; }];
            [self.tracks removeObjectsAtIndexes:indices]; [self.tracks addObjectsFromArray:audio]; [self.tracks addObjectsFromArray:retained];}
            self.lastScanWarning = scanWarning;
            for (NSMutableDictionary *newPlaylist in importedPlaylists) {
                NSMutableDictionary *existing = nil;
                for (NSMutableDictionary *candidate in self.playlists) if ([candidate[@"id"] isEqual:newPlaylist[@"id"]]) { existing = candidate; break; }
        if (existing) {
                    NSMutableArray *ordered = [newPlaylist[@"trackIDs"] mutableCopy];
                    NSMutableSet *orderedSet = [NSMutableSet setWithArray:ordered];
                    for (NSString *oldID in existing[@"trackIDs"] ?: @[]) {
                        NSDictionary *offline = retainedByID[oldID];
                        if (offline && ![orderedSet containsObject:oldID]) { [ordered addObject:oldID]; [orderedSet addObject:oldID]; }
                    }
                    newPlaylist[@"trackIDs"] = ordered;
            [existing addEntriesFromDictionary:newPlaylist];
                } else [self.playlists addObject:newPlaylist];
            }
            self.automaticRetryAfter=0;
            self.metadataWritePending=YES;[self persistMetadataNow];
            [self save]; [self finish:completion error:nil];
            dispatch_semaphore_signal(scanCommitDone);
        });
        dispatch_semaphore_wait(scanCommitDone, DISPATCH_TIME_FOREVER);
    });
}


- (NSArray *)localFileRoots {return [IPLocalLibrary fileRoots];}
- (void)scanLocalLibraryWithProgress:(IPStoreProgress)progress completion:(IPStoreCompletion)completion {
    if(!self.libraryLoaded){[self finish:completion error:IPStoreError(17,IPL(@"Cargando biblioteca guardada…"))];return;}
    if(self.localScanRunning){if(completion)completion(nil);return;}
#if TARGET_OS_IPHONE
    if(!self.observingLocalMedia){
        self.observingLocalMedia=YES;
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(localMediaChanged:) name:MPMediaLibraryDidChangeNotification object:nil];
        [[MPMediaLibrary defaultMediaLibrary]beginGeneratingLibraryChangeNotifications];
    }
#endif
    self.localScanRunning=YES;[self sendProgress:progress message:IPL(@"Reading local music…")];
    [self stopAutomaticMetadata];
    // The filesystem and system media database are never traversed on the UI thread.
    dispatch_async(self.queue,^{@autoreleasepool{
        NSDictionary *result=[IPLocalLibrary scanRoots:[self localFileRoots] includeMediaLibrary:YES];
        NSMutableDictionary *previous=[NSMutableDictionary new];
        if(self.database)for(NSDictionary *t in [self.database recordsForProfileID:IPLocalProfileID])previous[t[@"id"]]=t;
        dispatch_async(dispatch_get_main_queue(),^{
            NSArray *models=[self.tracks isKindOfClass:[IPTrackCollection class]]?[(IPTrackCollection *)self.tracks materializedTracks]:self.tracks;
            for(NSDictionary *t in models)if([t[@"profileID"]isEqual:IPLocalProfileID])previous[t[@"id"]]=t;
            NSMutableArray *records=[NSMutableArray new];NSMutableSet *found=[NSMutableSet new];BOOL changed=NO;
            for(NSDictionary *fresh in result[@"tracks"]){
                NSDictionary *old=previous[fresh[@"id"]];NSMutableDictionary *t=[fresh mutableCopy];[found addObject:t[@"id"]];
                BOOL same=old&&[old[@"size"]isEqual:t[@"size"]]&&[old[@"modifiedAt"]isEqual:t[@"modifiedAt"]]&&[(old[@"localRevision"]?:@"")isEqual:t[@"localRevision"]?:@""];
                if(!same)[self.decodedMetadata removeObjectForKey:t[@"id"]];
                if(same){
                    for(NSString *key in @[@"title",@"artist",@"album",@"genre",@"duration",@"trackNumber",@"artwork",@"metadataLoaded",@"metadataPending",@"metadataAutoVersion",@"artworkAutoVersion",@"metadataCacheState",@"metadataRetryAfter"])if(old[key])t[key]=old[key];
                }
                if(old[@"addedAt"])t[@"addedAt"]=old[@"addedAt"];
                t[@"favorite"]=self.favoriteOverrides[t[@"id"]]?:old[@"favorite"]?:@NO;
                if(![old isEqual:t])changed=YES;
                [records addObject:t];
            }
            for(NSDictionary *old in previous.allValues)if(![found containsObject:old[@"id"]]){
                NSMutableDictionary *t=[old mutableCopy];BOOL inaccessible=NO;
                for(NSString *path in result[@"failedRoots"])if([old[@"path"]isEqual:path]||[old[@"path"]hasPrefix:[path stringByAppendingString:@"/"]]){inaccessible=YES;break;}
                if(!inaccessible)t[@"unavailableRemote"]=@YES;
                if(![old isEqual:t])changed=YES;[records addObject:t];
            }
            if(changed){
                if([self.tracks isKindOfClass:[IPTrackCollection class]])[(IPTrackCollection *)self.tracks replaceProfileRecords:records previous:previous];
                else {NSIndexSet *indices=[self.tracks indexesOfObjectsPassingTest:^BOOL(NSDictionary *t,NSUInteger i,BOOL *stop){return [t[@"profileID"]isEqual:IPLocalProfileID];}];[self.tracks removeObjectsAtIndexes:indices];[self.tracks addObjectsFromArray:records];}
                self.trackLookup=nil;self.legacyIndex=nil;[self save];
            }
            self.lastScanWarning=[result[@"failedRoots"]count]?IPL(@"Some folders could not be read. Existing entries were kept."):nil;
            self.localScanRunning=NO;self.lastLocalScan=[NSDate date].timeIntervalSince1970;
            [self finish:completion error:nil];

        });
    }});
}

- (NSUInteger)metadataPendingCountForProfile:(NSDictionary *)profile {
    if(self.database)return [[self.database metadataStatus:profile][@"pending"]unsignedIntegerValue];
    __block NSUInteger count = 0;
    NSString *identity = [self identityForProfile:profile];
    dispatch_block_t work = ^{ for (NSDictionary *track in self.tracks) if ([track[@"profileID"] isEqual:profile[@"id"]] && [[track objectForKey:@"endpointIdentity"] isEqual:identity] && ![track[@"unavailableRemote"] boolValue] && [track[@"metadataPending"] boolValue] && !track[@"unsupportedReason"]) count++; };
    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    return count;
}

- (void)refreshProfileIfNeeded:(NSMutableDictionary *)profile {
    if(!self.libraryLoaded || [profile[@"isExample"]boolValue])return;
    if(!profile[@"id"])return;
    if(!self.refreshingProfiles)self.refreshingProfiles=[NSMutableSet new];
    if(IPIsLocalProfile(profile)){if(!self.localScanRunning&&[NSDate date].timeIntervalSince1970-self.lastLocalScan>=60)[self scanProfile:profile progress:nil completion:nil];return;}
    NSString *key=[@"library-refresh-" stringByAppendingString:[self identityForProfile:profile]];
    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    if([self.refreshingProfiles containsObject:profile[@"id"]] || now-[[NSUserDefaults standardUserDefaults]doubleForKey:key]<900)return;
    [[NSUserDefaults standardUserDefaults]setDouble:now forKey:key];[self.refreshingProfiles addObject:profile[@"id"]];
    [self scanProfile:profile progress:nil completion:^(NSError *error){[self.refreshingProfiles removeObject:profile[@"id"]];}];
}
- (void)stopAutomaticMetadata {
    @synchronized(self){self.automaticGeneration++;self.automaticRunning=NO;self.priorityIDs=nil;}
}
- (NSString *)metadataPauseKey:(NSDictionary *)profile {return [@"metadata-paused-" stringByAppendingString:[self identityForProfile:profile]];}
- (void)setMetadataPaused:(BOOL)paused forProfile:(NSDictionary *)profile {
    [[NSUserDefaults standardUserDefaults]setBool:paused forKey:[self metadataPauseKey:profile]];
    if(paused){[self stopAutomaticMetadata];[self persistMetadataNow];}
    else {self.automaticRetryAfter=0;[self ensureMetadataForProfile:profile priorityTracks:@[]];}
}
- (NSDictionary *)metadataCacheStatusForProfile:(NSDictionary *)profile {
    NSAssert([NSThread isMainThread],@"Cache status uses main-thread models");
    NSUInteger total=0,cached=0,empty=0,failed=0;NSString *identity=[self identityForProfile:profile];
    if(self.database){NSDictionary *counts=[self.database metadataStatus:profile];total=[counts[@"total"]unsignedIntegerValue];cached=[counts[@"cached"]unsignedIntegerValue];empty=[counts[@"empty"]unsignedIntegerValue];failed=[counts[@"failed"]unsignedIntegerValue];}
    else {
    for(NSDictionary *track in self.tracks){
        if(![track[@"profileID"]isEqual:profile[@"id"]]||![track[@"endpointIdentity"]isEqual:identity]||track[@"unsupportedReason"]||[track[@"unavailableRemote"]boolValue])continue;
        total++;if(!IPNeedsTags(track)){cached++;if([track[@"metadataCacheState"]isEqual:@"empty"])empty++;}else if([track[@"metadataCacheState"]isEqual:@"error"])failed++;
    }
    }
    BOOL active=[self.automaticProfile isEqual:identity];
    return @{@"total":@(total),@"cached":@(cached),@"empty":@(empty),@"failed":@(failed),@"pending":@(total-cached),
        @"running":@(active&&self.automaticRunning),@"paused":@([[NSUserDefaults standardUserDefaults]boolForKey:[self metadataPauseKey:profile]]),
        @"current":active?self.automaticCurrent?:@"":@"",@"error":active?self.automaticError?:@"":@""};
}
- (void)ensureMetadataForProfile:(NSDictionary *)profile priorityTracks:(NSArray *)tracks {
    if(!self.libraryLoaded || [profile[@"isExample"]boolValue])return;
    if(!profile[@"id"])return;
    if([[NSUserDefaults standardUserDefaults]boolForKey:[self metadataPauseKey:profile]])return;
    NSDictionary *target=[profile copy];NSString *identity=[self identityForProfile:target];
    NSMutableArray *priority=[NSMutableArray new];for(NSDictionary *t in tracks)if(t[@"id"])[priority addObject:t[@"id"]];
    NSUInteger generation;
    @synchronized(self){
        self.priorityIDs=priority;
        if(self.automaticRunning&&[self.automaticProfile isEqual:identity])return;
        if([self.automaticProfile isEqual:identity]&&[NSDate date].timeIntervalSince1970<self.automaticRetryAfter)return;
        self.automaticGeneration++;generation=self.automaticGeneration;self.automaticRunning=YES;self.automaticProfile=identity;
        self.automaticError=nil;self.automaticCurrent=nil;
    }
    NSMutableArray *snapshots=[NSMutableArray new];
    if(self.database)[snapshots addObjectsFromArray:[self.database pendingMetadata:target before:[NSDate date].timeIntervalSince1970 limit:256]];
    else for(NSDictionary *t in self.tracks)if([t[@"profileID"]isEqual:target[@"id"]]&&[t[@"endpointIdentity"]isEqual:identity]&&IPNeedsTags(t)&&[t[@"metadataRetryAfter"]doubleValue]<=[NSDate date].timeIntervalSince1970)[snapshots addObject:[t copy]];
    dispatch_async(self.metadataQueue,^{@autoreleasepool{
        NSMutableDictionary *pending=[NSMutableDictionary new];NSMutableArray *order=[NSMutableArray new];
        for(NSDictionary *t in snapshots){pending[t[@"id"]]=t;[order addObject:t[@"id"]];}
        NSUInteger cursor=0,failures=0,batchArtBytes=0;NSMutableArray *batch=[NSMutableArray new];NSTimeInterval batchStarted=[NSDate date].timeIntervalSince1970;
        IPSMB *client=nil;BOOL connected=NO;
        while(pending.count){
            @synchronized(self){if(generation!=self.automaticGeneration)break;}
            @autoreleasepool{
                NSString *tid=nil;
                @synchronized(self){for(NSString *candidate in self.priorityIDs)if(pending[candidate]&&(!self.playbackActive||[pending[candidate][@"extension"] isEqual:@"mp3"])){tid=candidate;break;}}
                while(!tid&&cursor<order.count){NSString *candidate=order[cursor++];if(pending[candidate])tid=candidate;}
                if(!tid)break;NSDictionary *track=pending[tid];[pending removeObjectForKey:tid];
                self.automaticCurrent=[track[@"path"]lastPathComponent];
                NSString *ext=[track[@"extension"] lowercaseString];
                if(self.playbackActive&&![ext isEqual:@"mp3"]){
                    pending[tid]=track;cursor=0;
                    NSMutableArray *mp3First=[NSMutableArray new],*other=[NSMutableArray new];
                    for(NSString *candidate in order)if(pending[candidate]){if([pending[candidate][@"extension"] isEqual:@"mp3"])[mp3First addObject:candidate];else [other addObject:candidate];}
                    [mp3First addObjectsFromArray:other];order=mp3First;
                    if(![pending[order.firstObject][@"extension"] isEqual:@"mp3"])[NSThread sleepForTimeInterval:.25];
                    continue;
                }
                NSError *error=nil;NSMutableDictionary *tags=nil;NSURL *local=[self localURL:track];
                if([track[@"mediaPersistentID"]length]){tags=[[IPLocalLibrary metadataForMediaID:track[@"mediaPersistentID"]]mutableCopy];}
                else if(IPIsLocalProfile(target)&&!local){error=IPStoreError(16,IPL(@"The local file is no longer available."));}
                else if([ext isEqual:@"mp3"]){
                    if(!local&&!connected){if(!client){NSMutableDictionary *settings=[target mutableCopy];settings[@"readTimeout"]=@5;client=[[IPSMB alloc]initWithProfile:settings password:[self passwordForProfile:target error:NULL]?:@""];}connected=[client connect:&error];}
                    NSFileHandle *file=local?[NSFileHandle fileHandleForReadingAtPath:local.path]:nil;
                    NSData *(^read)(uint64_t,NSUInteger)=^NSData *(uint64_t offset,NSUInteger length){
                        if(file){@try{[file seekToFileOffset:offset];return [file readDataOfLength:length];}@catch(NSException *exception){return nil;}}
                        return connected?[client read:track[@"path"] offset:offset length:length error:NULL]:nil;
                    };
                    tags=[[IPID3 readMetadataWithReader:read fileSize:[track[@"size"]unsignedLongLongValue] error:&error]mutableCopy];
                    [file closeFile];
                } else if([@[@"flac",@"ogg",@"oga",@"opus"]containsObject:ext]){
                    IPPCMServer *decoder=local?[[IPPCMServer alloc]initWithURL:local]:[[IPPCMServer alloc]initWithProfile:target password:[self passwordForProfile:target error:NULL]?:@"" path:track[@"path"] size:[track[@"size"] unsignedLongLongValue]];
                    if([decoder preparePCM:&error])tags=[decoder.metadata mutableCopy];[decoder closePCM];
                } else {
                    NSMutableDictionary *updated=[track mutableCopy];NSUInteger manualGeneration;@synchronized(self){manualGeneration=self.metadataGeneration;}
                    if([self loadMetadataForTrack:updated profile:target generation:manualGeneration])tags=updated;
                }
                if(tags){if([ext isEqual:@"mp3"])tags[@"artworkAutoVersion"]=@15;batchArtBytes+=[tags[@"artworkData"]length];BOOL found=[tags[@"title"]length]||[tags[@"artist"]length]||[tags[@"album"]length];tags[@"metadataAutoVersion"]=@14;tags[@"metadataCacheState"]=found?@"tagged":@"empty";tags[@"metadataRetryAfter"]=@0;[batch addObject:@{@"id":tid,@"tags":tags}];failures=0;}
                else{failures++;self.automaticError=error.localizedDescription?:IPL(@"No se pudo leer la etiqueta. Se reintentará más tarde.");[batch addObject:@{@"id":tid,@"tags":@{@"metadataCacheState":@"error",@"metadataRetryAfter":@([NSDate date].timeIntervalSince1970+600)}}];if(connected){[client disconnect];connected=NO;}}
                if(batch.count>=25 || batchArtBytes>=4*1024*1024 || [NSDate date].timeIntervalSince1970-batchStarted>=5 || !pending.count){[self applyMetadataBatch:[batch copy] completion:nil];[batch removeAllObjects];batchArtBytes=0;batchStarted=[NSDate date].timeIntervalSince1970;}
                if(failures>=3)break;
                [NSThread sleepForTimeInterval:self.playbackActive?.4:.08];
            }
        }
        if(batch.count)[self applyMetadataBatch:[batch copy] completion:nil];[client disconnect];
        @synchronized(self){if(generation==self.automaticGeneration){self.automaticRunning=NO;self.automaticCurrent=nil;self.automaticRetryAfter=[NSDate date].timeIntervalSince1970+(failures?60:0);}}
        if(self.database&&!failures&&snapshots.count==256)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(generation==self.automaticGeneration)[self ensureMetadataForProfile:profile priorityTracks:@[]];});
    }});
}

- (void)cancelMetadata {
    @synchronized (self) {
        self.metadataGeneration++;
        [self.activeMetadataAsset cancelLoading];
        [self.activeMetadataServer stop];
        self.activeMetadataAsset = nil;
        self.activeMetadataServer = nil;
    }
}

- (void)enrichProfile:(NSMutableDictionary *)profile progress:(IPStoreProgress)progress completion:(IPStoreCompletion)completion {
    __block NSDictionary *target = nil;
    dispatch_block_t capture = ^{ target = [profile copy]; };
    if ([NSThread isMainThread]) capture(); else dispatch_sync(dispatch_get_main_queue(), capture);
    [self cancelMetadata];
    NSUInteger generation;
    @synchronized (self) { generation = self.metadataGeneration; }
    dispatch_async(self.metadataQueue, ^{
        __block NSArray *pending = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSMutableArray *items = [NSMutableArray array];
            for (NSDictionary *track in self.tracks) if ([track[@"profileID"] isEqual:target[@"id"]] && [[track objectForKey:@"endpointIdentity"] isEqual:[self identityForProfile:target]] && ![track[@"unavailableRemote"] boolValue] && [track[@"metadataPending"] boolValue] && !track[@"unsupportedReason"]) [items addObject:[track copy]];
            pending = items;
        });
        NSUInteger completed = 0;
        NSMutableArray *updates = [NSMutableArray arrayWithCapacity:25];
        for (NSDictionary *snapshot in pending) {
            @synchronized (self) { if (generation != self.metadataGeneration) break; }
            @autoreleasepool {
                NSMutableDictionary *track = [snapshot mutableCopy];
                BOOL loaded = [self loadMetadataForTrack:track profile:target generation:generation];
                if (loaded) { track[@"metadataPending"] = @NO; track[@"metadataLoaded"] = @YES; [updates addObject:track]; }
            }
            completed++;
            if (updates.count >= 25 || completed == pending.count) {
                NSArray *batch = [updates copy]; [updates removeAllObjects];
                BOOL shouldSave = (completed % 250 == 0 || completed == pending.count);
                dispatch_semaphore_t committed = dispatch_semaphore_create(0);
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (NSDictionary *updated in batch) for (NSMutableDictionary *stored in self.tracks) if ([stored[@"id"] isEqual:updated[@"id"]] && [self profileForTrack:stored]) { [stored addEntriesFromDictionary:updated]; break; }
                    if (shouldSave) [self save];
                    dispatch_semaphore_signal(committed);
                });
                dispatch_semaphore_wait(committed, DISPATCH_TIME_FOREVER);
            }
            [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Reading metadata %lu of %lu"), (unsigned long)completed, (unsigned long)pending.count]];
        }
        BOOL canceled; @synchronized (self) { canceled = generation != self.metadataGeneration; }
        if (updates.count) {
            NSArray *batch = [updates copy];
            dispatch_semaphore_t committed = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSDictionary *updated in batch) for (NSMutableDictionary *stored in self.tracks) if ([stored[@"id"] isEqual:updated[@"id"]] && [self profileForTrack:stored]) { [stored addEntriesFromDictionary:updated]; break; }
                [self save]; dispatch_semaphore_signal(committed);
            });
            dispatch_semaphore_wait(committed, DISPATCH_TIME_FOREVER);
        } else if (completed % 250 != 0) {
            dispatch_semaphore_t saved = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{ [self save]; dispatch_semaphore_signal(saved); });
            dispatch_semaphore_wait(saved, DISPATCH_TIME_FOREVER);
        }
        [self finish:completion error:(canceled ? IPStoreError(10,IPL(@"Metadata scan was canceled.")) : nil)];
    });
}

- (void)refreshMetadataForTrack:(NSDictionary *)track completion:(IPStoreCompletion)completion {
    NSDictionary *snapshot = [track copy];
    [self cancelMetadata];
    NSUInteger generation; @synchronized (self) { generation = self.metadataGeneration; }
    dispatch_async(self.metadataQueue, ^{
        __block NSDictionary *profile = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{ profile = [[self profileForTrack:snapshot] copy]; });
        if (!profile) { [self finish:completion error:IPStoreError(11,IPL(@"Track's server endpoint is no longer available."))]; return; }
        NSMutableDictionary *updated = [snapshot mutableCopy];
        BOOL loaded = [self loadMetadataForTrack:updated profile:profile generation:generation];
        if(loaded)[self applyDecodedMetadata:updated toTrack:snapshot completion:completion];
        else dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(IPStoreError(12,IPL(@"Track metadata could not be read from the server.")));});
    });
}

- (void)reimportPlaylistsForProfile:(NSMutableDictionary *)profile progress:(IPStoreProgress)progress completion:(IPStoreCompletion)completion {
    if(IPIsLocalProfile(profile)){[self scanLocalLibraryWithProgress:progress completion:completion];return;}
    if ([profile[@"isExample"]boolValue]) { [self finish:completion error:IPStoreError(14,IPL(@"This is a fictional example. Edit the profile with your own server details before connecting."))]; return; }
    __block NSDictionary *target = nil;
    __block NSArray *trackSnapshot = nil;
    __block NSArray *playlistSnapshot = nil;
    dispatch_block_t capture = ^{
        target = [profile copy];
        NSMutableArray *tracks = [NSMutableArray array];
        for (NSDictionary *track in self.tracks) if ([track[@"profileID"] isEqual:target[@"id"]] && [[self identityForProfile:track] isEqual:[self identityForProfile:target]]) [tracks addObject:[track copy]];
        trackSnapshot = tracks;
        NSMutableArray *playlists = [NSMutableArray array];
        for (NSDictionary *playlist in self.playlists) if ([playlist[@"profileID"] isEqual:target[@"id"]] && [[playlist objectForKey:@"sourcePath"] length]) [playlists addObject:[playlist copy]];
        playlistSnapshot = playlists;
    };
    if ([NSThread isMainThread]) capture(); else dispatch_sync(dispatch_get_main_queue(), capture);
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSString *password = [self passwordForProfile:target error:&error] ?: @"";
        IPSMB *client = [[IPSMB alloc] initWithProfile:target password:password];
        if (![client connect:&error]) { [self finish:completion error:error]; return; }
        NSString *root = [self normalizedRoot:target[@"root"] ?: @""];
        NSMutableArray *m3us = [NSMutableArray array];
        if (playlistSnapshot.count) {
            for (NSDictionary *playlist in playlistSnapshot) {
                NSString *path = playlist[@"sourcePath"];
                uint64_t size = [client size:path error:NULL];
                if (size) [m3us addObject:@{@"path":path,@"size":@(size)}];
            }
        } else {
            NSString *path = @"All Tracks.m3u";
            uint64_t size = [client size:path error:NULL];
            if (size) [m3us addObject:@{@"path":path,@"size":@(size)}];
        }
        [client disconnect];
        if (m3us.count == 0) { [self finish:completion error:IPStoreError(13,IPL(@"No M3U playlists were found for this profile."))]; return; }
        NSArray *updated = [self importPlaylists:m3us profile:target root:root tracks:trackSnapshot progress:progress];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL stillCurrent = NO;
            for (NSDictionary *candidate in self.profiles) if ([candidate[@"id"] isEqual:target[@"id"]] && [[self identityForProfile:candidate] isEqual:[self identityForProfile:target]]) { stillCurrent = YES; break; }
            if (!stillCurrent) { [self finish:completion error:IPStoreError(9,IPL(@"The profile changed while playlists were importing."))]; return; }
            for (NSMutableDictionary *playlist in updated) {
                NSMutableDictionary *existing = nil;
                for (NSMutableDictionary *candidate in self.playlists) if ([candidate[@"id"] isEqual:playlist[@"id"]]) { existing = candidate; break; }
                if (existing) [existing addEntriesFromDictionary:playlist]; else [self.playlists addObject:playlist];
            }
            [self save];
            [self finish:completion error:nil];
        });
    });
}

- (NSArray *)importPlaylists:(NSArray *)m3us profile:(NSDictionary *)profile root:(NSString *)root tracks:(NSArray *)tracks progress:(IPStoreProgress)progress {
    if (!m3us.count) return @[];
    NSString *password = [self passwordForProfile:profile error:NULL] ?: @"";
    IPSMB *client = [[IPSMB alloc] initWithProfile:profile password:password]; NSError *error = nil;
    if (![client connect:&error]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableDictionary *trackByPath = [NSMutableDictionary dictionary];
    NSMutableArray *libraryPathSamples = [NSMutableArray array];
    for (NSDictionary *track in tracks) {
        trackByPath[track[@"path"]]=track;
        if (libraryPathSamples.count < 8) [libraryPathSamples addObject:track[@"path"] ?: @""];
    }
    NSSet *knownPaths = [NSSet setWithArray:trackByPath.allKeys];
    for (NSDictionary *item in m3us) {
      @autoreleasepool {
        uint64_t listedSize = [item[@"size"] unsignedLongLongValue];
        const uint64_t maximumPlaylistSize = 8ULL * 1024 * 1024;
        if (listedSize > maximumPlaylistSize) { [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Skipped oversized playlist %@"), item[@"path"]]]; continue; }
        NSData *data = [client read:item[@"path"] offset:0 length:(NSUInteger)MIN(listedSize, maximumPlaylistSize) error:NULL];
        NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (body.length && [body characterAtIndex:0] == 0xFEFF) body = [body substringFromIndex:1];
        if (!body && data) body = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
        if (!body) { [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Could not decode playlist %@"), item[@"path"]]]; continue; }
        NSMutableArray *trackIDs = [NSMutableArray array], *referenceSamples = [NSMutableArray array], *unresolvedSamples = [NSMutableArray array]; NSString *base = [item[@"path"] stringByDeletingLastPathComponent]; NSUInteger skipped = 0;
        for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *reference = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!reference.length || [reference hasPrefix:@"#"]) continue;
            NSString *sample = reference;
            if (referenceSamples.count < 8 || unresolvedSamples.count < 8) {
                if ([sample containsString:@"://"]) {
                    NSURLComponents *components = [NSURLComponents componentsWithString:sample];
                    sample = components.path ?: @"[unrecognized URL path]";
                } else if ([sample hasPrefix:@"//"]) {
                    NSArray *parts = [sample componentsSeparatedByString:@"/"];
                    sample = parts.count > 3 ? [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@"/"] : @"[UNC share path]";
                }
                if (referenceSamples.count < 8) [referenceSamples addObject:sample];
            }
            NSString *relative = [self resolvePlaylistReference:reference base:base root:root profile:profile knownPaths:knownPaths];
            NSDictionary *track = relative ? trackByPath[relative] : nil;
            if (track) [trackIDs addObject:track[@"id"]];
            else { skipped++; if (unresolvedSamples.count < 8) [unresolvedSamples addObject:sample]; }
        }
        NSString *playlistID = IPStoreHash([NSString stringWithFormat:@"%@\n%@\n%@", profile[@"id"] ?: @"", [self identityForProfile:profile], item[@"path"]]);
        if (skipped) [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Playlist %@ skipped %lu unmatched or unsafe entries"), item[@"path"], (unsigned long)skipped]];
        [result addObject:[@{@"id":playlistID,@"name":[[item[@"path"] lastPathComponent] stringByDeletingPathExtension],@"trackIDs":trackIDs,
                            @"profileID":profile[@"id"] ?: @"", @"sourceName":profile[@"name"] ?: profile[@"host"] ?: IPL(@"Server"),
                            @"sourceHost":profile[@"host"] ?: @"", @"sourcePath":item[@"path"] ?: @"",
                            @"skippedEntries":@(skipped), @"referenceSamples":referenceSamples, @"unresolvedSamples":unresolvedSamples,
                            @"libraryPathSamples":libraryPathSamples} mutableCopy]];
      }
    }
    [client disconnect];
    return result;
}

- (NSString *)resolvePlaylistReference:(NSString *)reference base:(NSString *)base root:(NSString *)root profile:(NSDictionary *)profile knownPaths:(NSSet *)knownPaths {
    NSString *ref = [reference stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if ([ref hasPrefix:@"//"] || [ref hasPrefix:@"smb://"]) {
        NSURLComponents *components = [NSURLComponents componentsWithString:([ref hasPrefix:@"smb://"] ? ref : [@"smb:" stringByAppendingString:ref])];
        if ([[components host] caseInsensitiveCompare:profile[@"host"] ?: @""] != NSOrderedSame) return nil;
        NSArray *parts = [components.path componentsSeparatedByString:@"/"];
        if (parts.count < 2 || [parts[1] caseInsensitiveCompare:profile[@"share"] ?: @""] != NSOrderedSame) return nil;
        ref = [[parts subarrayWithRange:NSMakeRange(2, parts.count-2)] componentsJoinedByString:@"/"];
        if ([ref hasPrefix:[root stringByAppendingString:@"/"]]) ref = [ref substringFromIndex:root.length+1]; else return nil;
    } else if ([ref hasPrefix:@"/"]) {
        NSString *absoluteRoot = [@"/" stringByAppendingString:root];
        if ([ref isEqualToString:absoluteRoot]) ref = @"";
        else if ([ref hasPrefix:[absoluteRoot stringByAppendingString:@"/"]]) ref = [ref substringFromIndex:absoluteRoot.length+1];
        else {
            /* Some media servers expose /music/<share-root> even when the SMB
             * share root is nested. Try suffix aliases, but accept only an exact
             * path already present in the scan index. */
            NSMutableArray *referenceParts = [NSMutableArray array];
            for (NSString *part in [ref componentsSeparatedByString:@"/"]) if (part.length) [referenceParts addObject:part];
            NSArray *rootParts = [root componentsSeparatedByString:@"/"];
            if (!rootParts.count || referenceParts.count < 2) return nil;
            NSMutableArray *aliases = [NSMutableArray array];
            for (NSUInteger length = rootParts.count; length > 0; length--) [aliases addObject:[rootParts subarrayWithRange:NSMakeRange(rootParts.count - length, length)]];
            NSString *resolved = nil;
            for (NSArray *alias in aliases) {
                for (NSUInteger start = 0; start + alias.count < referenceParts.count; start++) {
                    BOOL match = YES;
                    for (NSUInteger offset = 0; offset < alias.count; offset++) if (![referenceParts[start + offset] isEqualToString:alias[offset]]) { match = NO; break; }
                    if (!match) continue;
                    NSArray *tail = [referenceParts subarrayWithRange:NSMakeRange(start + alias.count, referenceParts.count - start - alias.count)];
                    NSMutableArray *safe = [NSMutableArray array]; BOOL invalid = NO;
                    for (NSString *part in tail) {
                        if ([part isEqualToString:@"."] || !part.length) continue;
                        if ([part isEqualToString:@".."] || [part containsString:@":"]) { invalid = YES; break; }
                        [safe addObject:part];
                    }
                    NSString *candidate = [safe componentsJoinedByString:@"/"];
                    if (!invalid && candidate.length && [knownPaths containsObject:candidate]) {
                        if (resolved && ![resolved isEqualToString:candidate]) return nil;
                        resolved = candidate;
                    }
                }
                if (resolved) break;
            }
            return resolved;
        }
    } else {
        ref = base.length ? [base stringByAppendingFormat:@"/%@", ref] : ref;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [ref componentsSeparatedByString:@"/"]) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) { if (!parts.count) return nil; [parts removeLastObject]; continue; }
        if ([part containsString:@":"]) return nil;
        [parts addObject:part];
    }
    NSString *candidate = parts.count ? [parts componentsJoinedByString:@"/"] : nil;
    return candidate && [knownPaths containsObject:candidate] ? candidate : nil;
}

- (BOOL)loadMetadataForTrack:(NSMutableDictionary *)track profile:(NSDictionary *)profile generation:(NSUInteger)generation {
    NSError *error = nil;
    if([track[@"mediaPersistentID"]length]){NSDictionary *tags=[IPLocalLibrary metadataForMediaID:track[@"mediaPersistentID"]];if(tags){[track addEntriesFromDictionary:tags];return YES;}return NO;}
    NSURL *local=[self localURLForTrack:track];
    if(IPIsLocalProfile(profile)&&!local)return NO;
    NSString *password = local?@"":[self passwordForProfile:profile error:&error] ?: @"";
    IPHTTPServer *server = [[IPHTTPServer alloc] initWithProfile:profile password:password
                                                            path:track[@"path"]
                                                            size:[track[@"size"] unsignedLongLongValue]];
    NSURL *url = nil;
    if(local){server=nil;url=local;}
    for (NSUInteger attempt = 0; attempt < 40 && !url; attempt++) {
        @synchronized (self) { if (generation != self.metadataGeneration) return NO; }
        url = [server start:&error];
        if (!url && [error.domain isEqualToString:@"IPHTTPServerErrorDomain"] && error.code == 16) [NSThread sleepForTimeInterval:0.025];
        else if (!url) break;
    }
    if (!url) return NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    @synchronized (self) { if (generation != self.metadataGeneration) { [server stop]; return NO; } self.activeMetadataServer = server; self.activeMetadataAsset = asset; }
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"duration", @"commonMetadata", @"availableMetadataFormats"] completionHandler:^{ dispatch_semaphore_signal(loaded); }];
    long waitResult = dispatch_semaphore_wait(loaded, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    BOOL canceled;
    @synchronized (self) { canceled = generation != self.metadataGeneration; }
    if (canceled) [asset cancelLoading];
    if (waitResult == 0) {
        NSError *statusError = nil;
        AVKeyValueStatus durationStatus = [asset statusOfValueForKey:@"duration" error:&statusError];
        if (durationStatus == AVKeyValueStatusLoaded) {
            Float64 seconds = CMTimeGetSeconds(asset.duration);
            if (isfinite(seconds) && seconds > 0) track[@"duration"] = @(seconds);
        }
        AVKeyValueStatus metadataStatus = [asset statusOfValueForKey:@"commonMetadata" error:NULL];
        if (metadataStatus == AVKeyValueStatusLoaded) {
            for (AVMetadataItem *item in IPMetadataItems(asset)) {
                NSString *identifier = item.identifier.lowercaseString ?: @"";
                NSString *commonKey = [item.commonKey lowercaseString] ?: @"";
                NSString *value = item.stringValue;
                if ([identifier containsString:@"trkn"] && [item.dataValue isKindOfClass:[NSData class]] && item.dataValue.length>=4) {const unsigned char*b=item.dataValue.bytes;track[@"trackNumber"]=@((b[2]<<8)|b[3]);}
                if (value.length) {
                    if ([commonKey isEqualToString:AVMetadataCommonKeyTitle]) track[@"title"] = value;
                    else if ([commonKey isEqualToString:AVMetadataCommonKeyArtist]) track[@"artist"] = value;
                    else if ([commonKey isEqualToString:AVMetadataCommonKeyAlbumName]) track[@"album"] = value;
                    else if ([identifier containsString:@"genre"] || [identifier containsString:@"gnre"]) track[@"genre"] = value;
                    else if ([identifier containsString:@"track"] || [identifier containsString:@"trkn"]) {
                        NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
                        NSMutableString *number = [NSMutableString string];
                        for (NSUInteger i = 0; i < value.length; i++) {
                            unichar c = [value characterAtIndex:i];
                            if ([digits characterIsMember:c]) [number appendFormat:@"%C", c];
                            else if (number.length) break;
                        }
                        if (number.length) track[@"trackNumber"] = @([number integerValue]);
                    }
                }
                if ([commonKey isEqualToString:AVMetadataCommonKeyArtwork] && [item.dataValue isKindOfClass:[NSData class]]) {
                    NSString *name = [NSString stringWithFormat:@"%@.artwork", IPStoreHash(track[@"id"] ?: @"")];
                    NSURL *artURL = [self.artworkURL URLByAppendingPathComponent:name];
                    if ([IPSmallArtwork(item.dataValue) writeToURL:artURL atomically:YES]) track[@"artwork"] = name;
                }
            }
        }
    } else {
        [asset cancelLoading];
    }
    [server stop];
    @synchronized (self) { if (self.activeMetadataServer == server) { self.activeMetadataServer = nil; self.activeMetadataAsset = nil; } }
    if (waitResult == 0 && !canceled) { track[@"metadataPending"] = @NO; track[@"metadataLoaded"] = @YES; return YES; }
    return NO;
}

- (void)downloadTracks:(NSArray<NSDictionary *> *)tracks progress:(IPStoreProgress)progress completion:(IPStoreCompletion)completion {
    [self cancelMetadata];
    NSArray *requested = [[NSArray alloc] initWithArray:tracks copyItems:YES];
    __block NSArray *profileCopies = nil;
    dispatch_block_t copyProfiles = ^{
        NSMutableArray *copies = [NSMutableArray arrayWithCapacity:self.profiles.count];
        for (NSDictionary *profile in self.profiles) [copies addObject:[profile copy]];
        profileCopies = copies;
    };
    if ([NSThread isMainThread]) copyProfiles(); else dispatch_sync(dispatch_get_main_queue(), copyProfiles);
    NSMutableDictionary *profilesByID = [NSMutableDictionary dictionary];
    for (NSDictionary *profile in profileCopies) if (profile[@"id"]) profilesByID[profile[@"id"]] = profile;
    dispatch_async(self.queue, ^{
        NSError *failure = nil;
        NSMutableArray *completedTracks = [NSMutableArray array];
        for (NSDictionary *track in requested) {
            if([track[@"profileID"]isEqual:IPLocalProfileID])continue;
            if ([self manualURLForTrack:track]) continue;
            NSURL *automatic=[self.smartCache localURLForTrack:track];
            if(automatic){
                [self recalculateCacheBytes];uint64_t size=[[[NSFileManager defaultManager]attributesOfItemAtPath:automatic.path error:NULL][NSFileSize]unsignedLongLongValue];
                NSURL *destination=[self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.media",IPStoreHash(track[@"id"])]];
                if(size>self.cacheLimitBytes||self.cacheBytes>self.cacheLimitBytes-size||![[NSFileManager defaultManager]copyItemAtURL:automatic toURL:destination error:&failure]){if(!failure)failure=IPStoreError(4,IPL(@"No hay espacio para guardar la descarga manual."));[[NSFileManager defaultManager]removeItemAtURL:destination error:NULL];break;}
                NSMutableDictionary *updated=[track mutableCopy];updated[@"downloaded"]=@YES;[completedTracks addObject:updated];[self recalculateCacheBytes];continue;
            }
            NSDictionary *profile = profilesByID[track[@"profileID"]];
            NSString *trackIdentity = [track[@"endpointIdentity"] length] ? track[@"endpointIdentity"] : track[@"profileID"];
            NSString *profileIdentity = [self identityForProfile:profile];
            if (!profile || ![trackIdentity isEqual:profileIdentity]) { failure=IPStoreError(3,IPL(@"Track belongs to an outdated or missing server profile.")); break; }
            NSString *password=[self passwordForProfile:profile error:&failure] ?: @"";
            IPSMB *client=[[IPSMB alloc] initWithProfile:profile password:password];
            if (![client connect:&failure]) break;
            uint64_t size=[client size:track[@"path"] error:&failure];
            if (failure) { [client disconnect]; break; }
            [self recalculateCacheBytes];
            NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfFileSystemForPath:self.cacheURL.path error:&failure];
            unsigned long long freeBytes=[attrs[NSFileSystemFreeSize] unsignedLongLongValue];
            if (failure || size > self.cacheLimitBytes || self.cacheBytes > self.cacheLimitBytes-size || size > freeBytes) {
                [client disconnect]; failure=IPStoreError(4,IPL(@"There is not enough cache or device space for this download.")); break;
            }
            NSURL *finalURL=[self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.media",IPStoreHash(track[@"id"] ?: @"")]];
            NSURL *partURL=[self.cacheURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.part",IPStoreHash(track[@"id"] ?: @"")]];
            [[NSFileManager defaultManager] removeItemAtURL:partURL error:NULL];
            [[NSFileManager defaultManager] createFileAtPath:partURL.path contents:nil attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:partURL.path];
            if (!handle) { [client disconnect]; failure=IPStoreError(5,IPL(@"Could not create a temporary download file.")); break; }
            BOOL ok=YES;
            uint64_t offset = 0;
            while (offset < size) {
                @autoreleasepool {
                    NSUInteger length=(NSUInteger)MIN((uint64_t)IPStoreChunkSize,size-offset);
                    NSData *chunk=[client read:track[@"path"] offset:offset length:length error:&failure];
                    if (!chunk || chunk.length==0) { ok=NO; }
                    else {
                        @try { [handle writeData:chunk]; } @catch (NSException *exception) { failure=IPStoreError(6,IPL(@"Could not write downloaded data.")); ok=NO; }
                        if (ok) {
                            offset += chunk.length;
                            [self sendProgress:progress message:[NSString stringWithFormat:IPL(@"Downloading %@ (%llu%%)"),track[@"title"] ?: @"track",size ? (unsigned long long)(offset*100/size) : 100ULL]];
                            if (chunk.length < length) { failure=IPStoreError(7,IPL(@"The server ended the file before the advertised size.")); ok=NO; }
                        }
                    }
                }
                if (!ok) break;
            }
            @try { [handle closeFile]; } @catch (__unused NSException *exception) {}
            [client disconnect];
            NSDictionary *written=[[NSFileManager defaultManager] attributesOfItemAtPath:partURL.path error:NULL];
            if (ok && [written[NSFileSize] unsignedLongLongValue]==size) {
                [[NSFileManager defaultManager] removeItemAtURL:finalURL error:NULL];
                if (![[NSFileManager defaultManager] moveItemAtURL:partURL toURL:finalURL error:&failure]) ok=NO;
            } else if (ok) { failure=IPStoreError(7,IPL(@"Downloaded file size did not match the server file.")); ok=NO; }
            if (!ok) { [[NSFileManager defaultManager] removeItemAtURL:partURL error:NULL]; if (!failure) failure=IPStoreError(8,IPL(@"Download did not complete.")); break; }
            NSMutableDictionary *updated = [track mutableCopy];
            updated[@"downloaded"] = @YES; updated[@"size"] = @(size);
            [self updateLocalMetadata:updated URL:finalURL];
            [completedTracks addObject:updated];
            [self recalculateCacheBytes];
        }
        dispatch_semaphore_t downloadCommitDone = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *updated in completedTracks) {
                for (NSMutableDictionary *stored in self.tracks) if ([stored[@"id"] isEqual:updated[@"id"]]) { [stored addEntriesFromDictionary:updated]; break; }
            }
            [self save];
            [self finish:completion error:failure];
            dispatch_semaphore_signal(downloadCommitDone);
        });
        dispatch_semaphore_wait(downloadCommitDone, DISPATCH_TIME_FOREVER);
    });
}

- (void)updateLocalMetadata:(NSMutableDictionary *)track URL:(NSURL *)url {
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];
    Float64 seconds=CMTimeGetSeconds(asset.duration); if (isfinite(seconds) && seconds>0) track[@"duration"]=@(seconds);
    for (AVMetadataItem *item in IPMetadataItems(asset)) {
        NSString *key=[item.commonKey lowercaseString]; id value=item.stringValue;
        if (!value) continue;
        if ([key isEqualToString:AVMetadataCommonKeyTitle]) track[@"title"]=value;
        else if ([key isEqualToString:AVMetadataCommonKeyArtist]) track[@"artist"]=value;
        else if ([key isEqualToString:AVMetadataCommonKeyAlbumName]) track[@"album"]=value;
        else if ([item.identifier.lowercaseString containsString:@"genre"]) track[@"genre"]=value;
    }
    for (AVMetadataItem *item in IPMetadataItems(asset)) if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtwork] && [item.dataValue isKindOfClass:[NSData class]]) {
        NSString *artwork=[url.lastPathComponent stringByAppendingString:@".artwork"];
        NSURL *artURL=[self.artworkURL URLByAppendingPathComponent:artwork]; [IPSmallArtwork(item.dataValue) writeToURL:artURL atomically:YES]; track[@"artwork"]=artwork; break;
    }
}

@end

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "../Sources/IPStore.h"
#import "IPSmartCache.h"
#import "IPLibraryDB.h"
#import "IPLocalLibrary.h"
#import "../Sources/IPSMB.h"
#import "../Sources/IPHTTPServer.h"

@interface IPStore (HostTestStorage)
- (instancetype)initWithSupportURL:(NSURL *)supportURL;
- (instancetype)initWithSupportURL:(NSURL *)supportURL deferred:(BOOL)deferred;
@end

@interface LocalTestStore : IPStore
@property(nonatomic,strong) NSArray *testRoots;
@end
@implementation LocalTestStore
- (NSArray *)localFileRoots {return self.testRoots?:@[];}
@end

static NSUInteger onceReads=0,coverReads=0;
static NSData *coverMP3;
static NSData *CoverMP3(void) {
    unsigned char pixel[]={255,40,80,255};CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixel,1,1,8,4,color,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);CGImageRef image=CGBitmapContextCreateImage(context);
    NSMutableData *jpeg=[NSMutableData new];CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg,CFSTR("public.jpeg"),1,NULL);CGImageDestinationAddImage(dest,image,NULL);NSCAssert(CGImageDestinationFinalize(dest),@"test JPEG failed");CFRelease(dest);CGImageRelease(image);CGContextRelease(context);CGColorSpaceRelease(color);
    const unsigned char prefix[]={0,'i','m','a','g','e','/','j','p','g',0,3,0};NSMutableData *apic=[NSMutableData dataWithBytes:prefix length:sizeof(prefix)];[apic appendData:jpeg];
    NSMutableData *frames=[NSMutableData dataWithBytes:"TIT2\0\0\0\6\0\0\3Title" length:16];[frames appendBytes:"APIC" length:4];NSUInteger n=apic.length;unsigned char size[]={n>>24,n>>16,n>>8,n,0,0};[frames appendBytes:size length:6];[frames appendData:apic];n=frames.length;unsigned char h[]={'I','D','3',3,0,0,(n>>21)&127,(n>>14)&127,(n>>7)&127,n&127};NSMutableData *file=[NSMutableData dataWithBytes:h length:10];[file appendData:frames];return file;
}
static NSUInteger smbConnections;
@implementation IPSMB
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password { return [super init]; }
- (BOOL)connect:(NSError **)error { smbConnections++; return YES; }
- (NSArray *)list:(NSString *)path error:(NSError **)error {
    if (!path.length) return @[
        @{@"name":@"Älbum", @"path":@"media/data/music/Example/Älbum", @"directory":@YES, @"size":@0},
        @{@"name":@"mix.m3u", @"path":@"media/data/music/Example/mix.m3u", @"directory":@NO, @"size":@250}
    ];
    if ([path isEqualToString:@"Älbum"]) return @[
        @{@"name":@"01.mp3", @"path":@"media/data/music/Example/Älbum/01.mp3", @"directory":@NO, @"size":@100},
        @{@"name":@"02.mp3", @"path":@"media/data/music/Example/Älbum/02.mp3", @"directory":@NO, @"size":@100},
        @{@"name":@"cover.jpg", @"path":@"media/data/music/Example/Älbum/cover.jpg", @"directory":@NO, @"size":@10},
        @{@"name":@"uncompressed.flac", @"path":@"media/data/music/Example/Älbum/uncompressed.flac", @"directory":@NO, @"size":@100},
        @{@"name":@"recording.ogg", @"path":@"media/data/music/Example/Älbum/recording.ogg", @"directory":@NO, @"size":@100},
        @{@"name":@"recording.opus", @"path":@"media/data/music/Example/Älbum/recording.opus", @"directory":@NO, @"size":@100},
        @{@"name":@"legacy.wma", @"path":@"media/data/music/Example/Älbum/legacy.wma", @"directory":@NO, @"size":@100}
    ];
    return @[];
}
- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if([path isEqual:@"legacy-cover.mp3"]){coverReads++;return [coverMP3 subdataWithRange:NSMakeRange((NSUInteger)offset,MIN(length,coverMP3.length-(NSUInteger)offset))];}
    if([path isEqual:@"once.mp3"])onceReads++;
    if ([path isEqualToString:@"mix.m3u"]) {
        NSString *text = @"\uFEFF#EXTM3U\r\n/music/Example/Älbum/02.mp3\r\n/music/Example/Älbum/01.mp3\r\n/music/Example/Älbum/uncompressed.flac\r\n/music/Example/Älbum/02.mp3\r\n/elsewhere/02.mp3\r\n/music/Example/../../etc/secret.mp3\r\n";
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        return [data subdataWithRange:NSMakeRange((NSUInteger)offset, MIN(length, data.length-(NSUInteger)offset))];
    }
    NSData *data = [NSMutableData dataWithLength:100];
    if (offset >= data.length) return [NSData data];
    return [data subdataWithRange:NSMakeRange((NSUInteger)offset, MIN(length,data.length-(NSUInteger)offset))];
}
- (uint64_t)size:(NSString *)path error:(NSError **)error { return [path isEqualToString:@"mix.m3u"] ? 250 : 100; }
- (void)disconnect {}
@end

@implementation IPHTTPServer
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size { return [super init]; }
- (NSURL *)start:(NSError **)error { return nil; }
- (void)stop {}
@end

static void IPWaitForFlag(volatile BOOL *done) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!*done && [end timeIntervalSinceNow] > 0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    NSCAssert(*done, @"asynchronous store operation timed out");
}

int main(void) {
    @autoreleasepool {
        NSURL *temporaryRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
        NSURL *storeRoot = [temporaryRoot URLByAppendingPathComponent:@"IPStore" isDirectory:YES];
        IPStore *store = [[IPStore alloc] initWithSupportURL:storeRoot];
        NSCAssert(store.profiles.count == 1, @"first launch should seed one server profile");
        NSCAssert([store.profiles[0][@"host"] isEqual:@"music.example.invalid"], @"first launch profile host mismatch");
        NSCAssert([store.profiles[0][@"root"] isEqual:@"Sample Library"], @"first launch profile root mismatch");

        NSCAssert([store.profiles[0][@"isExample"]boolValue] && [store.profiles[0][@"name"]isEqual:@"Example Music Server"], @"new users must see a fictional English example only");
        NSUInteger initialConnections=smbConnections;
        [store refreshProfileIfNeeded:store.profiles[0]];
        [store ensureMetadataForProfile:store.profiles[0] priorityTracks:@[]];
        __block volatile BOOL sampleDone=NO;
        [store scanProfile:store.profiles[0] progress:nil completion:^(NSError *e){NSCAssert(e.code==14,@"example scan must explain configuration without connecting");sampleDone=YES;}];
        IPWaitForFlag(&sampleDone);
        NSCAssert(smbConnections==initialConnections,@"fictional example attempted a network connection");

        // Upgrade a ready library without materializing or modifying any existing track.
        NSURL *upgradeRoot=[temporaryRoot URLByAppendingPathComponent:@"existing-library" isDirectory:YES];
        [[NSFileManager defaultManager]createDirectoryAtURL:upgradeRoot withIntermediateDirectories:YES attributes:nil error:NULL];
        IPLibraryDB *upgradeDB=[[IPLibraryDB alloc]initWithURL:[upgradeRoot URLByAppendingPathComponent:@"library.sqlite"]];
        NSDictionary *existingProfile=@{@"id":@"existing-profile",@"endpointIdentity":@"existing-endpoint",@"name":@"Existing Music",@"host":@"archive.example.invalid",@"share":@"Archive",@"root":@"Old Library",@"username":@"existing-user",@"default":@YES};
        NSDictionary *existingTrack=@{@"id":@"existing-track",@"profileID":existingProfile[@"id"],@"endpointIdentity":existingProfile[@"endpointIdentity"],@"title":@"Saved title",@"artist":@"Saved artist",@"path":@"song.mp3",@"extension":@"mp3",@"favorite":@YES,@"metadataAutoVersion":@15,@"metadataLoaded":@YES,@"downloaded":@YES,@"artwork":@"keep.png"};
        NSDictionary *existingPlaylist=@{@"id":@"existing-playlist",@"name":@"Saved queue",@"trackIDs":@[existingTrack[@"id"]]};
        NSCAssert(([upgradeDB commitState:@{@"profiles":@[existingProfile],@"playlists":@[existingPlaylist],@"cacheLimitBytes":@1234567} tracks:@[existingTrack] IDs:@[existingTrack[@"id"]]]&&[upgradeDB finishImport]),@"could not seed upgrade fixture");
        NSArray *keepPaths=@[@"Downloads/keep.media",@"Artwork/keep.png",@"decoded-metadata.json",@"favorites.json",@"playback-position.json",@"playback-queue.json"];
        NSData *keep=[@"preserved fixture data" dataUsingEncoding:NSUTF8StringEncoding];
        for(NSString *path in keepPaths){NSURL *url=[upgradeRoot URLByAppendingPathComponent:path];[[NSFileManager defaultManager]createDirectoryAtURL:[url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];[keep writeToURL:url atomically:YES];}
        NSString *automaticKey=@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        NSURL *automaticFile=[upgradeRoot URLByAppendingPathComponent:[NSString stringWithFormat:@"SmartCache/%@.media",automaticKey]];
        [[NSFileManager defaultManager]createDirectoryAtURL:[automaticFile URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        [keep writeToURL:automaticFile atomically:YES];
        NSData *manifest=[NSJSONSerialization dataWithJSONObject:@{@"entries":@{automaticKey:@{@"size":@(keep.length),@"used":@100}},@"enabled":@YES,@"limit":@1048576} options:0 error:NULL];
        [manifest writeToURL:[upgradeRoot URLByAppendingPathComponent:@"SmartCache/manifest.json"] atomically:YES];
        IPStore *upgraded=[[IPStore alloc]initWithSupportURL:upgradeRoot];
        NSCAssert(upgraded.profiles.count==2&&[upgraded.profiles[0]isEqual:existingProfile],@"upgrade changed the saved server or did not add the example");
        NSCAssert([(IPTrackCollection *)upgraded.tracks materializedTracks].count==0,@"adding the example loaded track metadata");
        NSCAssert([[upgraded.database track:@"existing-track"]isEqual:existingTrack]&&[upgraded.playlists[0]isEqual:existingPlaylist]&&upgraded.cacheLimitBytes==1234567,@"upgrade changed tags, favorites, download flags, queue references or limits");
        for(NSString *path in keepPaths)NSCAssert([keep isEqual:[NSData dataWithContentsOfURL:[upgradeRoot URLByAppendingPathComponent:path]]],@"upgrade rewrote cached data: %@",path);
        NSCAssert([upgraded.smartCache.status[@"count"]intValue]==1&&[keep isEqual:[NSData dataWithContentsOfURL:automaticFile]]&&[manifest isEqual:[NSData dataWithContentsOfURL:[upgradeRoot URLByAppendingPathComponent:@"SmartCache/manifest.json"]]],@"upgrade lost the automatic cache or changed its manifest");
        NSString *sampleIdentity=[upgraded.profiles[1][@"endpointIdentity"]copy];
        IPStore *upgradeAgain=[[IPStore alloc]initWithSupportURL:upgradeRoot];
        NSCAssert(upgradeAgain.profiles.count==2&&[upgradeAgain.profiles[1][@"endpointIdentity"]isEqual:sampleIdentity],@"reopening duplicated or recreated the example");
        IPStore *editableExample=[[IPStore alloc]initWithSupportURL:[temporaryRoot URLByAppendingPathComponent:@"configured-example"]];
        NSCAssert([editableExample setEndpoint:@{@"host":@"custom.example.invalid"} forProfileID:editableExample.profiles[0][@"id"] error:NULL]&&![editableExample.profiles[0][@"isExample"]boolValue],@"editing the example did not activate the configured profile");
        [editableExample flushPersistence];
        NSCAssert([upgradeAgain deleteProfile:upgradeAgain.profiles[1] error:NULL],@"could not remove example");[upgradeAgain flushPersistence];
        NSCAssert([(IPTrackCollection *)upgradeAgain.tracks materializedTracks].count==0,@"removing the example loaded unrelated metadata");
        IPStore *afterRemoval=[[IPStore alloc]initWithSupportURL:upgradeRoot];
        NSCAssert(afterRemoval.profiles.count==1&&[afterRemoval.profiles[0]isEqual:existingProfile],@"removed example reappeared or existing server changed");
        [afterRemoval.profiles removeAllObjects];[afterRemoval save];[afterRemoval flushPersistence];
        IPStore *emptyReopen=[[IPStore alloc]initWithSupportURL:upgradeRoot];
        NSCAssert(emptyReopen.profiles.count==0,@"an intentionally empty server list was reseeded");
        printf("Example profile: new install, inert sample, preservation of existing library/cache, one-time upgrade, edit and removal passed\n");

        [store.profiles removeAllObjects]; [store.tracks removeAllObjects]; [store.playlists removeAllObjects];
        NSMutableDictionary *profile = [@{@"id":@"host-test", @"endpointIdentity":@"identity-a", @"name":@"Test music",
                                          @"host":@"127.0.0.1", @"share":@"share", @"root":@"media/data/music/Example", @"username":@"test"} mutableCopy];
        [store.profiles addObject:profile]; [store save];
        [store flushPersistence];
        __block volatile BOOL done = NO;
        [store scanProfile:profile progress:nil completion:^(NSError *error) { NSCAssert(error == nil, @"scan failed: %@", error); done = YES; }];
        IPWaitForFlag(&done);
        [store flushPersistence];
        NSCAssert(store.tracks.count == 6, @"scan should keep supported and unsupported audio, but skip cover image");
        NSMutableDictionary *unsupported = nil;
        for (NSMutableDictionary *track in store.tracks) if ([track[@"extension"] isEqual:@"flac"]) unsupported = track;
        NSCAssert(!unsupported[@"unsupportedReason"], @"FFmpeg-supported FLAC must not be marked unsupported");
        NSMutableDictionary *wma = nil;
        for (NSMutableDictionary *candidate in store.tracks) if ([candidate[@"extension"] isEqual:@"wma"]) wma = candidate;
        NSCAssert([wma[@"unsupportedReason"] length] > 0, @"WMA should remain explicitly unsupported");
        NSCAssert(store.playlists.count == 1, @"M3U playlist should import");
        NSArray *orderedIDs = store.playlists[0][@"trackIDs"];
        NSCAssert(orderedIDs.count == 4, @"playlist should retain valid alias references and duplicates while rejecting outside paths");
        NSCAssert([orderedIDs[0] isEqual:store.tracks[1][@"id"]], @"M3U reference order was not preserved");
        NSCAssert([orderedIDs[2] isEqual:unsupported[@"id"]], @"M3U import should retain unsupported audio track references");
        NSCAssert([orderedIDs[3] isEqual:store.tracks[1][@"id"]], @"duplicate M3U references should preserve order");
        NSArray *refSamples = store.playlists[0][@"referenceSamples"];
        NSCAssert([refSamples count] == 6 && [refSamples[0] isEqual:@"/music/Example/Älbum/02.mp3"], @"playlist reference diagnostics should contain safe path samples");
        NSCAssert([store.playlists[0][@"sourcePath"] isEqual:@"mix.m3u"], @"playlist source path should be retained for reimport diagnostics");
        done = NO;
        [store reimportPlaylistsForProfile:profile progress:nil completion:^(NSError *error) { NSCAssert(error == nil, @"targeted playlist reimport failed: %@", error); done = YES; }];
        IPWaitForFlag(&done);
        NSCAssert([store.playlists[0][@"trackIDs"] count] == 4, @"targeted reimport should resolve from the cached track index");

        NSURL *jsonURL = [storeRoot URLByAppendingPathComponent:@"library.json"];
        NSData *jsonData = [NSData dataWithContentsOfURL:jsonURL];
        NSDictionary *loaded = store.database ? @{@"profiles":store.database.state[@"profiles"],@"tracks":[store materializeTrackIDs:store.database.trackIDs],@"playlists":store.database.state[@"playlists"]} : [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
        NSCAssert([loaded[@"profiles"] count] == 1 && [loaded[@"tracks"] count] == 6, @"atomic JSON snapshot did not persist the library");
        IPStore *reloadedStore = [[IPStore alloc] initWithSupportURL:storeRoot];
        NSCAssert([reloadedStore.profiles[0][@"id"] isEqual:@"host-test"] && reloadedStore.tracks.count == 6, @"saved JSON did not reload into the library");

        NSMutableDictionary *favoriteTrack = nil;
        for (NSMutableDictionary *candidate in store.tracks) if ([candidate[@"path"] hasSuffix:@"01.mp3"]) favoriteTrack = candidate;
        NSString *favoriteID = favoriteTrack[@"id"];
        NSCAssert([store setFavorite:YES forTrack:favoriteTrack], @"favorite toggle failed");
        NSCAssert([store setFavorite:NO forTrack:favoriteTrack], @"favorite untoggle failed");
        NSCAssert([store setFavorite:YES forTrack:favoriteTrack], @"rapid favorite toggle failed");
        [store save]; [store flushPersistence];
        IPStore *favoriteReload = [[IPStore alloc] initWithSupportURL:storeRoot];
        NSMutableDictionary *reloadedFavorite = nil;
        for (NSMutableDictionary *candidate in favoriteReload.tracks) if ([candidate[@"id"] isEqual:favoriteID]) reloadedFavorite = candidate;
        NSCAssert([reloadedFavorite[@"favorite"] boolValue], @"favorite override did not survive normal save and reload");

        done = NO;
        [store applyDecodedMetadata:@{@"title":@"Etiquetas",@"artist":@"Árbol",@"album":@"Álbum",@"trackNumber":@3,@"duration":@7} toTrack:favoriteTrack completion:^(NSError *error) { NSCAssert(!error,@"metadata apply failed"); done = YES; }];
        IPWaitForFlag(&done); [store flushPersistence];
        NSCAssert([favoriteTrack[@"title"] isEqual:@"Etiquetas"] && [favoriteTrack[@"favorite"] boolValue], @"metadata merge lost values or favorites");
        IPStore *tagReload = [[IPStore alloc] initWithSupportURL:storeRoot];
        NSDictionary *reloadedTags = nil;
        for (NSDictionary *candidate in tagReload.tracks) if ([candidate[@"id"] isEqual:favoriteID]) reloadedTags = candidate;
        NSCAssert([reloadedTags[@"artist"] isEqual:@"Árbol"] && [reloadedTags[@"title"] isEqual:@"Etiquetas"], @"metadata overlay did not survive restart");
        NSMutableDictionary *automaticTrack=nil;
        for(NSMutableDictionary *candidate in store.tracks)if([candidate[@"path"] hasSuffix:@"02.mp3"])automaticTrack=candidate;
        [store ensureMetadataForProfile:profile priorityTracks:@[automaticTrack]];
        NSDate *automaticEnd=[NSDate dateWithTimeIntervalSinceNow:10];
        while([automaticTrack[@"metadataAutoVersion"] integerValue]<14 && automaticEnd.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert([automaticTrack[@"metadataAutoVersion"] integerValue]==14,@"automatic bounded MP3 indexing did not finish");
        [store stopAutomaticMetadata];
        NSMutableDictionary *track = store.tracks[0];
        NSString *identity = profile[@"endpointIdentity"];
        NSCAssert([store setEndpoint:@{@"name":@"Renamed"} forProfileID:profile[@"id"] error:NULL], @"display-name update failed");
        NSCAssert([profile[@"endpointIdentity"] isEqual:identity], @"display-name edit must not rotate endpoint identity");
        NSCAssert([store setEndpoint:@{@"root":@"other"} forProfileID:profile[@"id"] error:NULL], @"root update failed");
        NSCAssert(![profile[@"endpointIdentity"] isEqual:identity], @"root edit must rotate endpoint identity");
        NSCAssert([store.tracks containsObject:track], @"endpoint edits must preserve old library entries");
        NSCAssert([store profileForTrack:track] == nil, @"retired tracks must not stream against a changed endpoint");
        // A file with no tags is complete too; persist it and prove reopening makes no SMB reads.
        NSURL *onceRoot=[temporaryRoot URLByAppendingPathComponent:@"Once"];
        IPStore *once=[[IPStore alloc]initWithSupportURL:onceRoot];[once.profiles removeAllObjects];[once.tracks removeAllObjects];
        NSMutableDictionary *onceProfile=[@{@"id":@"once-test",@"endpointIdentity":[[NSUUID UUID]UUIDString],@"name":@"Once",@"host":@"127.0.0.1",@"share":@"s",@"root":@"",@"username":@"t"}mutableCopy];
        [once.profiles addObject:onceProfile];
        NSMutableDictionary *onceTrack=[@{@"id":@"once-track",@"profileID":@"once-test",@"endpointIdentity":onceProfile[@"endpointIdentity"],@"path":@"once.mp3",@"extension":@"mp3",@"size":@100,@"title":@"once",@"metadataPending":@YES}mutableCopy];
        [once.tracks addObject:onceTrack];[once save];[once flushPersistence];
        [once setMetadataPaused:YES forProfile:onceProfile];[once ensureMetadataForProfile:onceProfile priorityTracks:@[]];
        NSCAssert(onceReads==0&&[[once metadataCacheStatusForProfile:onceProfile][@"paused"]boolValue],@"paused cache read a file");
        [once setMetadataPaused:NO forProfile:onceProfile];NSDate *end=[NSDate dateWithTimeIntervalSinceNow:10];
        while([onceTrack[@"metadataAutoVersion"]intValue]!=14&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert([onceTrack[@"metadataAutoVersion"]intValue]==14&&onceReads>0,@"empty MP3 did not finish");
        [once stopAutomaticMetadata];[once flushPersistence];NSUInteger reads=onceReads;
        IPStore *reopen=[[IPStore alloc]initWithSupportURL:onceRoot];[reopen ensureMetadataForProfile:reopen.profiles[0] priorityTracks:@[]];
        end=[NSDate dateWithTimeIntervalSinceNow:.2];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSDictionary *status=[reopen metadataCacheStatusForProfile:reopen.profiles[0]];
        NSCAssert(onceReads==reads&&[status[@"cached"]intValue]==1&&[status[@"pending"]intValue]==0&&[status[@"empty"]intValue]==1,@"cache reread a completed empty MP3 after restart");
        [reopen setMetadataPaused:YES forProfile:reopen.profiles[0]];IPStore *pausedReopen=[[IPStore alloc]initWithSupportURL:onceRoot];
        NSCAssert([[pausedReopen metadataCacheStatusForProfile:pausedReopen.profiles[0]][@"paused"]boolValue],@"pause did not survive restart");
        [pausedReopen setMetadataPaused:NO forProfile:pausedReopen.profiles[0]];[pausedReopen stopAutomaticMetadata];[reopen stopAutomaticMetadata];
        puts("Persistent one-time empty-tag cache and pause/resume checks passed");
        // Text cached by old releases must not hide an APIC that was beyond the old read cap.
        coverMP3=CoverMP3();NSURL *coverRoot=[temporaryRoot URLByAppendingPathComponent:@"CoverRepair"];
        IPStore *covers=[[IPStore alloc]initWithSupportURL:coverRoot];[covers.profiles removeAllObjects];[covers.tracks removeAllObjects];[covers.profiles addObject:onceProfile];
        NSMutableDictionary *legacyCover=[@{@"id":@"legacy-cover",@"profileID":onceProfile[@"id"],@"endpointIdentity":onceProfile[@"endpointIdentity"],@"path":@"legacy-cover.mp3",@"extension":@"mp3",@"size":@(coverMP3.length),@"title":@"Title",@"artist":@"Artist",@"album":@"Album",@"metadataLoaded":@YES,@"metadataPending":@NO,@"metadataAutoVersion":@13}mutableCopy];
        NSMutableDictionary *legacy14=[legacyCover mutableCopy];legacy14[@"id"]=@"legacy-cover14";legacy14[@"metadataAutoVersion"]=@14;
        [covers.tracks addObject:legacyCover];[covers.tracks addObject:legacy14];[covers save];[covers flushPersistence];
        NSCAssert([[covers metadataCacheStatusForProfile:onceProfile][@"pending"]intValue]==2,@"legacy missing cover was skipped");
        [covers ensureMetadataForProfile:onceProfile priorityTracks:@[legacyCover]];end=[NSDate dateWithTimeIntervalSinceNow:10];
        while(([legacyCover[@"artworkAutoVersion"]intValue]!=15||[legacy14[@"artworkAutoVersion"]intValue]!=15)&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert([legacyCover[@"artworkAutoVersion"]intValue]==15&&[legacy14[@"artworkAutoVersion"]intValue]==15&&[covers artworkURLForTrack:legacyCover]&&[covers artworkURLForTrack:legacy14]&&coverReads>0,@"legacy cover not recovered");
        NSCAssert([legacyCover[@"artist"]isEqual:@"Artist"]&&[legacyCover[@"album"]isEqual:@"Album"],@"cover repair lost text metadata");
        [covers stopAutomaticMetadata];[covers flushPersistence];NSUInteger oldCoverReads=coverReads;
        IPStore *coverReopen=[[IPStore alloc]initWithSupportURL:coverRoot];[coverReopen ensureMetadataForProfile:coverReopen.profiles[0] priorityTracks:@[]];end=[NSDate dateWithTimeIntervalSinceNow:.2];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert(coverReads==oldCoverReads&&[coverReopen artworkURLForTrack:coverReopen.tracks[0]],@"cover repair did not persist or unnecessarily reread");[coverReopen stopAutomaticMetadata];
        puts("Legacy cached-text cover recovery and persistent one-time repair passed");
        [once.smartCache prefetchQueue:@[onceTrack] index:0 profiles:@[onceProfile] password:nil];[once.smartCache flush];
        NSCAssert([once localURL:onceTrack],@"automatic cache was not available to playback");NSUInteger readsBeforePromotion=onceReads;done=NO;
        [once downloadTracks:@[onceTrack] progress:nil completion:^(NSError *error){NSCAssert(!error,@"automatic-to-manual copy failed: %@",error);done=YES;}];IPWaitForFlag(&done);
        NSCAssert([onceTrack[@"downloaded"]boolValue]&&onceReads==readsBeforePromotion,@"manual download did not reuse complete automatic copy");
        [once.smartCache protectTrack:@{}];[once.smartCache clear];[once.smartCache flush];NSCAssert([once localURL:onceTrack],@"clearing automatic cache removed manual download");
        puts("Automatic-cache playback fallback and offline promotion to a separate manual download passed");
        // Cold startup must not parse the large library before the first UI turn.
        NSURL *startupRoot=[temporaryRoot URLByAppendingPathComponent:@"startup" isDirectory:YES];
        [[NSFileManager defaultManager]createDirectoryAtURL:startupRoot withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *seedProfile=@{@"id":@"startup-profile",@"endpointIdentity":@"startup-endpoint",@"name":@"Example"};
        NSMutableArray *legacyTracks=[NSMutableArray new];
        for(NSUInteger n=0;n<25154;n++)[legacyTracks addObject:@{@"id":[NSString stringWithFormat:@"startup-%lu",(unsigned long)n],@"profileID":seedProfile[@"id"],@"endpointIdentity":seedProfile[@"endpointIdentity"],@"extension":@"mp3",@"title":@"File name",@"path":@"music/test.mp3"}];
        NSDictionary *legacy=@{@"profiles":@[seedProfile],@"tracks":legacyTracks,@"playlists":@[],@"cacheLimitBytes":@(256*1024*1024)};
        [[NSJSONSerialization dataWithJSONObject:legacy options:0 error:NULL]writeToURL:[startupRoot URLByAppendingPathComponent:@"library.json"] atomically:YES];
        [[NSJSONSerialization dataWithJSONObject:@[seedProfile] options:0 error:NULL]writeToURL:[startupRoot URLByAppendingPathComponent:@"startup-profiles.json"] atomically:YES];
        NSDictionary *tagOverlay=@{@"startup-25153":@{@"title":@"Cached title",@"artist":@"Cached artist",@"metadataAutoVersion":@15}};
        [[NSJSONSerialization dataWithJSONObject:tagOverlay options:0 error:NULL]writeToURL:[startupRoot URLByAppendingPathComponent:@"decoded-metadata.json"] atomically:YES];
        [[NSJSONSerialization dataWithJSONObject:@{@"startup-25153":@YES} options:0 error:NULL]writeToURL:[startupRoot URLByAppendingPathComponent:@"favorites.json"] atomically:YES];
        NSData *before=[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"library.json"]];
        NSTimeInterval start=[NSDate timeIntervalSinceReferenceDate];
        IPStore *startup=[[IPStore alloc]initWithSupportURL:startupRoot deferred:YES];
        NSTimeInterval bootstrapTime=[NSDate timeIntervalSinceReferenceDate]-start;
        NSCAssert(!startup.libraryLoaded&&startup.tracks.count==0&&startup.profiles.count==1,@"startup read the full model synchronously or lost the profile mirror");
        NSMutableDictionary *bootstrapProfile=startup.profiles[0];
        [startup save];[startup flushPersistence];
        NSCAssert([before isEqual:[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"library.json"]]],@"early background/save destroyed the saved library");
        __block BOOL notified=NO;id observer=[[NSNotificationCenter defaultCenter]addObserverForName:@"IPLibraryLoaded" object:startup queue:nil usingBlock:^(NSNotification *note){NSCAssert([NSThread isMainThread],@"library handoff was off main");notified=YES;}];
        [startup loadLibrary];[startup loadLibrary]; // Repeated calls must coalesce.
        NSCAssert(!startup.libraryLoaded&&startup.tracks.count==0,@"loadLibrary blocked until parsing completed");
        end=[NSDate dateWithTimeIntervalSinceNow:10];while(!startup.libraryLoaded&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        [[NSNotificationCenter defaultCenter]removeObserver:observer];
        NSCAssert(notified&&startup.libraryLoaded&&startup.tracks.count==25154&&startup.profiles[0]==bootstrapProfile,@"deferred handoff lost rows, profile identity or notification");
        NSCAssert(!startup.database,@"the first usable library waited for SQLite import");
        [startup pausePreparation];NSCAssert(![startup.preparationStatus[@"running"]boolValue]&&!startup.database,@"preparation could not be paused before conversion");
        __block BOOL queried=NO;
        [startup queryProfile:nil mode:@"library" playlistIDs:nil sort:@"title" query:nil offset:0 limit:200 completion:^(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records){NSCAssert(total==25154&&records.count==200,@"legacy page is unavailable during preparation");queried=YES;}];IPWaitForFlag(&queried);
        [startup setFavorite:NO forTrack:startup.tracks.lastObject];
        [startup resumePreparation];
        end=[NSDate dateWithTimeIntervalSinceNow:10];while(!startup.database&&[startup.preparationStatus[@"completed"]unsignedIntegerValue]<256&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        if(!startup.database){[startup pausePreparation];[startup resumePreparation];}
        end=[NSDate dateWithTimeIntervalSinceNow:20];while(!startup.database&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert(startup.database.ready&&![startup.tracks.lastObject[@"favorite"]boolValue],@"background preparation did not finish or lost a favorite edited while importing");
        NSCAssert([(IPTrackCollection *)startup.tracks materializedTracks].count<=1,@"SQLite activation eagerly materialized metadata");
        NSCAssert([startup.tracks.lastObject[@"title"]isEqual:@"Cached title"]&&startup.smartCache,@"deferred load lost tags, favorites or audio cache");
        before=[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"library.json"]];
        NSData *tagBackup=[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"decoded-metadata.json"]],*favoriteBackup=[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"favorites.json"]];
        [startup setFavorite:NO forTrack:startup.tracks.lastObject];[startup save];[startup flushPersistence];
        NSCAssert([before isEqual:[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"library.json"]]]&&[tagBackup isEqual:[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"decoded-metadata.json"]]]&&[favoriteBackup isEqual:[NSData dataWithContentsOfURL:[startupRoot URLByAppendingPathComponent:@"favorites.json"]]],@"SQLite writes modified the legacy rollback backups");
        [[NSFileManager defaultManager]removeItemAtURL:[startupRoot URLByAppendingPathComponent:@"startup-profiles.json"] error:NULL];
        IPStore *migration=[[IPStore alloc]initWithSupportURL:startupRoot deferred:YES];
        NSCAssert(!migration.profiles.count&&!migration.libraryLoaded,@"mirrorless migration eagerly parsed the library");[migration loadLibrary];
        end=[NSDate dateWithTimeIntervalSinceNow:10];while(!migration.libraryLoaded&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        [migration flushPersistence];NSCAssert(migration.tracks.count==25154&&migration.profiles.count==2&&![migration.tracks.lastObject[@"favorite"]boolValue],@"first upgrade without profile mirror lost data");
        printf("Deferred startup: 25154 tracks, metadata/favorites, mirror migration, early-save protection passed; profile bootstrap %.3f ms\n",bootstrapTime*1000);
        NSURL *brokenRoot=[temporaryRoot URLByAppendingPathComponent:@"broken-db" isDirectory:YES];[[NSFileManager defaultManager]createDirectoryAtURL:brokenRoot withIntermediateDirectories:YES attributes:nil error:NULL];
        [[@"not a sqlite database" dataUsingEncoding:NSUTF8StringEncoding]writeToURL:[brokenRoot URLByAppendingPathComponent:@"library.sqlite"] atomically:YES];
        NSDictionary *smallLegacy=@{@"profiles":@[seedProfile],@"tracks":@[legacyTracks[0]],@"playlists":@[]};
        [[NSJSONSerialization dataWithJSONObject:smallLegacy options:0 error:NULL]writeToURL:[brokenRoot URLByAppendingPathComponent:@"library.json"] atomically:YES];
        IPStore *fallback=[[IPStore alloc]initWithSupportURL:brokenRoot];NSCAssert(!fallback.database&&fallback.tracks.count==1,@"SQLite failure discarded the legacy library");
        done=NO;[fallback queryProfile:nil mode:@"library" playlistIDs:nil sort:@"title" query:nil offset:0 limit:200 completion:^(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records){NSCAssert(total==1&&records.count==1,@"legacy fallback cannot query songs");done=YES;}];IPWaitForFlag(&done);
        puts("SQLite backup preservation and usable JSON fallback passed");
        NSArray *bulk=@[startup.tracks[0],startup.tracks[1],startup.tracks[0]];
        __block NSUInteger favoriteNotifications=0;
        id favoriteObserver=[[NSNotificationCenter defaultCenter]addObserverForName:@"IPFavoriteChanged" object:startup queue:nil usingBlock:^(NSNotification *n){favoriteNotifications++;}];
        [startup setFavorite:YES forTracks:bulk];[startup flushPersistence];
        IPStore *bulkReload=[[IPStore alloc]initWithSupportURL:startupRoot];
        NSCAssert([bulkReload.tracks[0][@"favorite"]boolValue]&&[bulkReload.tracks[1][@"favorite"]boolValue]&&favoriteNotifications==1,@"bulk favorites did not persist as one update notification");
        [[NSNotificationCenter defaultCenter]removeObserver:favoriteObserver];
        [fallback setFavorite:YES forTracks:@[fallback.tracks[0],fallback.tracks[0]]];[fallback flushPersistence];
        IPStore *fallbackReload=[[IPStore alloc]initWithSupportURL:brokenRoot];
        NSCAssert([fallbackReload.tracks[0][@"favorite"]boolValue],@"bulk favorites did not persist with legacy fallback");
        puts("Bulk favorites: SQLite and JSON persistence, duplicate inputs and one notification passed");
        NSURL *localRoot=[temporaryRoot URLByAppendingPathComponent:@"local-source"];
        LocalTestStore *localStore=[[LocalTestStore alloc]initWithSupportURL:localRoot];
        NSURL *musicRoot=[localRoot URLByAppendingPathComponent:@"TestMusic"];
        [[NSFileManager defaultManager]createDirectoryAtURL:musicRoot withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *songURL=[musicRoot URLByAppendingPathComponent:@"A local song.mp3"];
        [CoverMP3()writeToURL:songURL atomically:YES];localStore.testRoots=@[musicRoot];
        NSMutableDictionary *localProfile=localStore.localProfile;
        NSCAssert([localProfile[@"id"]isEqual:IPLocalProfileID]&&![localStore.profiles containsObject:localProfile],@"fixed local profile leaked into editable server list");
        NSError *lockedError=nil;
        NSCAssert(![localStore deleteProfile:localProfile error:&lockedError]&&lockedError.code==15,@"local source could be deleted");
        NSCAssert(![localStore setEndpoint:@{@"host":@"anything"} forProfileID:IPLocalProfileID error:NULL],@"local source could be edited");
        NSUInteger connectionsBeforeLocal=smbConnections;
        __block BOOL localDone=NO;
        [localStore scanProfile:localProfile progress:nil completion:^(NSError *error){NSCAssert(!error,@"local scan failed");localDone=YES;}];IPWaitForFlag(&localDone);[localStore flushPersistence];
        NSCAssert(localStore.tracks.count==1&&smbConnections==connectionsBeforeLocal,@"local discovery tried SMB or lost files");
        NSMutableDictionary *localTrack=localStore.tracks[0];NSString *localID=localTrack[@"id"];
        NSCAssert([[localStore localURL:localTrack]isEqual:songURL]&&[localStore profileForTrack:localTrack]==localProfile,@"local playback URL/profile resolution failed");
        [localStore setFavorite:YES forTrack:localTrack];[localStore ensureMetadataForProfile:localProfile priorityTracks:@[localTrack]];
        NSDate *localEnd=[NSDate dateWithTimeIntervalSinceNow:5];
        while([localStore metadataPendingCountForProfile:localProfile]&&localEnd.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        [localStore stopAutomaticMetadata];[localStore flushPersistence];
        NSCAssert([localTrack[@"title"]isEqual:@"Title"]&&[localTrack[@"artwork"]length]&&smbConnections==connectionsBeforeLocal,@"local MP3 tags/cover used network or were missing");
        localDone=NO;[localStore scanProfile:localProfile progress:nil completion:^(NSError *e){localDone=YES;}];IPWaitForFlag(&localDone);[localStore flushPersistence];
        NSCAssert([[localStore trackWithID:localID][@"favorite"]boolValue]&&[[localStore trackWithID:localID][@"artwork"]length],@"unchanged local refresh erased favorites or cached art");
        IPStore *localReopen=[[IPStore alloc]initWithSupportURL:localRoot];
        NSCAssert([[localReopen localURL:[localReopen trackWithID:localID]]isEqual:songURL],@"local URL did not survive reopening");
        [[NSFileManager defaultManager]removeItemAtURL:songURL error:NULL];
        localDone=NO;[localStore scanProfile:localProfile progress:nil completion:^(NSError *e){localDone=YES;}];IPWaitForFlag(&localDone);[localStore flushPersistence];
        localDone=NO;[localStore queryProfile:localProfile mode:@"library" playlistIDs:nil sort:@"title" query:nil offset:0 limit:200 completion:^(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records){NSCAssert(total==0,@"deleted local file remained in Local");localDone=YES;}];IPWaitForFlag(&localDone);
        NSCAssert(![localStore localURL:[localStore trackWithID:localID]]&&[[localStore trackWithID:localID][@"favorite"]boolValue],@"missing local file lost its favorite or still had a playback URL");
        NSCAssert(smbConnections==connectionsBeforeLocal,@"Local used a network connection");
        puts("Local Store: immutable source, read-only discovery, offline MP3 tags/art, unchanged refresh, favorite/URL persistence, disappearance and no SMB passed");
        puts("IPStore host checks passed");
        [[NSFileManager defaultManager] removeItemAtURL:temporaryRoot error:NULL];
    }
    return 0;
}

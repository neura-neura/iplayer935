#import "IPStrings.h"
#import "IPDiagnostics.h"
#import "IPStore.h"
#import "IPLibraryDB.h"
#import "IPCodecCheck.h"
#import "IPPlayer.h"
#import "IPSmartCache.h"
#import <UIKit/UIKit.h>
@implementation IPDiagnostics
+ (void)write {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self write];
        });
        return;
    }
    IPStore *s = [IPStore shared];
#if defined(IP_IOS6)
    if(s.legacyLibraryWritePending){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self write];});return;}
#endif
    NSMutableDictionary *extensions = [NSMutableDictionary new];
    NSUInteger offline = 0, unsupported = 0, pending = 0;
    if(!s.database)for (NSDictionary *t in s.tracks) {
        NSString *ext = t[@"extension"] ?: @"unknown";
        extensions[ext] = @([extensions[ext] unsignedIntegerValue] + 1);
        if ([t[@"downloaded"] boolValue])
            offline++;
        if (t[@"unsupportedReason"])
            unsupported++;
        if ([t[@"metadataPending"] boolValue])
            pending++;
    }
    if(s.database){NSDictionary *counts=[s.database diagnosticCounts];extensions=[counts[@"extensions"]mutableCopy];offline=[counts[@"offline"]unsignedIntegerValue];unsupported=[counts[@"unsupported"]unsignedIntegerValue];pending=[counts[@"pending"]unsignedIntegerValue];}
    NSMutableArray *pathSamples = [NSMutableArray new];
    for (NSDictionary *track in s.tracks) {
        if (pathSamples.count >= 8)
            break;
        if (track[@"path"])
            [pathSamples addObject:track[@"path"]];
    }
    NSMutableArray *lists = [NSMutableArray new];
    for (NSDictionary *p in s.playlists)
        [lists addObject:@{
            @"count" : @([p[@"trackIDs"] count]),
            @"imported" : @(p[@"sourceName"] != nil),
            @"unresolved" : p[@"skippedEntries"] ?: @0,
            @"unresolvedPaths" : p[@"unresolvedSamples"] ?: p[@"referenceSamples"] ?: @[]
        }];
    NSDictionary *playing=[IPPlayer shared].track?:@{};
    NSDictionary *report = @{
        @"application" : @"org.neura.iplayer935",
        @"version" : [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
            ?: @"unknown",
        @"observedAt" : @([[NSDate date] timeIntervalSince1970]),
        @"systemVersion" : [UIDevice currentDevice].systemVersion,
        @"interfaceLanguage" : IPInterfaceLanguage(),
        @"languagePreference" : IPLanguagePreference(),
        @"preferredLanguages" : [NSLocale preferredLanguages],
        @"profiles" : @(s.profiles.count),
        @"tracks" : @(s.tracks.count),
        @"offlineTracks" : @(offline),
        @"unsupportedTracks" : @(unsupported),
        @"metadataPending" : @(pending),
        @"tagCache" : s.profiles.count?[s metadataCacheStatusForProfile:s.profiles.firstObject]:@{},
        @"extensions" : extensions,
        @"playlists" : lists,
        @"sampleTrackPaths" : pathSamples,
        @"cacheBytes" : @(s.cacheBytes),
        @"smartCache" : s.smartCache.status?:@{},
        @"queueCount" : @([IPPlayer shared].queue.count),
        @"queueIndex" : @([IPPlayer shared].index),
        @"codecChecks" : [IPCodecCheck results],
        @"currentTrackTags" : @{@"title":playing[@"title"]?:@"",@"artist":playing[@"artist"]?:@"",@"metadataAutoVersion":playing[@"metadataAutoVersion"]?:@0,@"artworkAutoVersion":playing[@"artworkAutoVersion"]?:@0,@"artworkStored":@([s artworkURLForTrack:playing]!=nil)},
        @"playback" : [IPPlayer shared].playbackDiagnostic ?: @{}
    };
    NSURL *url = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                         inDomains:NSUserDomainMask]
                      .firstObject URLByAppendingPathComponent:@"diagnostics.json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    [data writeToURL:url options:NSDataWritingAtomic error:NULL];
}
@end

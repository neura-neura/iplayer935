#import "IPLocalLibrary.h"
#import "IPStrings.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#import <stdlib.h>
#if TARGET_OS_IPHONE
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
#endif
NSString *const IPLocalProfileID = @"local-library-v1";
BOOL IPIsLocalProfile(NSDictionary *profile) { return [profile[@"id"] isEqual:IPLocalProfileID]; }
NSString *IPProfileName(NSDictionary *profile) { return IPIsLocalProfile(profile) ? IPL(@"Local") : profile[@"name"]; }

static NSString *LocalID(NSString *source) {
    NSData *data=[source dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,hash);NSMutableString *s=[NSMutableString stringWithString:@"local-"];
    for(NSUInteger i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]];return s;
}
static NSMutableDictionary *BaseTrack(NSString *source,NSString *title,NSString *ext) {
    return [@{@"id":LocalID(source),@"profileID":IPLocalProfileID,@"endpointIdentity":IPLocalProfileID,
        @"sourceName":@"Local",@"sourceHost":@"",@"title":title?:@"",@"artist":@"",@"album":@"",@"genre":@"",
        @"extension":ext?:@"",@"duration":@0,@"trackNumber":@0,@"size":@0,@"favorite":@NO,
        @"modifiedAt":@0,@"addedAt":@([NSDate date].timeIntervalSince1970),@"metadataPending":@YES}mutableCopy];
}
@implementation IPLocalLibrary
+ (NSArray *)fileRoots {
    NSMutableArray *roots=[NSMutableArray new];
    NSURL *documents=[[NSFileManager defaultManager]URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if(documents)[roots addObject:documents];
#if TARGET_OS_IPHONE
    [roots addObject:[NSURL fileURLWithPath:@"/var/mobile/Media" isDirectory:YES]];
#endif
    return roots;
}
+ (NSDictionary *)scanRoots:(NSArray *)roots includeMediaLibrary:(BOOL)includeMedia {
    NSFileManager *fm=[NSFileManager defaultManager];NSMutableArray *tracks=[NSMutableArray new],*failed=[NSMutableArray new];
    NSMutableSet *seen=[NSMutableSet new];BOOL hasMediaItems=NO;
#if TARGET_OS_IPHONE
    if(includeMedia){
        NSArray *items=[MPMediaQuery songsQuery].items;hasMediaItems=items.count>0;
        for(MPMediaItem *item in items){@autoreleasepool{
            NSString *pid=[NSString stringWithFormat:@"%llu",[[item valueForProperty:MPMediaItemPropertyPersistentID]unsignedLongLongValue]];
            NSURL *url=[item valueForProperty:MPMediaItemPropertyAssetURL];
            NSString *ext=url.pathExtension.lowercaseString;if(!ext.length)ext=@"m4a";
            NSMutableDictionary *t=BaseTrack([@"media:" stringByAppendingString:pid],[item valueForProperty:MPMediaItemPropertyTitle],ext);
            t[@"mediaPersistentID"]=pid;t[@"path"]=[@"iTunes/" stringByAppendingString:pid];
            for(NSArray *pair in @[@[@"artist",MPMediaItemPropertyArtist],@[@"album",MPMediaItemPropertyAlbumTitle],@[@"genre",MPMediaItemPropertyGenre],@[@"duration",MPMediaItemPropertyPlaybackDuration],@[@"trackNumber",MPMediaItemPropertyAlbumTrackNumber]]){
                id value=[item valueForProperty:pair[1]];if(value)t[pair[0]]=value;
            }
            t[@"localRevision"]=[NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",t[@"title"],t[@"artist"],t[@"album"],t[@"genre"],t[@"duration"],t[@"trackNumber"]];
            if(url){t[@"localURL"]=url.absoluteString;if(url.isFileURL)[seen addObject:url.path.stringByResolvingSymlinksInPath];}
            else {t[@"unsupportedReason"]=@"This iTunes item is protected or has no playable local file.";t[@"metadataPending"]=@NO;}
            [tracks addObject:t];
        }}
    }
#endif
    NSSet *extensions=[NSSet setWithArray:@[@"mp3",@"m4a",@"aac",@"wav",@"wave",@"aif",@"aiff",@"caf",@"m4b",@"flac",@"ogg",@"oga",@"opus",@"alac"]];
    NSArray *keys=@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey,NSURLContentModificationDateKey];
    for(NSURL *root in roots){@autoreleasepool{
        NSError *rootError=nil;NSDictionary *attributes=[fm attributesOfItemAtPath:root.path error:&rootError];
        if(!attributes){if(rootError.code!=NSFileReadNoSuchFileError&&rootError.code!=NSFileNoSuchFileError)[failed addObject:root.path.stringByResolvingSymlinksInPath];continue;}
        if(![attributes[NSFileType]isEqual:NSFileTypeDirectory])continue;
        NSDirectoryEnumerator *enumerator=[fm enumeratorAtURL:root includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:^BOOL(NSURL *url,NSError *error){[failed addObject:url.path.stringByResolvingSymlinksInPath];return YES;}];
        for(NSURL *url in enumerator){@autoreleasepool{
            NSDictionary *v=[url resourceValuesForKeys:keys error:NULL];
            if([v[NSURLIsSymbolicLinkKey]boolValue]){[enumerator skipDescendants];continue;}
            if([v[NSURLIsDirectoryKey]boolValue]){
                if([@[@"DCIM",@"PhotoData",@"Photos",@"PhotoStreamsData"]containsObject:url.lastPathComponent] || (hasMediaItems&&[url.lastPathComponent isEqual:@"iTunes_Control"]))[enumerator skipDescendants];
                continue;
            }
            NSString *ext=url.pathExtension.lowercaseString;if(![extensions containsObject:ext])continue;
            NSString *path=url.path.stringByResolvingSymlinksInPath;if([seen containsObject:path])continue;[seen addObject:path];
            if(![fm isReadableFileAtPath:path]){[failed addObject:path];continue;}
            NSMutableDictionary *t=BaseTrack([@"file:" stringByAppendingString:path],url.lastPathComponent.stringByDeletingPathExtension,ext);
            t[@"path"]=path;t[@"localURL"]=[NSURL fileURLWithPath:path].absoluteString;
            t[@"size"]=v[NSURLFileSizeKey]?:@0;NSDate *date=v[NSURLContentModificationDateKey];t[@"modifiedAt"]=@(date.timeIntervalSince1970);
            [tracks addObject:t];
        }}
    }}
    return @{@"tracks":tracks,@"failedRoots":failed};
}
+ (NSDictionary *)metadataForMediaID:(NSString *)persistentID {
#if TARGET_OS_IPHONE
    MPMediaQuery *query=[MPMediaQuery new];[query addFilterPredicate:[MPMediaPropertyPredicate predicateWithValue:@(strtoull(persistentID.UTF8String,NULL,10)) forProperty:MPMediaItemPropertyPersistentID]];
    MPMediaItem *item=query.items.firstObject;if(!item)return nil;
    NSMutableDictionary *tags=[NSMutableDictionary new];
    for(NSArray *pair in @[@[@"title",MPMediaItemPropertyTitle],@[@"artist",MPMediaItemPropertyArtist],@[@"album",MPMediaItemPropertyAlbumTitle],@[@"genre",MPMediaItemPropertyGenre],@[@"duration",MPMediaItemPropertyPlaybackDuration],@[@"trackNumber",MPMediaItemPropertyAlbumTrackNumber]]){id v=[item valueForProperty:pair[1]];if(v)tags[pair[0]]=v;}
    MPMediaItemArtwork *art=[item valueForProperty:MPMediaItemPropertyArtwork];UIImage *image=[art imageWithSize:CGSizeMake(320,320)];
    if(image){NSData *data=UIImageJPEGRepresentation(image,.8);if(data)tags[@"artworkData"]=data;}
    return tags;
#else
    return nil;
#endif
}
@end

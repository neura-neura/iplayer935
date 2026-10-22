#import <Foundation/Foundation.h>
#import "IPLocalLibrary.h"
int main(){@autoreleasepool{
    NSFileManager *fm=[NSFileManager defaultManager];NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    for(NSString *folder in @[@"Albums",@"DCIM",@".hidden"])[fm createDirectoryAtURL:[root URLByAppendingPathComponent:folder] withIntermediateDirectories:YES attributes:nil error:NULL];
    for(NSString *name in @[@"Albums/中文.mp3",@"Albums/test.FLAC",@"Albums/audio.aif",@"Albums/image.jpg",@"DCIM/video.mp3",@".hidden/song.mp3",@"unfinished.mp3.part"])[[@"fixture" dataUsingEncoding:NSUTF8StringEncoding]writeToURL:[root URLByAppendingPathComponent:name] atomically:YES];
    [fm createSymbolicLinkAtPath:[[root URLByAppendingPathComponent:@"Albums/loop"]path] withDestinationPath:root.path error:NULL];
    NSArray *roots=@[root,[root URLByAppendingPathComponent:@"Albums"]];
    NSDictionary *scan=[IPLocalLibrary scanRoots:roots includeMediaLibrary:NO];NSArray *tracks=scan[@"tracks"];
    NSCAssert(tracks.count==3&&![scan[@"failedRoots"]count],@"scanner included non-audio, hidden, photos, symlinks or duplicate overlapping roots");
    NSSet *ids=[NSSet setWithArray:[tracks valueForKey:@"id"]];
    NSCAssert(ids.count==3,@"duplicate local identity");
    for(NSDictionary *t in tracks){NSCAssert([t[@"profileID"]isEqual:IPLocalProfileID]&&[t[@"endpointIdentity"]isEqual:IPLocalProfileID]&&[NSURL URLWithString:t[@"localURL"]].isFileURL,@"invalid local record");}
    NSCAssert([ids isEqual:[NSSet setWithArray:[[IPLocalLibrary scanRoots:roots includeMediaLibrary:NO][@"tracks"]valueForKey:@"id"]]],@"local IDs changed on refresh");
    [fm removeItemAtURL:[root URLByAppendingPathComponent:@"Albums/test.FLAC"] error:NULL];
    NSCAssert([[IPLocalLibrary scanRoots:roots includeMediaLibrary:NO][@"tracks"]count]==2,@"removed file was not detected");
    [fm removeItemAtURL:root error:NULL];puts("Local scanner: nested/Unicode files, overlapping roots, stable IDs, deletion, hidden/photo/partial-file and symlink exclusions passed");
}return 0;}

#import <Foundation/Foundation.h>

extern NSString *const IPLocalProfileID;
BOOL IPIsLocalProfile(NSDictionary *profile);
NSString *IPProfileName(NSDictionary *profile);

/** Read-only discovery. Never imports, moves or deletes the user's audio. */
@interface IPLocalLibrary : NSObject
+ (NSArray<NSURL *> *)fileRoots;
/** Runs off main; roots are injectable for host tests. Returns tracks and failedRoots. */
+ (NSDictionary *)scanRoots:(NSArray<NSURL *> *)roots includeMediaLibrary:(BOOL)includeMedia;
+ (NSDictionary *)metadataForMediaID:(NSString *)persistentID;
@end

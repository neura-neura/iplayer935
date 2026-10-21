#import <Foundation/Foundation.h>
/** Main-thread model access, serial background filtering/sorting, bounded result cache. */
@interface IPLibraryIndex : NSObject
- (void)replaceTracks:(NSArray *)tracks;
- (void)updateTracks:(NSArray *)tracks;
- (void)rowsForProfile:(NSDictionary *)profile mode:(NSString *)mode playlistIDs:(NSArray *)playlistIDs sort:(NSString *)sort query:(NSString *)query completion:(void (^)(NSArray *rows, NSUInteger pending))completion;
@end

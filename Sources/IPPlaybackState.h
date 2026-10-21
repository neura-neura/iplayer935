#import <Foundation/Foundation.h>
/** IDs and playhead are separate atomic files: the large queue is written only when changed. */
@interface IPPlaybackState : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSDictionary *)restoreWithTracks:(NSArray *)tracks;
- (void)saveQueue:(NSArray *)tracks index:(NSInteger)index elapsed:(double)elapsed duration:(double)duration;
- (void)savePosition:(NSInteger)index elapsed:(double)elapsed duration:(double)duration;
- (void)flush;
@end

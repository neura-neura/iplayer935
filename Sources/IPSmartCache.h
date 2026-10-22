#import <Foundation/Foundation.h>
@interface IPSmartCache : NSObject
@property(atomic) BOOL enabled;
@property(atomic) unsigned long long limitBytes;
@property(atomic,copy,readonly) NSDictionary *status;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSURL *)localURLForTrack:(NSDictionary *)track;
/** Call on main; copies at most four tracks. Explicit downloads are not managed here. */
- (void)prefetchQueue:(NSArray *)queue index:(NSInteger)index profiles:(NSArray *)profiles password:(NSString *(^)(NSDictionary *profile))password;
- (void)protectTrack:(NSDictionary *)track;
- (void)cancel;
- (void)clear;
- (void)flush;
@end

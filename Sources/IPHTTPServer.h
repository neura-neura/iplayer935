#import <Foundation/Foundation.h>

/** Loopback HTTP byte-range bridge for AVPlayer. */
@interface IPHTTPServer : NSObject
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size;
- (NSURL *)start:(NSError **)error;
- (void)stop;
@end

#import <Foundation/Foundation.h>

/** Synchronous, read-only SMB2/3 client. Call methods from a background queue. */
@interface IPSMB : NSObject
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password;
- (BOOL)connect:(NSError **)error;
/** Lists a directory relative to profile root. Returned paths are relative to the share and include profile root. */
- (NSArray *)list:(NSString *)shareRelativePath error:(NSError **)error;
/** Reads up to length bytes at offset. A short result indicates end of file. */
- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error;
- (uint64_t)size:(NSString *)path error:(NSError **)error;
- (void)disconnect;
@end

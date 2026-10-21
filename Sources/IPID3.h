#import <Foundation/Foundation.h>
/** Bounded ID3v2.2/2.3/2.4 and ID3v1 text parsing; no network or audio decoding. */
@interface IPID3 : NSObject
+ (NSUInteger)tagLength:(NSData *)header;
+ (NSDictionary *)metadataFromData:(NSData *)data;
+ (NSDictionary *)legacyMetadata:(NSData *)data;
+ (NSDictionary *)readMetadataWithReader:(NSData *(^)(uint64_t offset,NSUInteger length))reader fileSize:(uint64_t)fileSize error:(NSError **)error;
@end

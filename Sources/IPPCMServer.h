#import <Foundation/Foundation.h>

/** Streams decoded FLAC, Vorbis, or Opus as seekable 16-bit PCM WAV over loopback HTTP. */
@interface IPPCMServer : NSObject
@property(nonatomic, copy, readonly) NSDictionary *metadata;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size;
- (NSURL *)start:(NSError **)error;
- (BOOL)preparePCM:(NSError **)error;
- (NSData *)readPCMFrames:(uint32_t)frames error:(NSError **)error;
- (BOOL)seekPCMFrame:(int64_t)frame error:(NSError **)error;
- (void)closePCM;
- (void)stop;
/** Sanitized decoder and recent HTTP request state. Contains no source URL or credentials. */
- (NSDictionary *)diagnosticSnapshot;
@end

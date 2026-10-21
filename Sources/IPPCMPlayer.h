#import <Foundation/Foundation.h>

typedef void (^IPPCMPlayerStartCompletion)(NSError *error);
typedef void (^IPPCMPlayerErrorHandler)(NSError *error);

/** Plays FLAC, Vorbis, and Opus through bounded PCM16 AudioQueue buffers. */
@interface IPPCMPlayer : NSObject
@property(nonatomic, copy) dispatch_block_t ended;
@property(nonatomic, copy) IPPCMPlayerErrorHandler error;
/** Applied before any output buffers are filled. Set before start. */
@property(nonatomic) NSTimeInterval initialTime;
/** Independent deck gain, applied through AudioQueue, never by rewriting PCM samples. */
@property(nonatomic) float volume;
@property(nonatomic, readonly) NSTimeInterval duration;
@property(nonatomic, readonly) NSTimeInterval currentTime;
@property(nonatomic, readonly, getter=isPlaying) BOOL playing;
@property(nonatomic, readonly, getter=isSeeking) BOOL seeking;
@property(nonatomic, copy, readonly) NSDictionary *metadata;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size;
- (void)startWithCompletion:(IPPCMPlayerStartCompletion)completion;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekFraction:(double)fraction;
- (NSDictionary *)diagnosticSnapshot;
@end

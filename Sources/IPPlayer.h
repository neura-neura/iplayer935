#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
@class IPCrossfade;
@interface IPPlayer : NSObject
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) NSDictionary *track;
@property(nonatomic, strong) NSArray *queue;
@property(nonatomic) NSInteger index;
@property(nonatomic, copy) void (^changed)(NSString *error);
@property(nonatomic, copy, readonly) NSDictionary *playbackDiagnostic;
@property(nonatomic, readonly) double duration, elapsed;
@property(nonatomic,readonly,getter=isSeeking) BOOL seeking;
@property(nonatomic, readonly, getter=isPlaying) BOOL playing;
+ (instancetype)shared;
- (void)playTracks:(NSArray *)tracks index:(NSInteger)index;
- (void)restoreSession;
- (void)saveSession;
- (void)flushSession;
@property(nonatomic,readonly) BOOL shuffleEnabled;
- (void)toggleShuffle;
@property(nonatomic,strong,readonly) IPCrossfade *crossfade;
- (void)crossfadeSettingsChanged;
- (void)toggleCrossfadeSession;
- (void)toggle;
- (void)next;
- (void)previous;
- (void)seek:(float)fraction;
@end

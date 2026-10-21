#import "IPStrings.h"
#import "IPPlayer.h"
#import "IPHTTPServer.h"
#import "IPSMB.h"
#import "IPStore.h"
#import "IPPCMPlayer.h"
#import "IPDiagnostics.h"
#import "IPPlaybackState.h"
#import "IPShuffleQueue.h"
#import "IPSmartCache.h"
#import "IPLocalAudioFile.h"
#import "IPCrossfade.h"
#import <MediaPlayer/MediaPlayer.h>
// Owns only the outgoing audio resources until the overlap ends or opening fails.
@interface IPAudioTail : NSObject
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) IPPCMPlayer *pcm;
@property(nonatomic,strong) IPHTTPServer *server;
@property(nonatomic,strong) IPLocalAudioFile *link;
@property(nonatomic,strong) NSArray *queue;
@property(nonatomic,strong) NSDictionary *track;
@property(nonatomic) NSInteger index;
@property(nonatomic) BOOL usingLocal;
@end
@implementation IPAudioTail
@end
@interface IPPlayer ()
@property(nonatomic,strong) IPPlaybackState *session;
@property(nonatomic,strong,readwrite) IPCrossfade *crossfade;
@property(nonatomic,strong) IPAudioTail *tail;
@property(nonatomic,strong) NSURL *playbackLinksRoot;
@property(nonatomic,strong) NSTimer *fadeTimer, *advanceTimer;
@property(nonatomic) BOOL preserveTail, fadeStarted;
@property(nonatomic) double tailOpenedAt, fadeMediaStart, fadeDuration, fadeProgress, lastFadeMovement;
@property(nonatomic,copy) NSString *autoAttemptID;
@property(nonatomic,readwrite) BOOL shuffleEnabled;
@property(nonatomic,strong) IPLocalAudioFile *localAudio;
@property(nonatomic) BOOL awaitingResume,opening,wantsPlayback,usingLocal;
@property(nonatomic) double resumeSeconds,restoredDuration,lastSessionSave,lastGoodElapsed;
@property(nonatomic, strong) IPHTTPServer *server;
@property(nonatomic, strong) IPPCMPlayer *pcmPlayer;
@property(nonatomic, strong) NSTimer *pcmTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) id observer;
@property(nonatomic, copy) NSString *publishedArtworkKey;
@property(nonatomic, strong) MPMediaItemArtwork *publishedArtwork;
@property(nonatomic, copy, readwrite) NSDictionary *playbackDiagnostic;
@end
@implementation IPPlayer
+ (instancetype)shared {
    static IPPlayer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [self new];
    });
    return p;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSURL *base=[[[NSFileManager defaultManager]URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"IPStore"];
        self.session=[[IPPlaybackState alloc]initWithDirectory:base];
        self.crossfade=[[IPCrossfade alloc]initWithDefaults:[NSUserDefaults standardUserDefaults]];
        self.shuffleEnabled=[[NSUserDefaults standardUserDefaults]boolForKey:@"shuffleEnabled"];
        self.playbackLinksRoot=[base URLByAppendingPathComponent:@"PlaybackLinks"];
        self.localAudio=[[IPLocalAudioFile alloc]initWithDirectory:self.playbackLinksRoot];
        self.player = [AVPlayer new];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(metadataChanged:) name:@"IPTrackMetadataChanged" object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(libraryChanged:) name:@"IPStoreChanged" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ended:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(interrupted:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(routeChanged:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:nil];
        MPRemoteCommandCenter *r = [MPRemoteCommandCenter sharedCommandCenter];
        [r.playCommand addTarget:self action:@selector(remotePlay:)];
        [r.pauseCommand addTarget:self action:@selector(remotePause:)];
        [r.nextTrackCommand addTarget:self action:@selector(remoteNext:)];
        [r.previousTrackCommand addTarget:self action:@selector(remotePrevious:)];
        self.pcmTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tickPCM) userInfo:nil repeats:YES];
        [self attachTimeObserver];
        [self crossfadeSettingsChanged];
    }
    return self;
}
- (void)ended:(NSNotification *)n {
    if (n.object == self.player.currentItem)
        [self advanceAutomatically];
}
- (void)metadataChanged:(NSNotification *)notification {
    for(NSDictionary *track in notification.userInfo[@"tracks"])if([track[@"id"] isEqual:self.track[@"id"]]){self.track=track;[self publish];if(self.changed)self.changed(nil);break;}
}
- (void)libraryChanged:(NSNotification *)notification {
    if(!self.track)return;
    NSDictionary *track=[[IPStore shared]trackWithID:self.track[@"id"]];if(track){self.track=track;[self publish];}
}
- (void)interrupted:(NSNotification *)n {
    if ([n.userInfo[AVAudioSessionInterruptionTypeKey] integerValue] ==
        AVAudioSessionInterruptionTypeBegan)
        [self pause];
}
- (void)routeChanged:(NSNotification *)n {
    if ([n.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue] ==
        AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
        [self pause];
}
- (MPRemoteCommandHandlerStatus)remotePlay:(id)e {
    [self play];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remotePause:(id)e {
    [self pause];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remoteNext:(id)e {
    [self next];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remotePrevious:(id)e {
    [self previous];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (void)publish {
    [self updateAdvanceTimer];
    double position=self.elapsed;if(!self.opening&&!self.awaitingResume&&isfinite(position)&&position>=0)self.lastGoodElapsed=position;
    [IPStore shared].playbackActive=self.playing;
    if(self.track&&self.playing&&[NSDate date].timeIntervalSince1970-self.lastSessionSave>=5)[self saveSession];
    if (!self.track)
        return;
    double d = self.duration, t = self.elapsed;
    NSMutableDictionary *m = [@{
        MPMediaItemPropertyTitle : self.track[@"title"] ?: @"",
        MPMediaItemPropertyArtist : self.track[@"artist"] ?: @"",
        MPMediaItemPropertyAlbumTitle : self.track[@"album"] ?: @"",
        MPNowPlayingInfoPropertyPlaybackRate : @(self.playing ? 1 : 0),
        MPNowPlayingInfoPropertyElapsedPlaybackTime : @(isfinite(t) ? t : 0)
    } mutableCopy];
    if (isfinite(d))
        m[MPMediaItemPropertyPlaybackDuration] = @(d);
    NSString *artKey = [NSString stringWithFormat:@"%@/%@", self.track[@"id"], self.track[@"artwork"]];
    if (![artKey isEqual:self.publishedArtworkKey]) {
        self.publishedArtworkKey = artKey;
        NSURL *artURL = [[IPStore shared] artworkURLForTrack:self.track];
        UIImage *art = artURL ? [UIImage imageWithContentsOfFile:artURL.path] : nil;
        self.publishedArtwork = art ? [[MPMediaItemArtwork alloc] initWithImage:art] : nil;
    }
    if (self.publishedArtwork) m[MPMediaItemPropertyArtwork] = self.publishedArtwork;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = m;
    [[NSNotificationCenter defaultCenter]postNotificationName:@"IPPlaybackChanged" object:self];
}
- (void)restoreSession {
    if(self.track)return;NSDictionary *restored=[self.session restoreWithTracks:[IPStore shared].tracks];if(!restored)return;
    self.queue=restored[@"queue"];self.shuffleEnabled=[self.queue isKindOfClass:[IPShuffleQueue class]];[[NSUserDefaults standardUserDefaults]setBool:self.shuffleEnabled forKey:@"shuffleEnabled"];self.index=[restored[@"index"]integerValue];self.track=self.queue[self.index];self.resumeSeconds=[restored[@"elapsed"]doubleValue];self.restoredDuration=[restored[@"duration"]doubleValue];self.awaitingResume=YES;
    [[IPStore shared].smartCache protectTrack:self.track];[self publish];
}
- (void)saveSession {
    if(!self.track)return;self.lastSessionSave=[NSDate date].timeIntervalSince1970;[self.session savePosition:self.index elapsed:self.elapsed duration:self.duration];
}
- (void)flushSession {[self saveSession];[self.session flush];}
- (void)toggleShuffle {
    [self finishTransition];
    self.shuffleEnabled=!self.shuffleEnabled;
    [[NSUserDefaults standardUserDefaults]setBool:self.shuffleEnabled forKey:@"shuffleEnabled"];
    if(self.queue.count){
        if(self.shuffleEnabled){self.queue=[[IPShuffleQueue alloc]initWithQueue:self.queue currentIndex:self.index];self.index=0;}
        else if([self.queue isKindOfClass:[IPShuffleQueue class]]){IPShuffleQueue *shuffled=(id)self.queue;self.index=[shuffled originalIndexAtIndex:self.index];self.queue=shuffled.originalQueue;}
        [self.session saveQueue:self.queue index:self.index elapsed:self.elapsed duration:self.duration];
        [[IPStore shared].smartCache cancel];
        [[IPStore shared]preparePlaybackCacheForQueue:self.queue index:self.index];
    }
    [self publish];
}
- (void)playTracks:(NSArray *)tracks index:(NSInteger)i {
    if(i<0||i>=(NSInteger)tracks.count)return;
    if(tracks!=self.queue&&self.shuffleEnabled){tracks=[[IPShuffleQueue alloc]initWithQueue:tracks currentIndex:i];i=0;}
    [self transitionToTracks:tracks index:i automatic:NO];
}
- (void)beginTracks:(NSArray *)tracks index:(NSInteger)i resume:(double)seconds {
    if(i<0||i>=(NSInteger)tracks.count)return;
    if(!self.preserveTail)[self finishTransition];self.preserveTail=NO;
    BOOL newQueue=tracks!=self.queue;
    self.autoAttemptID=nil;
    if(newQueue)self.queue=[tracks copy];self.index=i;self.track=self.queue[i];
    self.awaitingResume=NO;self.opening=YES;self.wantsPlayback=YES;self.resumeSeconds=MAX(0,seconds);self.lastGoodElapsed=self.resumeSeconds;self.restoredDuration=[self.track[@"duration"]doubleValue];
    if(newQueue)[self.session saveQueue:self.queue index:i elapsed:self.resumeSeconds duration:self.restoredDuration];else [self saveSession];
    [[IPStore shared].smartCache cancel];[[IPStore shared].smartCache protectTrack:self.track];
    [IPStore shared].playbackActive=YES;
    [[NSNotificationCenter defaultCenter]postNotificationName:@"IPPlaybackChanged" object:self];
    self.playbackDiagnostic = @{@"extension":self.track[@"extension"] ?: @"", @"state":@"opening"};
    [[IPStore shared] cancelMetadata];
    NSUInteger token = ++self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(token==self.generation&&self.wantsPlayback)[[IPStore shared]preparePlaybackCacheForQueue:self.queue index:self.index];});
    [self.player pause];
    AVPlayerItem *previousItem = self.player.currentItem;
    if (previousItem) [previousItem removeObserver:self forKeyPath:@"status"];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    [self.localAudio close];
    [self.pcmPlayer stop];
    self.pcmPlayer = nil;
    [self.server stop];
    self.server = nil;
    IPStore *store = [IPStore shared];
    NSURL *local = [store localURL:self.track];
    self.usingLocal=local!=nil;
    if (local) {
        [self prepareURL:local token:token];
        return;
    }
    NSDictionary *profile = [store profileForTrack:self.track];
    if (!profile || [self.track[@"unavailableRemote"] boolValue]) {
        if([self restoreOutgoing])return;
        if (self.changed)
            self.changed(IPL(@"El perfil de origen ya no está disponible. Usa una copia descargada."));
        return;
    }
    NSDictionary *track = self.track;
    NSString *ext = [track[@"extension"] lowercaseString];
    if ([@[@"flac", @"ogg", @"oga", @"opus"] containsObject:ext]) {
        IPPCMPlayer *pcm = [[IPPCMPlayer alloc] initWithProfile:profile
                                                    password:[store passwordForProfile:profile error:NULL] ?: @""
                                                        path:track[@"path"]
                                                        size:[track[@"size"] unsignedLongLongValue]];
        [self startPCM:pcm token:token];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        IPHTTPServer *s =
            [[IPHTTPServer alloc] initWithProfile:profile
                                         password:[store passwordForProfile:profile error:NULL]
                                             path:track[@"path"]
                                             size:[track[@"size"] unsignedLongLongValue]];
        NSURL *url = [s start:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self.generation) {
                [s stop];
                return;
            }
            if (!url) {
                if([self restoreOutgoing])return;
                if (self.changed)
                    self.changed(IPL(@"No se pudo acceder al servidor. Revisa conexión y credenciales; "
                                 @"esta canción no está descargada."));
                return;
            }
            self.server = s;
            [self prepareURL:url token:token];
        });
    });
}
- (void)prepareURL:(NSURL *)url token:(NSUInteger)token {
    NSString *ext = [self.track[@"extension"] lowercaseString];
    if (![@[@"flac", @"ogg", @"oga", @"opus"] containsObject:ext]) {
        if(url.isFileURL){NSError *error=nil;url=[self.localAudio openFile:url extension:ext error:&error];if(!url){if([self restoreOutgoing])return;self.awaitingResume=YES;self.opening=NO;if(self.changed)self.changed(error.localizedDescription);return;}}
        [self startURL:url token:token];
        return;
    }
    IPPCMPlayer *pcm = [[IPPCMPlayer alloc] initWithURL:url];
    [self startPCM:pcm token:token];
}
- (void)wirePCM:(IPPCMPlayer *)pcm token:(NSUInteger)token {
    __weak IPPlayer *weakSelf = self;
    __weak IPPCMPlayer *weakPCM = pcm;
    pcm.ended = ^{
        IPPlayer *strongSelf = weakSelf;
        if (token == strongSelf.generation) [strongSelf advanceAutomatically];
    };
    pcm.error = ^(NSError *error) {
        IPPlayer *strongSelf = weakSelf;
        if (token != strongSelf.generation) return;
        if([strongSelf restoreOutgoing])return;
        if([strongSelf recoverFromCache])return;
        strongSelf.playbackDiagnostic = @{@"extension":strongSelf.track[@"extension"] ?: @"", @"state":@"failed",
            @"domain":error.domain ?: @"", @"code":@(error.code), @"pcm":[weakPCM diagnosticSnapshot] ?: @{}};
        [IPDiagnostics write];
        if (strongSelf.changed) strongSelf.changed(error.localizedDescription);
    };
}
- (void)startPCM:(IPPCMPlayer *)pcm token:(NSUInteger)token {
    pcm.initialTime=self.resumeSeconds;pcm.volume=self.tail?0:1;
    self.pcmPlayer = pcm;
    NSError *sessionError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
    [[AVAudioSession sharedInstance] setActive:YES error:&sessionError];
    if (sessionError) { if([self restoreOutgoing])return; if (self.changed) self.changed(sessionError.localizedDescription); return; }
    [self wirePCM:pcm token:token];
    __weak IPPlayer *weakSelf=self;
    __weak IPPCMPlayer *weakPCM=pcm;
    [pcm startWithCompletion:^(NSError *error) {
        IPPlayer *strongSelf = weakSelf;
        if (token != strongSelf.generation) { [pcm stop]; return; }
        if(error&&[strongSelf restoreOutgoing])return;
        strongSelf.opening=NO;if(error){strongSelf.awaitingResume=YES;[pcm stop];strongSelf.pcmPlayer=nil;}else{strongSelf.resumeSeconds=0;if(!strongSelf.wantsPlayback)[pcm pause];}
        strongSelf.playbackDiagnostic = @{@"extension":strongSelf.track[@"extension"] ?: @"", @"state":error ? @"failed" : @"ready",
            @"domain":error.domain ?: @"", @"code":@(error.code), @"pcm":[weakPCM diagnosticSnapshot] ?: @{}};
        [IPDiagnostics write];
        if (strongSelf.changed) strongSelf.changed(error ? error.localizedDescription : nil);
        if(!error)[strongSelf startTransitionIfReady];
        [strongSelf publish];
        if (!error) {
            NSDictionary *selectedTrack = strongSelf.track;
            [[IPStore shared] applyDecodedMetadata:pcm.metadata toTrack:selectedTrack completion:^(NSError *metadataError) {
                IPPlayer *current = weakSelf;
                if (token != current.generation) return;
                [current publish];
                if (current.changed) current.changed(nil);
            }];
        }
    }];
}

- (void)startURL:(NSURL *)url token:(NSUInteger)token {
    NSError *e = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&e];
    [[AVAudioSession sharedInstance] setActive:YES error:&e];
    if (e) {
        if([self restoreOutgoing])return;
        if (self.changed)
            self.changed(e.localizedDescription);
        return;
    }
    self.player.volume=self.tail?0:1;
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [item addObserver:self forKeyPath:@"status" options:0 context:NULL];
    AVPlayerItem *old = self.player.currentItem;
    if (old)
        [old removeObserver:self forKeyPath:@"status"];
    [self.player replaceCurrentItemWithPlayerItem:item];
    if(self.wantsPlayback&&self.resumeSeconds<=0)[self.player play];
    [self publish];
    if (!self.pcmPlayer && [self.track[@"metadataPending"] boolValue])
        [[IPStore shared] refreshMetadataForTrack:self.track completion:^(NSError *error){[self publish];}];
}
- (void)observeValueForKeyPath:(NSString *)key
                      ofObject:(id)object
                        change:(NSDictionary *)c
                       context:(void *)ctx {
    if (object == self.player.currentItem && self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        NSUInteger token=self.generation;AVPlayerItem *item=self.player.currentItem;
        dispatch_async(dispatch_get_main_queue(),^{
            if(token!=self.generation||item!=self.player.currentItem)return;
            double seconds=self.resumeSeconds;
            void (^ready)(BOOL)=^(BOOL finished){dispatch_async(dispatch_get_main_queue(),^{if(token!=self.generation)return;self.opening=NO;self.resumeSeconds=0;if(self.wantsPlayback)[self.player play];else[self.player pause];[self startTransitionIfReady];[self saveSession];[self publish];});};
            if(seconds>0){double duration=CMTimeGetSeconds(item.duration);if(isfinite(duration)&&duration>0)seconds=MIN(seconds,MAX(0,duration-.1));[self.player seekToTime:CMTimeMakeWithSeconds(seconds,600) completionHandler:ready];}else ready(YES);
        });
        self.playbackDiagnostic = @{@"extension":self.track[@"extension"] ?: @"", @"state":@"ready",
            @"pcm": self.pcmPlayer ? [self.pcmPlayer diagnosticSnapshot] : @{}};
        [IPDiagnostics write];
    }
    if (object == self.player.currentItem &&
        self.player.currentItem.status == AVPlayerItemStatusFailed) {
        NSUInteger failedGeneration=self.generation;
        if(self.tail){dispatch_async(dispatch_get_main_queue(),^{if(failedGeneration==self.generation)[self restoreOutgoing];});return;}
        if(!self.usingLocal&&[[IPStore shared]localURL:self.track]){dispatch_async(dispatch_get_main_queue(),^{if(failedGeneration==self.generation)[self recoverFromCache];});return;}
        double failedPosition=self.lastGoodElapsed,failedDuration=self.duration;
        NSError *failure = self.player.currentItem.error;
        NSError *underlying = failure.userInfo[NSUnderlyingErrorKey];
        self.playbackDiagnostic = @{@"extension":self.track[@"extension"] ?: @"", @"state":@"failed",
            @"domain":failure.domain ?: @"", @"code":@(failure.code),
            @"underlyingDomain":underlying.domain ?: @"", @"underlyingCode":@(underlying.code),
            @"pcm":self.pcmPlayer ? [self.pcmPlayer diagnosticSnapshot] : @{}};
        [IPDiagnostics write];
        dispatch_async(dispatch_get_main_queue(), ^{
            if(failedGeneration!=self.generation)return;
            self.resumeSeconds=failedPosition;self.restoredDuration=failedDuration;self.awaitingResume=YES;self.opening=NO;[self publish];
            if (self.changed)
                self.changed([NSString stringWithFormat:IPL(@"No se pudo reproducir %@. Código %@ %ld (%ld)."),
                    [self.track[@"extension"] uppercaseString], failure.domain ?: @"audio", (long)failure.code, (long)underlying.code]);
        });
    }
}
- (BOOL)recoverFromCache {
    if(self.usingLocal||![[IPStore shared]localURL:self.track])return NO;
    double position=self.elapsed;if(!isfinite(position)||position<0)position=self.lastGoodElapsed;
    BOOL wanted=self.wantsPlayback;[self beginTracks:self.queue index:self.index resume:position];if(!wanted)[self pause];return YES;
}
- (double)duration { if(self.awaitingResume||self.opening)return self.restoredDuration;return self.pcmPlayer ? self.pcmPlayer.duration : CMTimeGetSeconds(self.player.currentItem.duration); }
- (double)elapsed { if(self.awaitingResume||self.opening)return self.resumeSeconds;return self.pcmPlayer ? self.pcmPlayer.currentTime : CMTimeGetSeconds(self.player.currentTime); }
- (BOOL)isSeeking {return self.pcmPlayer.seeking;}
- (BOOL)isPlaying { if(self.tail&&self.opening)return self.wantsPlayback;return self.pcmPlayer ? (self.pcmPlayer.playing||(self.pcmPlayer.seeking&&self.wantsPlayback)) : self.player.rate > 0; }
- (void)play {
    if(!self.track)return;if(self.awaitingResume||(!self.player.currentItem&&!self.pcmPlayer)){[self beginTracks:self.queue index:self.index resume:self.resumeSeconds];return;}
    self.wantsPlayback=YES;if(self.pcmPlayer)[self.pcmPlayer play];else if(!self.opening)[self.player play];
    [[IPStore shared]preparePlaybackCacheForQueue:self.queue index:self.index];[self publish];
}
- (void)pause { [self finishTransition];self.wantsPlayback=NO;if (self.pcmPlayer) [self.pcmPlayer pause]; else [self.player pause];[self saveSession]; [self publish]; }
- (void)tickPCM { if (self.pcmPlayer||self.awaitingResume) [self publish]; }
- (void)toggle {
    if (self.playing) [self pause]; else [self play];
}
- (void)advanceAutomatically {
    if(self.index+1<(NSInteger)self.queue.count)[self transitionToTracks:self.queue index:self.index+1 automatic:YES];else [self pause];
}
- (void)next {if(self.index+1<(NSInteger)self.queue.count)[self transitionToTracks:self.queue index:self.index+1 automatic:NO];else [self pause];}
- (void)previous {
    [self playTracks:self.queue index:MAX(0, self.index - 1)];
}
- (void)seek:(float)v {
    [self finishTransition];self.autoAttemptID=nil;
    if(self.awaitingResume){self.resumeSeconds=MAX(0,MIN(1,v))*self.restoredDuration;[self saveSession];[self publish];return;}
    if (self.pcmPlayer) { [self.pcmPlayer seekFraction:v]; return; }
    double d = self.duration;
    if (isfinite(d) && d > 0)
        [self.player seekToTime:CMTimeMakeWithSeconds(d * v, 600)];
}
- (void)attachTimeObserver {
    __weak IPPlayer *weak=self;
    self.observer=[self.player addPeriodicTimeObserverForInterval:CMTimeMake(1,1) queue:dispatch_get_main_queue() usingBlock:^(CMTime t){[weak publish];if(weak.changed)weak.changed(nil);}];
}
- (void)crossfadeSettingsChanged {
    [self finishTransition];
    [self updateAdvanceTimer];
    [[NSNotificationCenter defaultCenter]postNotificationName:@"IPCrossfadeChanged" object:self];
}
- (void)updateAdvanceTimer {
    BOOL needed=self.crossfade.active&&self.crossfade.automaticAdvance&&self.playing&&!self.opening&&!self.tail;
    if(!needed){[self.advanceTimer invalidate];self.advanceTimer=nil;}
    else if(!self.advanceTimer){self.advanceTimer=[NSTimer timerWithTimeInterval:.25 target:self selector:@selector(checkAutomaticTransition) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop]addTimer:self.advanceTimer forMode:NSRunLoopCommonModes];}
}
- (void)toggleCrossfadeSession {
    if(!self.crossfade.sessionControl||!self.crossfade.enabled)return;
    self.crossfade.sessionSuspended=!self.crossfade.sessionSuspended;[self crossfadeSettingsChanged];
}
- (void)checkAutomaticTransition {
    if(![self.crossfade allowsAutomatic:YES]||self.tail||self.opening||self.awaitingResume||self.pcmPlayer.seeking||!self.playing||self.index+1>=(NSInteger)self.queue.count)return;
    double d=self.duration,t=self.elapsed;
    if(!isfinite(d)||!isfinite(t)||d<=0||t<0||d-t>self.crossfade.duration||d-t<=.15)return;
    NSString *attempt=[NSString stringWithFormat:@"%@/%ld",self.track[@"id"],(long)self.index];if([attempt isEqual:self.autoAttemptID])return;
    self.autoAttemptID=attempt;[self transitionToTracks:self.queue index:self.index+1 automatic:YES];
}
- (void)transitionToTracks:(NSArray *)tracks index:(NSInteger)index automatic:(BOOL)automatic {
    if(index<0||index>=(NSInteger)tracks.count)return;
    BOOL overlap=[self.crossfade allowsAutomatic:automatic]&&self.playing&&!self.opening&&!self.awaitingResume;
    [self finishTransition];
    if(overlap){
        IPAudioTail *tail=[IPAudioTail new];tail.player=self.player;tail.pcm=self.pcmPlayer;tail.server=self.server;tail.link=self.localAudio;tail.track=self.track;tail.queue=self.queue;tail.index=self.index;tail.usingLocal=self.usingLocal;
        if(self.observer){[self.player removeTimeObserver:self.observer];self.observer=nil;}
        if(self.player.currentItem)[self.player.currentItem removeObserver:self forKeyPath:@"status"];
        tail.pcm.ended=nil;tail.pcm.error=nil;
        self.tail=tail;self.tailOpenedAt=[NSProcessInfo processInfo].systemUptime;self.fadeStarted=NO;
        self.player=[AVPlayer new];[self attachTimeObserver];self.pcmPlayer=nil;self.server=nil;
        NSURL *links=[self.playbackLinksRoot URLByAppendingPathComponent:[[NSUUID UUID]UUIDString]];
        self.localAudio=[[IPLocalAudioFile alloc]initWithDirectory:links];
        self.preserveTail=YES;
        self.fadeTimer=[NSTimer timerWithTimeInterval:.05 target:self selector:@selector(tickTransition) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop]addTimer:self.fadeTimer forMode:NSRunLoopCommonModes];
    }
    [self beginTracks:tracks index:index resume:0];
}
- (void)setIncomingGain:(float)gain {self.player.volume=gain;self.pcmPlayer.volume=gain;}
- (void)startTransitionIfReady {
    if(!self.tail||self.opening||self.fadeStarted)return;
    double remaining=self.tail.pcm?self.tail.pcm.duration-self.tail.pcm.currentTime:CMTimeGetSeconds(self.tail.player.currentItem.duration)-CMTimeGetSeconds(self.tail.player.currentTime);
    self.fadeDuration=self.crossfade.duration;if(isfinite(remaining))self.fadeDuration=MIN(self.fadeDuration,MAX(.05,remaining));
    if(isfinite(self.duration)&&self.duration>0)self.fadeDuration=MIN(self.fadeDuration,MAX(.05,self.duration*.5));
    self.fadeMediaStart=self.elapsed;self.fadeProgress=0;self.lastFadeMovement=[NSProcessInfo processInfo].systemUptime;self.fadeStarted=YES;
}
- (void)tickTransition {
    if(!self.tail)return;
    double now=[NSProcessInfo processInfo].systemUptime;
    if(!self.fadeStarted){if(now-self.tailOpenedAt>12)[self restoreOutgoing];return;}
    if(!self.wantsPlayback)return;
    // Media time, rather than timer ticks, holds gains steady if the incoming source stalls.
    double t=self.elapsed-self.fadeMediaStart;if(!isfinite(t)||t<0)t=0;
    double progress=MIN(1,t/MAX(.05,self.fadeDuration));
    if(progress>self.fadeProgress){self.fadeProgress=progress;self.lastFadeMovement=now;}
    else if(now-self.lastFadeMovement>12){[self restoreOutgoing];return;}
    float out,in;IPFadeGains(self.fadeProgress,self.crossfade.curve,&out,&in);
    self.tail.player.volume=out;self.tail.pcm.volume=out;[self setIncomingGain:in];
    if(self.fadeProgress>=1)[self finishTransition];
}
- (void)discardAudioLink:(IPLocalAudioFile *)link {
    [link close];if(link&&![link.directoryURL isEqual:self.playbackLinksRoot])[[NSFileManager defaultManager]removeItemAtURL:link.directoryURL error:NULL];
}
- (void)finishTransition {
    [self.fadeTimer invalidate];self.fadeTimer=nil;self.fadeStarted=NO;
    IPAudioTail *old=self.tail;self.tail=nil;
    [old.player pause];[old.player replaceCurrentItemWithPlayerItem:nil];[old.pcm stop];[old.server stop];[self discardAudioLink:old.link];
    [self setIncomingGain:1];
}
- (BOOL)restoreOutgoing {
    IPAudioTail *old=self.tail;if(!old)return NO;
    ++self.generation;[self.fadeTimer invalidate];self.fadeTimer=nil;self.fadeStarted=NO;
    if(self.observer){[self.player removeTimeObserver:self.observer];self.observer=nil;}
    if(self.player.currentItem)[self.player.currentItem removeObserver:self forKeyPath:@"status"];
    [self.player pause];[self.player replaceCurrentItemWithPlayerItem:nil];[self.pcmPlayer stop];[self.server stop];[self discardAudioLink:self.localAudio];
    self.player=old.player;self.pcmPlayer=old.pcm;self.server=old.server;self.localAudio=old.link;
    self.queue=old.queue;self.index=old.index;self.track=old.track;self.usingLocal=old.usingLocal;self.tail=nil;
    self.opening=NO;self.awaitingResume=NO;self.resumeSeconds=0;
    [self attachTimeObserver];if(self.player.currentItem)[self.player.currentItem addObserver:self forKeyPath:@"status" options:0 context:NULL];
    if(self.pcmPlayer)[self wirePCM:self.pcmPlayer token:self.generation];
    [self setIncomingGain:1];
    self.autoAttemptID=[NSString stringWithFormat:@"%@/%ld",self.track[@"id"],(long)self.index];
    [self.session saveQueue:self.queue index:self.index elapsed:self.elapsed duration:self.duration];
    [[IPStore shared].smartCache cancel];[[IPStore shared].smartCache protectTrack:self.track];
    self.playbackDiagnostic=@{@"state":@"crossfade-fallback",@"extension":self.track[@"extension"]?:@""};
    if(self.changed)self.changed(IPL(@"No se pudo preparar la siguiente canción para el fundido. Se conserva la anterior."));
    [self publish];return YES;
}

@end

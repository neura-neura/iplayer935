#import "IPStrings.h"
#import "IPPCMPlayer.h"
#import "IPPCMServer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#include <errno.h>
#include <string.h>

enum { IPPCMQueueBufferCount = 3, IPPCMQueueFramesPerBuffer = 4096 };

@interface IPPCMPlayer () {
    IPPCMServer *_decoder;
    dispatch_queue_t _workQueue;
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[IPPCMQueueBufferCount];
    NSUInteger _bufferGenerations[IPPCMQueueBufferCount];
    NSUInteger _queuedBufferCount;
    AudioStreamBasicDescription _format;
    NSUInteger _generation;
    int _sampleRate;
    int _channels;
    int64_t _durationFrames;
    int64_t _currentFrame;
    float _volume;
    BOOL _started;
    BOOL _starting;
    BOOL _playing;
    BOOL _paused;
    BOOL _seeking;
    BOOL _wantsPlayback;
    BOOL _stopRequested;
    BOOL _atEnd;
    BOOL _disposed;
    BOOL _endedSent;
    BOOL _audioQueueCreated;
    NSError *_lastError;
    IPPCMPlayer *_lifecycleRetain;
}
- (void)handleQueueCallback:(AudioQueueRef)queue buffer:(AudioQueueBufferRef)buffer;
@end

static void IPPCMQueueOutput(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    IPPCMPlayer *player = (__bridge IPPCMPlayer *)userData;
    [player handleQueueCallback:queue buffer:buffer];
}

@implementation IPPCMPlayer

- (NSDictionary *)metadata { return [_decoder metadata]; }

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _decoder = [[IPPCMServer alloc] initWithURL:url];
        _volume=1;
        _workQueue = dispatch_queue_create("com.iplayer935.pcm-audioqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size {
    self = [self initWithURL:nil];
    if (self) _decoder = [[IPPCMServer alloc] initWithProfile:profile password:password path:path size:size];
    return self;
}

- (NSTimeInterval)duration {
    @synchronized (self) { return _sampleRate > 0 ? (NSTimeInterval)_durationFrames / (NSTimeInterval)_sampleRate : 0; }
}

- (NSTimeInterval)currentTime {
    @synchronized (self) { return _sampleRate > 0 ? (NSTimeInterval)_currentFrame / (NSTimeInterval)_sampleRate : 0; }
}

- (float)volume {@synchronized(self){return _volume;}}
- (void)setVolume:(float)value {@synchronized(self){_volume=isfinite(value)?MAX(0,MIN(1,value)):1;if(_queue&&!_disposed&&!_stopRequested)AudioQueueSetParameter(_queue,kAudioQueueParam_Volume,_volume);}}

- (BOOL)isSeeking {@synchronized(self){return _seeking;}}
- (BOOL)isPlaying { @synchronized (self) { return _playing; } }

- (NSDictionary *)diagnosticSnapshot {
    NSDictionary *decoder = [_decoder diagnosticSnapshot] ?: @{};
    @synchronized (self) {
        NSMutableDictionary *snapshot = [decoder mutableCopy];
        snapshot[@"queueStarted"] = @(_started);
        snapshot[@"queueStarting"] = @(_starting);
        snapshot[@"queuePlaying"] = @(_playing);
        snapshot[@"queuePaused"] = @(_paused);
        snapshot[@"queueSeeking"]=@(_seeking);snapshot[@"queueWantsPlayback"]=@(_wantsPlayback);
        snapshot[@"queueAtEnd"] = @(_atEnd);
        snapshot[@"queueGeneration"] = @(_generation);
        snapshot[@"queueSampleRate"] = @(_sampleRate);
        snapshot[@"queueChannels"] = @(_channels);
        snapshot[@"queueCurrentFrame"] = @(_currentFrame);
        snapshot[@"queueErrorCode"] = @(_lastError.code);
        return snapshot;
    }
}

- (void)startWithCompletion:(IPPCMPlayerStartCompletion)completion {
    @synchronized (self) {
        if (_started || _starting || _stopRequested) {
            NSError *error = [NSError errorWithDomain:@"IPPCMPlayerErrorDomain" code:EBUSY userInfo:@{NSLocalizedDescriptionKey:IPL(@"PCM playback is already started or stopped.")}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
            return;
        }
        _starting = YES;_wantsPlayback=YES;
        _lifecycleRetain = self;
    }
    NSUInteger generation; @synchronized (self) { generation = _generation; }
    dispatch_async(_workQueue, ^{
        NSError *error = nil;
        if (![self->_decoder preparePCM:&error]) {
            [self finishStartWithError:error completion:completion generation:generation];
            return;
        }
        NSDictionary *decoderInfo = [self->_decoder diagnosticSnapshot];
        int rate = [decoderInfo[@"sampleRate"] intValue];
        int channels = [decoderInfo[@"channels"] intValue];
        int64_t durationFrames = [decoderInfo[@"durationFrames"] longLongValue];
        if (rate <= 0 || (channels != 1 && channels != 2) || durationFrames <= 0) {
            error = [NSError errorWithDomain:@"IPPCMPlayerErrorDomain" code:EINVAL userInfo:@{NSLocalizedDescriptionKey:IPL(@"The decoded audio format is invalid.")}];
            [self->_decoder closePCM];
            [self finishStartWithError:error completion:completion generation:generation];
            return;
        }
        int64_t initialFrame=isfinite(self.initialTime)?(int64_t)llround(MAX(0,MIN(self.initialTime,(double)durationFrames/rate-.1))*rate):0;
        if(initialFrame>0&&![self->_decoder seekPCMFrame:initialFrame error:&error]){[self->_decoder closePCM];[self finishStartWithError:error completion:completion generation:generation];return;}
        AudioStreamBasicDescription format = {0};
        format.mSampleRate = rate;
        format.mFormatID = kAudioFormatLinearPCM;
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        format.mBytesPerPacket = (UInt32)(channels * 2);
        format.mFramesPerPacket = 1;
        format.mBytesPerFrame = (UInt32)(channels * 2);
        format.mChannelsPerFrame = (UInt32)channels;
        format.mBitsPerChannel = 16;
        AudioQueueRef queue = NULL;
        OSStatus status = AudioQueueNewOutput(&format, IPPCMQueueOutput, (__bridge void *)self, NULL, NULL, 0, &queue);
        if (status != noErr) {
            error = [self audioError:status message:IPL(@"Could not create the audio output queue.")];
            [self->_decoder closePCM];
            [self finishStartWithError:error completion:completion generation:generation];
            return;
        }
        UInt32 bufferBytes = IPPCMQueueFramesPerBuffer * format.mBytesPerFrame;
        AudioQueueBufferRef buffers[IPPCMQueueBufferCount] = {NULL, NULL, NULL};
        for (UInt32 i = 0; i < IPPCMQueueBufferCount; i++) {
            status = AudioQueueAllocateBuffer(queue, bufferBytes, &buffers[i]);
            if (status != noErr) {
                error = [self audioError:status message:IPL(@"Could not allocate an audio buffer.")];
                for (UInt32 j = 0; j < i; j++) AudioQueueFreeBuffer(queue, buffers[j]);
                AudioQueueDispose(queue, true);
                [self->_decoder closePCM];
                [self finishStartWithError:error completion:completion generation:generation];
                return;
            }
        }
        @synchronized (self) {
            if (generation != self->_generation || self->_stopRequested) {
                self->_queue = queue; self->_audioQueueCreated = YES;
                memcpy(self->_buffers, buffers, sizeof(buffers));
            } else {
                self->_queue = queue; self->_audioQueueCreated = YES;
                memcpy(self->_buffers, buffers, sizeof(buffers));
                self->_format = format; self->_sampleRate = rate; self->_channels = channels;
                self->_durationFrames = durationFrames; self->_currentFrame = initialFrame;
            }
        }
        if (generation != self->_generation || self->_stopRequested) {
            [self teardownOnWorkQueue];
            [self finishStartWithError:[self cancelledError] completion:completion generation:generation];
            return;
        }
        UInt32 queued = 0;
        for (UInt32 i = 0; i < IPPCMQueueBufferCount; i++) {
            if (![self fillAndEnqueueBuffer:buffers[i] queue:queue generation:generation error:&error]) {
                if (error || queued == 0) {
                    [self teardownOnWorkQueue];
                    [self finishStartWithError:error ?: [self audioError:0 message:IPL(@"The audio source ended before playback could start.")] completion:completion generation:generation];
                    return;
                }
                break;
            }
            queued++;
        }
        @synchronized (self) {
            if (generation != self->_generation || self->_stopRequested || queue != self->_queue) status = ECANCELED;
            else {
                AudioQueueSetParameter(queue,kAudioQueueParam_Volume,self->_volume);
                status = self->_wantsPlayback?AudioQueueStart(queue, NULL):noErr;
                if (status == noErr) { self->_started = YES; self->_starting = NO; self->_playing = self->_wantsPlayback; self->_paused = !self->_wantsPlayback; }
            }
        }
        if (status != noErr) {
            error = status == ECANCELED ? [self cancelledError] : [self audioError:status message:IPL(@"Could not start audio playback.")];
            [self teardownOnWorkQueue];
            [self finishStartWithError:error completion:completion generation:generation];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil); });
    });
}

- (BOOL)fillAndEnqueueBuffer:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)queue generation:(NSUInteger)generation error:(NSError **)error {
    @synchronized (self) { if (generation != _generation || _stopRequested) return NO; }
    NSData *pcm = [_decoder readPCMFrames:IPPCMQueueFramesPerBuffer error:error];
    if (!pcm) {
        if (error && *error) { @synchronized (self) { _lastError = *error; } }
        return NO;
    }
    if (pcm.length == 0) { @synchronized (self) { _atEnd = YES; } return NO; }
    @synchronized (self) {
        if (generation != _generation || _stopRequested || queue != _queue) {
            if (error) *error = [self cancelledError];
            return NO;
        }
    }
    if (pcm.length > buffer->mAudioDataBytesCapacity) {
        if (error) *error = [NSError errorWithDomain:@"IPPCMPlayerErrorDomain" code:EOVERFLOW userInfo:@{NSLocalizedDescriptionKey:IPL(@"Decoded PCM exceeded its audio buffer.")}];
        return NO;
    }
    memcpy(buffer->mAudioData, pcm.bytes, pcm.length);
    buffer->mAudioDataByteSize = (UInt32)pcm.length;
    NSUInteger bufferIndex = NSNotFound;
    @synchronized (self) {
        for (NSUInteger i = 0; i < IPPCMQueueBufferCount; i++) if (_buffers[i] == buffer) { bufferIndex = i; _bufferGenerations[i] = generation; _queuedBufferCount++; break; }
    }
    OSStatus status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    if (status != noErr) { @synchronized (self) { if (_queuedBufferCount) _queuedBufferCount--; } if (error) *error = [self audioError:status message:IPL(@"Could not enqueue decoded audio.")]; return NO; }
    if (bufferIndex == NSNotFound) { if (error) *error = [self audioError:EINVAL message:IPL(@"Audio queue returned an unknown buffer.")]; return NO; }
    return YES;
}

- (void)handleQueueCallback:(AudioQueueRef)queue buffer:(AudioQueueBufferRef)buffer {
    NSUInteger generation = NSUIntegerMax;
    @synchronized (self) {
        for (NSUInteger i = 0; i < IPPCMQueueBufferCount; i++) if (_buffers[i] == buffer) { generation = _bufferGenerations[i]; break; }
        if (generation == _generation && !_stopRequested) {
            if (_queuedBufferCount) _queuedBufferCount--;
            _currentFrame += (int64_t)(buffer->mAudioDataByteSize / MAX((UInt32)1, _format.mBytesPerFrame));
        }
    }
    dispatch_async(_workQueue, ^{
        @autoreleasepool {
            @synchronized (self) {
                if (generation != self->_generation || self->_stopRequested || queue != self->_queue) return;
            }
            NSError *error = nil;
            if (![self fillAndEnqueueBuffer:buffer queue:queue generation:generation error:&error]) {
                if (error) { [self failOnWorkQueue:error generation:generation]; return; }
                BOOL shouldSignal = NO;
                @synchronized (self) {
                    if (!_queuedBufferCount && !self->_endedSent && generation == self->_generation && !self->_stopRequested) {
                        self->_endedSent = YES; self->_playing = NO; self->_atEnd = YES; shouldSignal = YES;
                    }
                }
                if (shouldSignal) {
                    AudioQueueStop(queue, false);
                    dispatch_async(dispatch_get_main_queue(), ^{ if (generation == self->_generation && self.ended) self.ended(); });
                }
            }
        }
    });
}

- (void)play {
    AudioQueueRef queue; BOOL wasAtEnd;
    @synchronized (self) {
        if (_stopRequested)return;_wantsPlayback=YES;
        if (!_queue || _playing || _seeking) return;
        wasAtEnd = _atEnd;
        _playing = YES; _paused = NO; _endedSent = NO; queue = _queue;
    }
    dispatch_async(_workQueue, ^{
        NSUInteger generation; @synchronized (self) { generation = self->_generation; }
        @synchronized (self) { if (generation != self->_generation || self->_stopRequested || queue != self->_queue) return; }
        UInt32 queued = 0;
        if (wasAtEnd) {
            AudioQueueStop(queue, true); AudioQueueReset(queue);
            NSError *error = nil;
            int64_t current; @synchronized (self) { current = self->_currentFrame; }
            if (current >= self->_durationFrames) current = 0;
            if (![self->_decoder seekPCMFrame:current error:&error]) { [self failOnWorkQueue:error generation:generation]; return; }
            @synchronized (self) { if (generation == self->_generation) { self->_currentFrame = current; self->_atEnd = NO; self->_queuedBufferCount = 0; } }
            for (UInt32 i = 0; i < IPPCMQueueBufferCount; i++) {
                NSError *fillError = nil;
                if (![self fillAndEnqueueBuffer:self->_buffers[i] queue:queue generation:generation error:&fillError]) {
                    if (fillError) [self failOnWorkQueue:fillError generation:generation];
                    else if (!queued) [self signalEnded:generation];
                    break;
                }
                queued++;
            }
        }
        if (wasAtEnd && !queued) return;
        OSStatus status;
        @synchronized (self) {
            if (generation != self->_generation || self->_stopRequested || queue != self->_queue) return;
            status = AudioQueueStart(queue, NULL);
        }
        if (status != noErr) [self failOnWorkQueue:[self audioError:status message:IPL(@"Could not resume audio playback.")] generation:generation];
    });
}

- (void)pause {
    @synchronized (self) { _wantsPlayback=NO;_paused=YES;if(_queue&&_playing)AudioQueuePause(_queue);_playing=NO; }
}

- (void)seekFraction:(double)fraction {
    if(!isfinite(fraction))return;fraction=MAX(0,MIN(1,fraction));
    AudioQueueRef queue;NSUInteger generation;int64_t target;
    @synchronized(self){
        if(!_queue||_stopRequested||!_started)return;
        generation=++_generation;queue=_queue;_seeking=YES;_playing=NO;_atEnd=NO;_endedSent=NO;
        // Repeated requests preserve user intent; only the newest generation may restart audio.
        target=(int64_t)llround((double)MAX((int64_t)0,_durationFrames-1)*fraction);_currentFrame=target;
        AudioQueuePause(queue);
    }
    dispatch_async(_workQueue,^{@autoreleasepool{
        @synchronized(self){if(generation!=self->_generation||self->_stopRequested||queue!=self->_queue)return;}
        AudioQueueStop(queue,true);AudioQueueReset(queue);
        NSError *error=nil;
        if(![self->_decoder seekPCMFrame:target error:&error]){[self failOnWorkQueue:error generation:generation];return;}
        @synchronized(self){if(generation!=self->_generation||self->_stopRequested)return;self->_currentFrame=target;self->_queuedBufferCount=0;self->_atEnd=NO;}
        UInt32 queued=0;
        for(UInt32 i=0;i<IPPCMQueueBufferCount;i++){
            if(![self fillAndEnqueueBuffer:self->_buffers[i] queue:queue generation:generation error:&error]){
                if(error){[self failOnWorkQueue:error generation:generation];return;}
                break;
            }queued++;
        }
        @synchronized(self){
            if(generation!=self->_generation||self->_stopRequested||queue!=self->_queue)return;
            self->_seeking=NO;
            if(queued){OSStatus status=self->_wantsPlayback?AudioQueueStart(queue,NULL):noErr;
                if(status!=noErr){[self failOnWorkQueue:[self audioError:status message:IPL(@"Could not resume after seeking.")] generation:generation];return;}
                self->_playing=self->_wantsPlayback;self->_paused=!self->_wantsPlayback;
            }
        }
        if(!queued)[self signalEnded:generation];
    }});
}

- (void)stop {
    @synchronized (self) {
        if (_stopRequested) return;
        _stopRequested = YES; _seeking=NO;_wantsPlayback=NO; _generation++; _playing = NO; _paused = NO; _starting = NO;
        if (_queue) AudioQueuePause(_queue);
    }
    [_decoder stop];
    dispatch_async(_workQueue, ^{ [self teardownOnWorkQueue]; });
}

- (void)teardownOnWorkQueue {
    AudioQueueRef queue;
    @synchronized (self) { if (_disposed) return; _disposed = YES; queue = _queue; _queue = NULL; }
    if (queue) {
        AudioQueueStop(queue, true);
        AudioQueueDispose(queue, true);
    }
    @synchronized (self) {
        memset(_buffers, 0, sizeof(_buffers)); memset(_bufferGenerations, 0, sizeof(_bufferGenerations)); _queuedBufferCount = 0; _audioQueueCreated = NO; _started = NO; _playing = NO;
    }
    [_decoder closePCM];
    @synchronized (self) { _lifecycleRetain = nil; }
}

- (void)finishStartWithError:(NSError *)error completion:(IPPCMPlayerStartCompletion)completion generation:(NSUInteger)generation {
    @synchronized (self) { _starting = NO; _lastError = error; }
    if (error) [self teardownOnWorkQueue];
    dispatch_async(dispatch_get_main_queue(), ^{ if (generation == self->_generation && completion) completion(error); });
}

- (void)signalEnded:(NSUInteger)generation {
    BOOL send = NO;
    @synchronized (self) { if (!_endedSent && generation == _generation && !_stopRequested) { _endedSent = YES; _atEnd = YES; _playing = NO; send = YES; } }
    if (send) dispatch_async(dispatch_get_main_queue(), ^{ if (generation == self->_generation && self.ended) self.ended(); });
}

- (void)failOnWorkQueue:(NSError *)error generation:(NSUInteger)generation {
    @synchronized (self) { if (generation != _generation || _stopRequested) return; _lastError = error; _playing = NO;_seeking=NO; }
    AudioQueueRef queue; @synchronized (self) { queue = _queue; }
    if (queue) AudioQueueStop(queue, false);
    dispatch_async(dispatch_get_main_queue(), ^{ if (generation == self->_generation && self.error) self.error(error); });
}

- (NSError *)audioError:(OSStatus)status message:(NSString *)message {
    return [NSError errorWithDomain:@"IPPCMPlayerAudioQueueErrorDomain" code:status userInfo:@{NSLocalizedDescriptionKey:message}];
}

- (NSError *)cancelledError {
    return [NSError errorWithDomain:@"IPPCMPlayerErrorDomain" code:ECANCELED userInfo:@{NSLocalizedDescriptionKey:IPL(@"PCM playback was cancelled.")}];
}

- (void)dealloc {
    if (_queue && !_disposed) {
        AudioQueueStop(_queue, true);
        AudioQueueDispose(_queue, true);
    }
}

@end

#import "IPStrings.h"
#import "IPPCMServer.h"
#import "IPSMB.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/mathematics.h>
#include <libswresample/swresample.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <libavutil/version.h>

static NSString * const IPPCMErrorDomain = @"IPPCMServerErrorDomain";
static const uint32_t IPPCMHeaderLength = 44;
static const int IPPCMReadFrames = 4096;
static const int IPPCMSourceRateLimit = 192000;

static void IPPCMWriteLE16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)(value & 0xff); p[1] = (uint8_t)(value >> 8);
}

static void IPPCMWriteLE32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)(value & 0xff); p[1] = (uint8_t)((value >> 8) & 0xff);
    p[2] = (uint8_t)((value >> 16) & 0xff); p[3] = (uint8_t)(value >> 24);
}

@interface IPPCMServer () {
    NSURL *_sourceURL;
    IPSMB *_smb;
    NSString *_smbPath;
    uint64_t _smbSize;
    int64_t _smbOffset;
    AVIOContext *_avio;
    AVFormatContext *_format;
    AVCodecContext *_codec;
    SwrContext *_resampler;
    AVPacket *_packet;
    AVFrame *_frame;
    int _streamIndex;
    int _sampleRate;
    int _channels;
    int64_t _durationFrames;
    BOOL _ready;
    BOOL _starting;
    BOOL _running;
    BOOL _interrupt;
    int _listenFD;
    int _clientFD;
    dispatch_queue_t _queue;
    dispatch_semaphore_t _decodeLock;
    int64_t _decodedFrame;
    int64_t _targetFrame;
    int64_t _discardUntilFrame;
    int64_t _seekBaseFrame;
    BOOL _demuxEOF;
    BOOL _flushSent;
    BOOL _decoderEOF;
    NSInteger _lastReadError;
    NSUInteger _seekProbeCount;
    NSString *_seekMode;
    BOOL _pcmPrepared;
    NSDictionary *_metadata;
    NSMutableData *_pendingPCM;
    NSMutableArray<NSDictionary *> *_recentRequests;
    NSMutableDictionary *_activeRequest;
    NSUInteger _totalRequests;
}
- (BOOL)shouldInterrupt;
- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message;
- (BOOL)isRunning;
- (void)serveLoop;
- (void)handleClient:(int)fd;
- (void)closeDecoder;
- (void)freeIOContext;
- (int)readSMB:(uint8_t *)buffer length:(int)length;
- (int64_t)seekSMB:(int64_t)offset whence:(int)whence;
- (BOOL)openDecoder:(NSError **)error;
- (BOOL)seekToFrame:(int64_t)frame error:(NSError **)error;
- (NSData *)readFrames:(uint32_t)frames error:(NSError **)error;
- (BOOL)writeData:(NSData *)data fd:(int)fd;
- (void)sendStatus:(int)status reason:(NSString *)reason fd:(int)fd extra:(NSString *)extra;
@end

static int IPPCMReadSMB(void *opaque, uint8_t *buffer, int length) {
    return [(__bridge IPPCMServer *)opaque readSMB:buffer length:length];
}

static int64_t IPPCMSeekSMB(void *opaque, int64_t offset, int whence) {
    return [(__bridge IPPCMServer *)opaque seekSMB:offset whence:whence];
}

static int IPPCMInterrupt(void *opaque) {
    IPPCMServer *server = (__bridge IPPCMServer *)opaque;
    return [server shouldInterrupt] ? 1 : 0;
}

@implementation IPPCMServer

- (NSDictionary *)metadata { @synchronized(self) { return _metadata ?: @{}; } }

- (void)freeIOContext {
    if (_avio) {
        av_freep(&_avio->buffer);
        avio_context_free(&_avio);
    }
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _sourceURL = [url copy];
        _streamIndex = -1;
        _listenFD = -1;
        _clientFD = -1;
        _decodeLock = dispatch_semaphore_create(1);
        _pendingPCM = [NSMutableData data];
        _recentRequests = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size {
    self = [self initWithURL:nil];
    if (self) {
        _smb = [[IPSMB alloc] initWithProfile:profile password:password];
        _smbPath = [path copy];
        _smbSize = size;
    }
    return self;
}

- (NSDictionary *)diagnosticSnapshot {
    @synchronized (self) {
        return @{
            @"ready": @(_ready), @"starting": @(_starting), @"running": @(_running),
            @"sampleRate": @(_sampleRate), @"channels": @(_channels),
            @"durationFrames": @(_durationFrames), @"requestCount": @(_totalRequests),
            @"metadataFields": [[_metadata allKeys] sortedArrayUsingSelector:@selector(compare:)] ?: @[],
            @"seekMode":_seekMode?:@"none",@"seekProbes":@(_seekProbeCount),
            @"decodedFrame": @(_decodedFrame), @"targetFrame": @(_targetFrame),
            @"demuxEOF": @(_demuxEOF), @"decoderEOF": @(_decoderEOF), @"lastReadError": @(_lastReadError),
            @"smbOffset": @(_smbOffset), @"smbSize": @(_smbSize),
            @"requests": [_recentRequests copy]
        };
    }
}

- (void)finishActiveRequest {
    @synchronized (self) {
        if (_activeRequest) {
            NSTimeInterval started = [_activeRequest[@"_startedAt"] doubleValue];
            _activeRequest[@"elapsedMs"] = @((NSUInteger)MAX(0, (NSProcessInfo.processInfo.systemUptime - started) * 1000.0));
            [_activeRequest removeObjectForKey:@"_startedAt"];
            [_recentRequests addObject:[_activeRequest copy]];
            if (_recentRequests.count > 8) [_recentRequests removeObjectAtIndex:0];
            _activeRequest = nil;
        }
    }
}

- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:IPPCMErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (BOOL)openDecoder:(NSError **)error {
    if (_ready) return YES;
    if (!_smb && (!_sourceURL || (!_sourceURL.isFileURL && ![@[@"http", @"https"] containsObject:_sourceURL.scheme.lowercaseString]))) {
        [self setError:error code:EINVAL message:IPL(@"Input must be a local file or HTTP URL.")];
        return NO;
    }
    AVFormatContext *format = avformat_alloc_context();
    if (!format) { [self setError:error code:ENOMEM message:IPL(@"Could not allocate media reader.")]; return NO; }
    format->interrupt_callback.callback = IPPCMInterrupt;
    format->interrupt_callback.opaque = (__bridge void *)self;
    AVDictionary *options = NULL;
    av_dict_set(&options, "rw_timeout", "10000000", 0);
    const char *input = NULL;
    if (_smb) {
        NSError *smbError = nil;
        if (![_smb connect:&smbError]) {
            av_dict_free(&options); avformat_free_context(format);
            [self setError:error code:smbError.code ?: EIO message:IPL(@"Could not connect to the SMB audio source.")];
            return NO;
        }
        if (_smbSize == 0) _smbSize = [_smb size:_smbPath error:&smbError];
        uint8_t *buffer = av_malloc(32768);
        if (_smbSize == 0 || !buffer) {
            if (buffer) av_free(buffer);
            av_dict_free(&options); avformat_free_context(format); [_smb disconnect];
            [self setError:error code:(buffer ? (smbError.code ?: EINVAL) : ENOMEM) message:IPL(@"Could not read the SMB audio source size.")];
            return NO;
        }
        _smbOffset = 0;
        _avio = avio_alloc_context(buffer, 32768, 0, (__bridge void *)self, IPPCMReadSMB, NULL, IPPCMSeekSMB);
        if (!_avio) {
            av_free(buffer); av_dict_free(&options); avformat_free_context(format); [_smb disconnect];
            [self setError:error code:ENOMEM message:IPL(@"Could not allocate SMB media reader.")];
            return NO;
        }
        _avio->seekable = AVIO_SEEKABLE_NORMAL;
        format->pb = _avio; format->flags |= AVFMT_FLAG_CUSTOM_IO;
    } else {
        input = _sourceURL.isFileURL ? _sourceURL.path.fileSystemRepresentation : _sourceURL.absoluteString.UTF8String;
    }
    int rc = avformat_open_input(&format, input, NULL, &options);
    av_dict_free(&options);
    if (rc < 0) {
        avformat_free_context(format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:-rc message:IPL(@"Could not open the media source.")];
        return NO;
    }
    rc = avformat_find_stream_info(format, NULL);
    if (rc < 0) {
        avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:-rc message:IPL(@"Could not inspect the media source.")];
        return NO;
    }
    int streamIndex = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (streamIndex < 0) {
        avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:-streamIndex message:IPL(@"The source has no supported audio stream.")];
        return NO;
    }
    AVStream *stream = format->streams[streamIndex];
    const AVCodec *decoder = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!decoder) {
        avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:ENOTSUP message:IPL(@"No decoder is available for this audio format.")];
        return NO;
    }
    AVCodecContext *codec = avcodec_alloc_context3(decoder);
    if (!codec || avcodec_parameters_to_context(codec, stream->codecpar) < 0 || avcodec_open2(codec, decoder, NULL) < 0) {
        if (codec) avcodec_free_context(&codec);
        avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:EINVAL message:IPL(@"Could not initialize the audio decoder.")];
        return NO;
    }
    int sampleRate = codec->sample_rate;
    if (sampleRate < 8000 || sampleRate > IPPCMSourceRateLimit) {
        avcodec_free_context(&codec); avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:EINVAL message:IPL(@"The source sample rate is outside the supported range.")];
        return NO;
    }
    int channels = 2;
    SwrContext *resampler = NULL;
#if LIBAVUTIL_VERSION_MAJOR >= 57
    AVChannelLayout outputLayout = AV_CHANNEL_LAYOUT_STEREO;
    if (codec->ch_layout.nb_channels == 1) { outputLayout = (AVChannelLayout)AV_CHANNEL_LAYOUT_MONO; channels = 1; }
    rc = swr_alloc_set_opts2(&resampler, &outputLayout, AV_SAMPLE_FMT_S16, sampleRate,
                             &codec->ch_layout, codec->sample_fmt, sampleRate, 0, NULL);
#else
    int64_t outputLayout = channels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
    int64_t inputLayout = codec->channel_layout;
    if (!inputLayout) inputLayout = av_get_default_channel_layout(codec->channels);
    channels = codec->channels == 1 ? 1 : 2;
    outputLayout = channels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
    resampler = swr_alloc_set_opts(NULL, outputLayout, AV_SAMPLE_FMT_S16, sampleRate,
                                   inputLayout, codec->sample_fmt, sampleRate, 0, NULL);
    rc = resampler ? 0 : AVERROR(ENOMEM);
#endif
    if (rc < 0 || !resampler || swr_init(resampler) < 0) {
        if (resampler) swr_free(&resampler);
        avcodec_free_context(&codec); avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:EINVAL message:IPL(@"Could not initialize PCM conversion.")];
        return NO;
    }
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    if (!packet || !frame) {
        av_packet_free(&packet); av_frame_free(&frame); swr_free(&resampler);
        avcodec_free_context(&codec); avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:ENOMEM message:IPL(@"Could not allocate decoder buffers.")];
        return NO;
    }
    int64_t duration = format->duration != AV_NOPTS_VALUE
        ? av_rescale(format->duration, sampleRate, AV_TIME_BASE)
        : (stream->duration != AV_NOPTS_VALUE ? av_rescale_q(stream->duration, stream->time_base, (AVRational){1, sampleRate}) : 0);
    if (stream->codecpar->initial_padding > 0) duration -= stream->codecpar->initial_padding;
    else duration -= codec->delay;
    if (stream->codecpar->trailing_padding > 0) duration -= stream->codecpar->trailing_padding;
    if (duration <= 0 || (uint64_t)duration > (UINT32_MAX - IPPCMHeaderLength) / (uint64_t)(channels * 2)) {
        av_packet_free(&packet); av_frame_free(&frame); swr_free(&resampler);
        avcodec_free_context(&codec); avformat_close_input(&format);
        if (_avio) { [self freeIOContext]; [_smb disconnect]; }
        [self setError:error code:EINVAL message:IPL(@"The source duration is missing or too large for a WAV stream.")];
        return NO;
    }
    _format = format; _codec = codec; _resampler = resampler; _packet = packet; _frame = frame;
    _streamIndex = streamIndex; _sampleRate = sampleRate; _channels = channels; _durationFrames = duration;
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    NSDictionary *keys = @{@"title":@"title", @"artist":@"artist", @"album":@"album", @"genre":@"genre", @"track":@"trackNumber"};
    for (NSString *key in keys) {
        AVDictionaryEntry *entry = av_dict_get(format->metadata, key.UTF8String, NULL, 0);
        if (!entry) entry = av_dict_get(stream->metadata, key.UTF8String, NULL, 0);
        if (!entry && [key isEqual:@"track"]) entry = av_dict_get(format->metadata, "tracknumber", NULL, 0);
        if (!entry && [key isEqual:@"track"]) entry = av_dict_get(stream->metadata, "tracknumber", NULL, 0);
        NSString *value = entry && entry->value ? [NSString stringWithUTF8String:entry->value] : nil;
        if (value.length) {
            if ([key isEqual:@"track"]) { if (value.integerValue > 0) tags[keys[key]] = @(value.integerValue); }
            else tags[keys[key]] = value;
        }
    }
    tags[@"duration"] = @((double)duration / sampleRate);
    for (unsigned int i = 0; i < format->nb_streams; i++) {
        AVStream *picture = format->streams[i];
        if ((picture->disposition & AV_DISPOSITION_ATTACHED_PIC) && picture->attached_pic.size > 0 && picture->attached_pic.size <= 16*1024*1024) {
            tags[@"artworkData"] = [NSData dataWithBytes:picture->attached_pic.data length:(NSUInteger)picture->attached_pic.size];
            break;
        }
    }
    @synchronized(self) { _metadata = [tags copy]; }
    _decodedFrame = 0; _targetFrame = 0; _seekBaseFrame = 0; _discardUntilFrame = 0; _demuxEOF = NO; _flushSent = NO; _decoderEOF = NO;
    [_pendingPCM setLength:0];
    _ready = YES;
    return YES;
}

- (void)closeDecoder {
    if (_packet) av_packet_free(&_packet);
    if (_frame) av_frame_free(&_frame);
    if (_resampler) swr_free(&_resampler);
    if (_codec) avcodec_free_context(&_codec);
    if (_format) avformat_close_input(&_format);
    [self freeIOContext];
    if (_smb) [_smb disconnect];
    _streamIndex = -1; _ready = NO;
}

- (int)readSMB:(uint8_t *)buffer length:(int)length {
    if (!_smb || length <= 0) return AVERROR(EINVAL);
    if ([self shouldInterrupt]) return AVERROR_EXIT;
    length = MIN(length, 64 * 1024);
    NSError *error = nil;
    NSData *data = [_smb read:_smbPath offset:(uint64_t)_smbOffset length:(NSUInteger)length error:&error];
    if (!data) return AVERROR(error.code > 0 ? (int)error.code : EIO);
    if (data.length == 0) return AVERROR_EOF;
    memcpy(buffer, data.bytes, data.length);
    _smbOffset += (int64_t)data.length;
    return (int)data.length;
}

- (int64_t)seekSMB:(int64_t)offset whence:(int)whence {
    if (!_smb || _smbSize > INT64_MAX) return AVERROR(EINVAL);
    if (whence & AVSEEK_SIZE) return (int64_t)_smbSize;
    whence &= ~AVSEEK_FORCE;
    int64_t target;
    if (whence == SEEK_SET) target = offset;
    else if (whence == SEEK_CUR) target = _smbOffset + offset;
    else if (whence == SEEK_END) target = (int64_t)_smbSize + offset;
    else return AVERROR(EINVAL);
    if (target < 0 || (uint64_t)target > _smbSize) return AVERROR(EINVAL);
    _smbOffset = target;
    return target;
}

- (NSURL *)start:(NSError **)error {
    if (error) *error = nil;
    @synchronized (self) {
        if (_running || _starting) {
            [self setError:error code:EBUSY message:IPL(@"PCM stream is already running or starting.")];
            return nil;
        }
        _starting = YES;
    }
    if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) return nil;
    BOOL opened = [self openDecoder:error];
    BOOL cancelled = [self shouldInterrupt];
    dispatch_semaphore_signal(_decodeLock);
    if (!opened || cancelled) {
        if (opened) [self closeDecoder];
        if (cancelled) [self setError:error code:ECANCELED message:IPL(@"PCM stream start was cancelled.")];
        @synchronized (self) { _starting = NO; }
        return nil;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { [self setError:error code:errno message:IPL(@"Could not create PCM listener.")]; [self closeDecoder]; @synchronized (self) { _starting = NO; } return nil; }
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address)); address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = 0;
    socklen_t addressLength = sizeof(address);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(fd, 4) < 0 || getsockname(fd, (struct sockaddr *)&address, &addressLength) < 0) {
        int saved = errno; close(fd); [self setError:error code:saved message:IPL(@"Could not start PCM listener.")]; [self closeDecoder]; @synchronized (self) { _starting = NO; } return nil;
    }
    @synchronized (self) {
        if (_interrupt) {
            close(fd);
            _starting = NO;
            [self closeDecoder];
            [self setError:error code:ECANCELED message:IPL(@"PCM stream start was cancelled.")];
            return nil;
        }
        _listenFD = fd; _running = YES; _starting = NO;
        _queue = dispatch_queue_create("com.iplayer935.pcm-http", DISPATCH_QUEUE_SERIAL);
    }
    dispatch_async(_queue, ^{ [self serveLoop]; });
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/audio.wav", ntohs(address.sin_port)]];
}

- (BOOL)preparePCM:(NSError **)error {
    if (error) *error = nil;
    @synchronized (self) {
        if (_running || _starting || _ready) {
            [self setError:error code:EBUSY message:IPL(@"PCM decoder is already prepared or running.")];
            return NO;
        }
        _starting = YES;
    }
    if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) {
        @synchronized (self) { _starting = NO; }
        [self setError:error code:EIO message:IPL(@"Could not lock the PCM decoder.")];
        return NO;
    }
    BOOL opened = [self openDecoder:error];
    dispatch_semaphore_signal(_decodeLock);
    @synchronized (self) {
        _starting = NO;
        if (opened && !_interrupt) { _running = YES; _pcmPrepared = YES; }
        else if (opened) opened = NO;
    }
    if (!opened) {
        if (error && !*error) [self setError:error code:ECANCELED message:IPL(@"PCM decoder preparation was cancelled.")];
        [self closePCM];
    }
    return opened;
}

- (NSData *)readPCMFrames:(uint32_t)frames error:(NSError **)error {
    if (error) *error = nil;
    if (!_pcmPrepared || ![self isRunning]) {
        [self setError:error code:EINVAL message:IPL(@"PCM decoder is not prepared.")];
        return nil;
    }
    if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) {
        [self setError:error code:EIO message:IPL(@"Could not lock the PCM decoder.")];
        return nil;
    }
    _lastReadError = 0;
    NSData *data = [self readFrames:frames error:error];
    if (error && *error) _lastReadError = (*error).code;
    dispatch_semaphore_signal(_decodeLock);
    return data;
}

- (BOOL)seekPCMFrame:(int64_t)frame error:(NSError **)error {
    if (error) *error = nil;
    if (!_pcmPrepared || ![self isRunning]) {
        [self setError:error code:EINVAL message:IPL(@"PCM decoder is not prepared.")];
        return NO;
    }
    if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) {
        [self setError:error code:EIO message:IPL(@"Could not lock the PCM decoder.")];
        return NO;
    }
    BOOL success = [self seekToFrame:frame error:error];
    if (error && *error) _lastReadError = (*error).code;
    dispatch_semaphore_signal(_decodeLock);
    return success;
}

- (void)closePCM {
    [self stop];
    if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) == 0) {
        [self closeDecoder];
        _pcmPrepared = NO;
        dispatch_semaphore_signal(_decodeLock);
    }
}

- (void)stop {
    int listener = -1, client = -1;
    @synchronized (self) {
        if (!_running && _listenFD < 0 && !_ready && !_starting) return;
        _running = NO; _interrupt = YES;
        listener = _listenFD; _listenFD = -1;
        client = _clientFD; _clientFD = -1;
    }
    if (client >= 0) shutdown(client, SHUT_RDWR);
    if (listener >= 0) { shutdown(listener, SHUT_RDWR); close(listener); }
}

- (BOOL)isRunning { @synchronized (self) { return _running; } }
- (BOOL)shouldInterrupt { @synchronized (self) { return _interrupt; } }

- (void)serveLoop {
    while ([self isRunning]) {
        int listener; @synchronized (self) { listener = _listenFD; }
        if (listener < 0) break;
        int client = accept(listener, NULL, NULL);
        if (client < 0) { if (![self isRunning]) break; if (errno == EINTR) continue; continue; }
        struct timeval timeout = {5, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        int noSignal = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        @synchronized (self) { if (!_running) { close(client); break; } _clientFD = client; }
        @autoreleasepool { [self handleClient:client]; [self finishActiveRequest]; }
        @synchronized (self) { if (_clientFD == client) _clientFD = -1; }
        close(client);
    }
    if (dispatch_semaphore_wait(_decodeLock, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0) {
        [self closeDecoder]; dispatch_semaphore_signal(_decodeLock);
    }
}

- (BOOL)writeData:(NSData *)data fd:(int)fd {
    const uint8_t *bytes = data.bytes; NSUInteger remaining = data.length;
    while (remaining && [self isRunning]) {
        ssize_t count = send(fd, bytes, remaining, 0);
        if (count < 0) { if (errno == EINTR) continue; @synchronized (self) { if (_activeRequest) _activeRequest[@"errorCode"] = @(errno); } return NO; }
        if (count == 0) return NO;
        @synchronized (self) { if (_activeRequest) _activeRequest[@"responseBytes"] = @([_activeRequest[@"responseBytes"] unsignedLongLongValue] + (uint64_t)count); }
        bytes += count; remaining -= (NSUInteger)count;
    }
    return remaining == 0;
}

- (void)sendStatus:(int)status reason:(NSString *)reason fd:(int)fd extra:(NSString *)extra {
    @synchronized (self) { if (_activeRequest) _activeRequest[@"status"] = @(status); }
    NSData *data = [[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nConnection: close\r\n%@\r\n", status, reason, extra ?: @""] dataUsingEncoding:NSASCIIStringEncoding];
    [self writeData:data fd:fd];
}

- (void)handleClient:(int)fd {
    uint8_t requestBytes[8192]; size_t used = 0; BOOL gotEnd = NO;
    while (used < sizeof(requestBytes) - 1 && [self isRunning]) {
        ssize_t n = recv(fd, requestBytes + used, sizeof(requestBytes) - 1 - used, 0);
        if (n < 0) { if (errno == EINTR) continue; return; }
        if (n == 0) return;
        used += (size_t)n; requestBytes[used] = 0;
        if (used >= 4 && strstr((char *)requestBytes, "\r\n\r\n")) { gotEnd = YES; break; }
    }
    if (!gotEnd) { [self sendStatus:400 reason:@"Bad Request" fd:fd extra:@"Content-Length: 0\r\n"]; return; }
    NSString *request = [[NSString alloc] initWithBytes:requestBytes length:used encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSArray *first = lines.count ? [lines[0] componentsSeparatedByString:@" "] : @[];
    NSString *method = first.count && ([first[0] isEqualToString:@"GET"] || [first[0] isEqualToString:@"HEAD"]) ? first[0] : @"OTHER";
    @synchronized (self) { _totalRequests++; _activeRequest = [@{@"method": method, @"rangeKind": @"none", @"rangeStart": @0, @"rangeEnd": @0, @"status": @0, @"responseBytes": @0, @"errorCode": @0, @"_startedAt": @(NSProcessInfo.processInfo.systemUptime)} mutableCopy]; }
    if (first.count < 2 || !([first[0] isEqualToString:@"GET"] || [first[0] isEqualToString:@"HEAD"])) {
        [self sendStatus:405 reason:@"Method Not Allowed" fd:fd extra:@"Allow: GET, HEAD\r\nContent-Length: 0\r\n"]; return;
    }
    if (![first[1] isEqualToString:@"/audio.wav"]) { [self sendStatus:404 reason:@"Not Found" fd:fd extra:@"Content-Length: 0\r\n"]; return; }
    BOOL headOnly = [first[0] isEqualToString:@"HEAD"];
    NSString *rangeHeader = nil;
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location != NSNotFound && [[[line substringToIndex:colon.location] lowercaseString] isEqualToString:@"range"])
            rangeHeader = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    uint64_t dataLength = (uint64_t)_durationFrames * (uint64_t)_channels * 2;
    uint64_t totalLength = dataLength + IPPCMHeaderLength;
    uint64_t start = 0, end = totalLength - 1;
    BOOL partial = NO;
    if (rangeHeader) {
        NSString *rangeKind = @"invalid";
        if ([rangeHeader hasPrefix:@"bytes="]) {
            NSString *spec = [rangeHeader substringFromIndex:6]; NSRange rangeDash = [spec rangeOfString:@"-"];
            if (rangeDash.location != NSNotFound && ![spec containsString:@","]) {
                NSString *rangeLeft = [spec substringToIndex:rangeDash.location], *rangeRight = [spec substringFromIndex:rangeDash.location + 1];
                if (!rangeLeft.length && rangeRight.length && strspn(rangeRight.UTF8String, "0123456789") == rangeRight.length) rangeKind = @"suffix";
                else if (rangeLeft.length && strspn(rangeLeft.UTF8String, "0123456789") == rangeLeft.length && (!rangeRight.length || strspn(rangeRight.UTF8String, "0123456789") == rangeRight.length)) rangeKind = rangeRight.length ? @"bounded" : @"open-ended";
            }
        }
        @synchronized (self) { if (_activeRequest) _activeRequest[@"rangeKind"] = rangeKind; }
        if (![rangeHeader hasPrefix:@"bytes="] || [rangeHeader containsString:@","] || totalLength == 0) {
            [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return;
        }
        NSString *spec = [rangeHeader substringFromIndex:6]; NSRange dash = [spec rangeOfString:@"-"];
        if (dash.location == NSNotFound) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return; }
        NSString *left = [spec substringToIndex:dash.location], *right = [spec substringFromIndex:dash.location + 1];
        if (left.length == 0) {
            uint64_t suffix = strtoull(right.UTF8String, NULL, 10);
            if (!suffix || !right.length || strspn(right.UTF8String, "0123456789") != right.length) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return; }
            start = suffix >= totalLength ? 0 : totalLength - suffix;
        } else {
            if (strspn(left.UTF8String, "0123456789") != left.length) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return; }
            start = strtoull(left.UTF8String, NULL, 10);
            if (right.length && strspn(right.UTF8String, "0123456789") != right.length) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return; }
            if (right.length) end = strtoull(right.UTF8String, NULL, 10);
        }
        if (start >= totalLength || end < start) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)totalLength]]; return; }
        if (end >= totalLength) end = totalLength - 1;
        partial = YES;
        @synchronized (self) { if (_activeRequest) { _activeRequest[@"rangeStart"] = @(start); _activeRequest[@"rangeEnd"] = @(end); } }
    }
    uint64_t length = end - start + 1;
    NSString *extra = partial
        ? [NSString stringWithFormat:@"Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: %llu\r\nContent-Range: bytes %llu-%llu/%llu\r\n", (unsigned long long)length, (unsigned long long)start, (unsigned long long)end, (unsigned long long)totalLength]
        : [NSString stringWithFormat:@"Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\nContent-Length: %llu\r\n", (unsigned long long)length];
    [self sendStatus:partial ? 206 : 200 reason:partial ? @"Partial Content" : @"OK" fd:fd extra:extra];
    if (headOnly) return;
    uint64_t cursor = start;
    while (cursor <= end && [self isRunning]) {
        if (cursor < IPPCMHeaderLength) {
            uint8_t header[44] = {0};
            memcpy(header, "RIFF", 4); IPPCMWriteLE32(header + 4, (uint32_t)(totalLength - 8));
            memcpy(header + 8, "WAVEfmt ", 8); IPPCMWriteLE32(header + 16, 16);
            IPPCMWriteLE16(header + 20, 1); IPPCMWriteLE16(header + 22, (uint16_t)_channels);
            IPPCMWriteLE32(header + 24, (uint32_t)_sampleRate); IPPCMWriteLE32(header + 28, (uint32_t)(_sampleRate * _channels * 2));
            IPPCMWriteLE16(header + 32, (uint16_t)(_channels * 2)); IPPCMWriteLE16(header + 34, 16);
            memcpy(header + 36, "data", 4); IPPCMWriteLE32(header + 40, (uint32_t)dataLength);
            size_t offset = (size_t)cursor, count = (size_t)MIN((uint64_t)(IPPCMHeaderLength - offset), end - cursor + 1);
            if (![self writeData:[NSData dataWithBytes:header + offset length:count] fd:fd]) return;
            cursor += count; continue;
        }
        int64_t firstFrame = (int64_t)((cursor - IPPCMHeaderLength) / ((uint64_t)_channels * 2));
        if (firstFrame != _targetFrame) {
            NSError *seekError = nil;
            if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) return;
            BOOL seekOK = [self seekToFrame:firstFrame error:&seekError];
            dispatch_semaphore_signal(_decodeLock);
            if (!seekOK) { @synchronized (self) { if (_activeRequest) _activeRequest[@"errorCode"] = @(seekError.code ?: EIO); } return; }
        }
        NSUInteger withinFrame = (NSUInteger)((cursor - IPPCMHeaderLength) % ((uint64_t)_channels * 2));
        uint64_t requestedBytes = end - cursor + 1;
        uint32_t frames = (uint32_t)MIN((uint64_t)IPPCMReadFrames, (requestedBytes + withinFrame + (uint64_t)_channels * 2 - 1) / ((uint64_t)_channels * 2));
        NSData *pcmData = nil; NSError *decodeError = nil;
        if (dispatch_semaphore_wait(_decodeLock, DISPATCH_TIME_FOREVER) != 0) return;
        pcmData = [self readFrames:frames error:&decodeError];
        dispatch_semaphore_signal(_decodeLock);
        if (!pcmData.length) { if (decodeError) @synchronized (self) { if (_activeRequest) _activeRequest[@"errorCode"] = @(decodeError.code ?: EIO); } return; }
        if (withinFrame >= pcmData.length) return;
        NSUInteger available = pcmData.length - withinFrame;
        NSUInteger toWrite = (NSUInteger)MIN((uint64_t)available, requestedBytes);
        NSData *slice = [pcmData subdataWithRange:NSMakeRange(withinFrame, toWrite)];
        if (![self writeData:slice fd:fd]) return;
        cursor += toWrite;
        _targetFrame = firstFrame + ((withinFrame + toWrite + (NSUInteger)(_channels * 2) - 1) / (NSUInteger)(_channels * 2));
    }
}

// Never enters FFmpeg 4.4's unsafe FLAC timestamp binary-seek implementation.
// Byte probes use the normal FLAC parser; decoded sample timestamps select a preceding frame.
- (BOOL)seekNativeFLACFrame:(int64_t)target {
    if(!_format->iformat||strcmp(_format->iformat->name,"flac")||!_format->pb||!(_format->pb->seekable&AVIO_SEEKABLE_NORMAL))return NO;
    int64_t size=avio_size(_format->pb);if(size<=0||_durationFrames<=0||target<(int64_t)_sampleRate*2)return NO;
    AVStream *stream=_format->streams[_streamIndex];
    int64_t low=0,high=size-1,lowFrame=0,highFrame=_durationFrames,bestPos=-1,bestFrame=0;
    _seekProbeCount=0;
    for(NSUInteger attempt=0;attempt<12&&high>low+1&&![self shouldInterrupt];attempt++){
        double ratio=(double)(target-lowFrame)/MAX((int64_t)1,highFrame-lowFrame);ratio=MAX(.05,MIN(.95,ratio));
        int64_t probe=low+(int64_t)((high-low)*ratio);
        // Bias toward a preceding frame to avoid decoding an entire prefix after the search.
        probe=MAX(low+1,MIN(high-1,probe-MIN((int64_t)32768,(high-low)/8)));
        if(av_seek_frame(_format,-1,probe,AVSEEK_FLAG_BYTE)<0)break;
        _seekProbeCount++;
        int64_t at=AV_NOPTS_VALUE,pos=-1;
        for(int packet=0;packet<16;packet++){
            if(av_read_frame(_format,_packet)<0)break;
            if(_packet->stream_index==_streamIndex&&_packet->pts!=AV_NOPTS_VALUE&&_packet->pos>=0){
                int64_t origin=stream->start_time==AV_NOPTS_VALUE?0:stream->start_time;
                at=av_rescale_q(_packet->pts-origin,stream->time_base,(AVRational){1,_sampleRate});pos=stream->parser?stream->parser->next_frame_offset-_packet->size:_packet->pos;

            }
            av_packet_unref(_packet);if(at!=AV_NOPTS_VALUE)break;
        }
        av_packet_unref(_packet);
        if(at==AV_NOPTS_VALUE||at<0||pos<0){high=probe;continue;}
        if(at<=target){
            if(bestPos<0||at>=bestFrame){bestPos=pos;bestFrame=at;}
            if(target-at<=_sampleRate*2)break;
            low=MAX(low+1,MAX(probe,pos));lowFrame=at;
        }else{high=probe;highFrame=at;}
    }
    if(bestPos<0||bestFrame==0||[self shouldInterrupt]||av_seek_frame(_format,-1,bestPos,AVSEEK_FLAG_BYTE)<0)return NO;
    avcodec_flush_buffers(_codec);swr_close(_resampler);if(swr_init(_resampler)<0)return NO;
    _decodedFrame=bestFrame;_seekBaseFrame=bestFrame;_targetFrame=target;_discardUntilFrame=0;
    _demuxEOF=NO;_flushSent=NO;_decoderEOF=NO;[_pendingPCM setLength:0];_seekMode=@"flac-byte-probe";
    return YES;
}

- (BOOL)seekToFrame:(int64_t)frame error:(NSError **)error {
    if (frame < 0 || frame > _durationFrames) return NO;
    enum AVCodecID codecID = _format->streams[_streamIndex]->codecpar->codec_id;
    AVStream *stream = _format->streams[_streamIndex];
    BOOL noUsableIndex = stream->nb_index_entries == 0;
    if(codecID==AV_CODEC_ID_FLAC&&[self seekNativeFLACFrame:frame])return YES;
    _seekMode=@"sequential-fallback";
    if (codecID == AV_CODEC_ID_VORBIS || codecID == AV_CODEC_ID_OPUS || codecID == AV_CODEC_ID_FLAC || noUsableIndex) {
        /* Timestamp metadata can be inaccurate, and FFmpeg 4.4 binary-seek crashes on these sources. Reopen and decode forward. */
        [self closeDecoder];
        if (![self openDecoder:error]) return NO;
        _decodedFrame = 0; _seekBaseFrame = 0; _targetFrame = frame; _discardUntilFrame = 0;
        [_pendingPCM setLength:0];
        return YES;
    }
    int64_t startTime = _format->streams[_streamIndex]->start_time;
    int64_t preroll = MIN(frame, (int64_t)_sampleRate * 5);
    int64_t seekFrame = frame - preroll;
    int64_t timestamp = (startTime == AV_NOPTS_VALUE ? 0 : startTime) + av_rescale_q(seekFrame, (AVRational){1, _sampleRate}, _format->streams[_streamIndex]->time_base);
    if (av_seek_frame(_format, _streamIndex, timestamp, AVSEEK_FLAG_BACKWARD) < 0) {
        [self closeDecoder];
        if (![self openDecoder:error]) return NO;
        _decodedFrame = 0; _seekBaseFrame = 0; _targetFrame = frame; _discardUntilFrame = 0;
        [_pendingPCM setLength:0];
        return YES;
    }
    avcodec_flush_buffers(_codec); swr_close(_resampler); swr_init(_resampler);
    _decodedFrame = seekFrame; _seekBaseFrame = seekFrame; _targetFrame = frame; _discardUntilFrame = frame; _demuxEOF = NO; _flushSent = NO; _decoderEOF = NO;
    [_pendingPCM setLength:0];
    return YES;
}

- (NSData *)readFrames:(uint32_t)frames error:(NSError **)error {
    if (frames == 0) return [NSData data];
    uint64_t maxBytes = (uint64_t)frames * (uint64_t)_channels * 2;
    NSMutableData *output = [NSMutableData dataWithLength:(NSUInteger)maxBytes];
    NSUInteger outputLength = 0;
    while (outputLength < maxBytes && [self isRunning]) {
        if (_pendingPCM.length > 0) {
            NSUInteger count = MIN((NSUInteger)maxBytes - outputLength, _pendingPCM.length);
            memcpy((uint8_t *)output.mutableBytes + outputLength, _pendingPCM.bytes, count);
            outputLength += count;
            if (count == _pendingPCM.length) [_pendingPCM setLength:0];
            else [_pendingPCM replaceBytesInRange:NSMakeRange(0, count) withBytes:NULL length:0];
            _targetFrame += count / (NSUInteger)(_channels * 2);
            continue;
        }
        int rc = avcodec_receive_frame(_codec, _frame);
        if (rc == 0) {
            if (_discardUntilFrame > 0) {
                int64_t pts = _frame->best_effort_timestamp;
                int64_t decodedAt = pts != AV_NOPTS_VALUE && _format->streams[_streamIndex]->start_time != AV_NOPTS_VALUE
                    ? av_rescale_q(pts - _format->streams[_streamIndex]->start_time, _format->streams[_streamIndex]->time_base, (AVRational){1, _sampleRate})
                    : _decodedFrame;
                if (decodedAt < 0) decodedAt = 0;
                int64_t decodedEnd = decodedAt + _frame->nb_samples;
                _decodedFrame = decodedEnd;
                if (decodedEnd <= _discardUntilFrame) { av_frame_unref(_frame); continue; }
                _discardUntilFrame = 0;
                /* Keep this overlapping frame: the main decode path skips exactly to the target sample. */
            }
            int64_t pts = _frame->best_effort_timestamp;
            BOOL sequentialCodec = _format->streams[_streamIndex]->codecpar->codec_id == AV_CODEC_ID_VORBIS ||
                                   _format->streams[_streamIndex]->codecpar->codec_id == AV_CODEC_ID_OPUS;
            int64_t frameStart = sequentialCodec ? _decodedFrame : (pts != AV_NOPTS_VALUE && _format->streams[_streamIndex]->start_time != AV_NOPTS_VALUE
                ? av_rescale_q(pts - _format->streams[_streamIndex]->start_time, _format->streams[_streamIndex]->time_base, (AVRational){1, _sampleRate})
                : _decodedFrame);
            if (frameStart < 0) frameStart = 0;
            int64_t frameEnd = frameStart + _frame->nb_samples;
            int64_t wanted = _targetFrame;
            if (frameEnd <= wanted) { _decodedFrame = frameEnd; av_frame_unref(_frame); continue; }
            int skip = (int)MAX((int64_t)0, wanted - frameStart);
            int samples = _frame->nb_samples - skip;
            int maxOut = samples;
            if (maxOut <= 0) { av_frame_unref(_frame); continue; }
            NSMutableData *convertedData = [NSMutableData dataWithLength:(NSUInteger)maxOut * (NSUInteger)_channels * 2];
            uint8_t *planes[1] = {convertedData.mutableBytes};
            int planar = av_sample_fmt_is_planar(_codec->sample_fmt);
            int bytesPerSample = av_get_bytes_per_sample(_codec->sample_fmt);
            int inputChannels = _channels;
#if LIBAVUTIL_VERSION_MAJOR >= 57
            inputChannels = _frame->ch_layout.nb_channels;
#else
            inputChannels = _codec->channels;
#endif
            if (inputChannels < 1 || inputChannels > 16) { av_frame_unref(_frame); [self setError:error code:EINVAL message:IPL(@"The source has an unsupported channel count.")]; return nil; }
            const uint8_t **input = (const uint8_t **)av_malloc_array((size_t)(planar ? inputChannels : 1), sizeof(uint8_t *));
            if (!input) { av_frame_unref(_frame); [self setError:error code:ENOMEM message:IPL(@"Could not convert decoded audio.")]; return nil; }
            for (int c = 0; c < (planar ? inputChannels : 1); c++) input[c] = _frame->extended_data[c] + (planar ? skip : skip * inputChannels) * bytesPerSample;
            int converted = swr_convert(_resampler, planes, maxOut, input, samples);
            av_free(input);
            if (converted > 0) {
                [convertedData setLength:(NSUInteger)converted * (NSUInteger)_channels * 2];
                [_pendingPCM appendData:convertedData];
            }
            _decodedFrame = frameEnd;
            av_frame_unref(_frame);
            continue;
        }
        if (rc == AVERROR_EOF) { _decoderEOF = YES; break; }
        if (rc != AVERROR(EAGAIN)) { _lastReadError = -rc; [self setError:error code:-rc message:IPL(@"Audio decoding failed.")]; return nil; }
        if (_demuxEOF) {
            if (!_flushSent) { avcodec_send_packet(_codec, NULL); _flushSent = YES; continue; }
            break;
        }
        rc = av_read_frame(_format, _packet);
        if (rc < 0) { _demuxEOF = YES; av_packet_unref(_packet); continue; }
        if (_packet->stream_index == _streamIndex) avcodec_send_packet(_codec, _packet);
        av_packet_unref(_packet);
    }
    [output setLength:outputLength];
    return output;
}

- (void)dealloc { [self stop]; }

@end

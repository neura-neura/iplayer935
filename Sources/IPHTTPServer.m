#import "IPStrings.h"
#import "IPHTTPServer.h"
#import "IPSMB.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static NSString * const IPHTTPErrorDomain = @"IPHTTPServerErrorDomain";

@interface IPHTTPServer () {
    NSDictionary *_profile;
    NSString *_password;
    NSString *_path;
    uint64_t _size;
    NSString *_urlPath;
    NSString *_mimeType;
    IPSMB *_smb;
    int _listenFD;
    int _clientFD;
    BOOL _running;
    dispatch_queue_t _queue;
}
- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message;
- (BOOL)isRunning;
- (void)serveLoop;
- (void)handleClient:(int)fd;
- (void)sendStatus:(int)status reason:(NSString *)reason fd:(int)fd extra:(NSString *)extra;
- (BOOL)writeData:(NSData *)data fd:(int)fd;
- (BOOL)parseUInt64:(NSString *)text value:(uint64_t *)value;
@end

@implementation IPHTTPServer

- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password path:(NSString *)path size:(uint64_t)size {
    self = [super init];
    if (self) {
        _profile = [profile copy] ?: @{};
        _password = [password copy] ?: @"";
        _path = [path copy] ?: @"";
        _size = size;
        NSDictionary *types = @{@"mp3": @"audio/mpeg", @"m4a": @"audio/mp4", @"mp4": @"audio/mp4",
                               @"aac": @"audio/aac", @"wav": @"audio/wav", @"wave": @"audio/wav",
                               @"caf": @"audio/x-caf", @"m4b": @"audio/mp4",
                               @"flac": @"audio/flac", @"ogg": @"audio/ogg", @"oga": @"audio/ogg",
                               @"aiff": @"audio/aiff", @"aif": @"audio/aiff"};
        NSString *extension = _path.pathExtension.lowercaseString;
        _mimeType = types[extension] ?: @"application/octet-stream";
        _urlPath = types[extension] ? [@"/audio." stringByAppendingString:extension] : @"/audio";
        _listenFD = -1;
        _clientFD = -1;
    }
    return self;
}

- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:IPHTTPErrorDomain code:code
                                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSURL *)start:(NSError **)error {
    @synchronized (self) {
        if (_running) {
            struct sockaddr_in addr; socklen_t len = sizeof(addr);
            if (getsockname(_listenFD, (struct sockaddr *)&addr, &len) == 0)
                return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@", ntohs(addr.sin_port), _urlPath]];
        }
        if (_smb != nil) {
            [self setError:error code:EBUSY message:IPL(@"The previous stream server is still stopping.")];
            return nil;
        }
    }
    _smb = [[IPSMB alloc] initWithProfile:_profile password:_password];
    NSError *smbError = nil;
    if (![_smb connect:&smbError]) {
        [self setError:error code:smbError.code message:IPL(@"Could not connect to the SMB source.")];
        _smb = nil;
        return nil;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        [_smb disconnect];
        _smb = nil;
        [self setError:error code:errno message:IPL(@"Could not create loopback listener.")];
        return nil;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    socklen_t addrLength = sizeof(addr);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(fd, 4) < 0 || getsockname(fd, (struct sockaddr *)&addr, &addrLength) < 0) {
        int saved = errno;
        close(fd);
        [_smb disconnect];
        _smb = nil;
        [self setError:error code:saved message:IPL(@"Could not start loopback listener.")];
        return nil;
    }
    @synchronized (self) {
        _listenFD = fd;
        _running = YES;
        _queue = dispatch_queue_create("com.iplayer935.http-range", DISPATCH_QUEUE_SERIAL);
    }
    dispatch_async(_queue, ^{ [self serveLoop]; });
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@", ntohs(addr.sin_port), _urlPath]];
}

- (void)stop {
    int listener = -1, client = -1;
    @synchronized (self) {
        if (!_running && _listenFD < 0) return;
        _running = NO;
        listener = _listenFD; _listenFD = -1;
        client = _clientFD; _clientFD = -1;
    }
    if (client >= 0) shutdown(client, SHUT_RDWR);
    if (listener >= 0) { shutdown(listener, SHUT_RDWR); close(listener); }
}

- (BOOL)isRunning {
    @synchronized (self) { return _running; }
}

- (void)serveLoop {
    while ([self isRunning]) {
        int listener;
        @synchronized (self) { listener = _listenFD; }
        if (listener < 0) break;
        int client = accept(listener, NULL, NULL);
        if (client < 0) { if (![self isRunning]) break; if (errno == EINTR) continue; continue; }
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        struct timeval sendTimeout = {5, 0};
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, sizeof(sendTimeout));
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        @synchronized (self) { if (!_running) { close(client); break; } _clientFD = client; }
        @autoreleasepool { [self handleClient:client]; }
        @synchronized (self) { if (_clientFD == client) _clientFD = -1; }
        close(client);
    }
    @synchronized (self) {
        [_smb disconnect];
        _smb = nil;
    }
}

- (void)sendStatus:(int)status reason:(NSString *)reason fd:(int)fd extra:(NSString *)extra {
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nConnection: close\r\n%@\r\n", status, reason, extra ?: @""];
    NSData *data = [head dataUsingEncoding:NSASCIIStringEncoding];
    [self writeData:data fd:fd];
}

- (BOOL)writeData:(NSData *)data fd:(int)fd {
    const uint8_t *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left > 0 && [self isRunning]) {
        ssize_t n = send(fd, bytes, left, 0);
        if (n < 0) { if (errno == EINTR) continue; return NO; }
        if (n == 0) return NO;
        bytes += n; left -= (NSUInteger)n;
    }
    return left == 0;
}

- (BOOL)parseUInt64:(NSString *)text value:(uint64_t *)value {
    if (text.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if ([text rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return NO;
    const char *s = text.UTF8String;
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(s, &end, 10);
    if (errno || !end || *end != '\0') return NO;
    *value = (uint64_t)parsed;
    return YES;
}

- (void)handleClient:(int)fd {
    NSMutableData *requestData = [NSMutableData data];
    uint8_t buf[1024];
    BOOL complete = NO;
    while ([self isRunning] && requestData.length < 16384) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n < 0) { if (errno == EINTR) continue; return; }
        if (n == 0) return;
        [requestData appendBytes:buf length:(NSUInteger)n];
        if (requestData.length >= 4) {
            const char *s = requestData.bytes;
            NSUInteger length = requestData.length;
            for (NSUInteger i = 3; i < length; i++) if (s[i-3] == '\r' && s[i-2] == '\n' && s[i-1] == '\r' && s[i] == '\n') { complete = YES; break; }
        }
        if (complete) break;
    }
    if (!complete) { [self sendStatus:400 reason:@"Bad Request" fd:fd extra:@"Content-Length: 0\r\n"]; return; }
    NSString *request = [[NSString alloc] initWithData:requestData encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSArray *first = lines.count ? [lines[0] componentsSeparatedByString:@" "] : @[];
    if (first.count < 2 || (![first[0] isEqualToString:@"GET"] && ![first[0] isEqualToString:@"HEAD"])) {
        [self sendStatus:405 reason:@"Method Not Allowed" fd:fd extra:@"Allow: GET, HEAD\r\nContent-Length: 0\r\n"]; return;
    }
    if (![first[1] isEqualToString:_urlPath]) {
        [self sendStatus:404 reason:@"Not Found" fd:fd extra:@"Content-Length: 0\r\n"]; return;
    }
    BOOL headOnly = [first[0] isEqualToString:@"HEAD"];
    NSString *rangeHeader = nil;
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:colon.location] lowercaseString];
        if ([key isEqualToString:@"range"]) rangeHeader = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    uint64_t start = 0, end = _size ? _size - 1 : 0;
    BOOL partial = NO;
    if (rangeHeader) {
        if (![rangeHeader hasPrefix:@"bytes="] || [rangeHeader rangeOfString:@","].location != NSNotFound || _size == 0) {
            [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return;
        }
        NSString *spec = [rangeHeader substringFromIndex:6];
        NSRange dash = [spec rangeOfString:@"-"];
        if (dash.location == NSNotFound) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return; }
        NSString *left = [spec substringToIndex:dash.location];
        NSString *right = [spec substringFromIndex:dash.location + 1];
        if (left.length == 0) {
            uint64_t suffix;
            if (![self parseUInt64:right value:&suffix] || suffix == 0) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return; }
            start = suffix >= _size ? 0 : _size - suffix;
            end = _size - 1;
        } else if (![self parseUInt64:left value:&start]) {
            [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return;
        }
        if (start >= _size) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return; }
        if (left.length > 0 && right.length > 0) {
            if (![self parseUInt64:right value:&end] || end < start) { [self sendStatus:416 reason:@"Range Not Satisfiable" fd:fd extra:[NSString stringWithFormat:@"Content-Range: bytes */%llu\r\nContent-Length: 0\r\n", (unsigned long long)_size]]; return; }
            if (end >= _size) end = _size - 1;
        } else end = _size - 1;
        partial = YES;
    }
    uint64_t remaining = _size ? end - start + 1 : 0;
    NSString *extra = partial
        ? [NSString stringWithFormat:@"Accept-Ranges: bytes\r\nContent-Type: %@\r\nContent-Length: %llu\r\nContent-Range: bytes %llu-%llu/%llu\r\n", _mimeType, (unsigned long long)remaining, (unsigned long long)start, (unsigned long long)end, (unsigned long long)_size]
        : [NSString stringWithFormat:@"Accept-Ranges: bytes\r\nContent-Type: %@\r\nContent-Length: %llu\r\n", _mimeType, (unsigned long long)remaining];
    [self sendStatus:partial ? 206 : 200 reason:partial ? @"Partial Content" : @"OK" fd:fd extra:extra];
    if (headOnly) return;
    while (remaining > 0 && [self isRunning]) {
        BOOL shouldContinue = YES;
        @autoreleasepool {
            NSUInteger chunk = (NSUInteger)MIN((uint64_t)(64 * 1024), remaining);
            NSError *readError = nil;
            NSData *data = [_smb read:_path offset:start length:chunk error:&readError];
            if (!data || data.length == 0 || data.length > remaining) {
                shouldContinue = NO;
            } else if (![self writeData:data fd:fd]) {
                shouldContinue = NO;
            } else {
                start += data.length;
                remaining -= data.length;
                if (data.length < chunk) shouldContinue = NO;
            }
        }
        if (!shouldContinue) break;
    }
}

- (void)dealloc { [self stop]; }

@end

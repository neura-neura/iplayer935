#import <Foundation/Foundation.h>
#import "../Sources/IPPCMServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static NSData *IPPCMRequest(NSURL *url, NSString *method, NSString *range) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    NSCAssert(fd >= 0, @"socket failed");
    int noSignal = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address)); address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)url.port.integerValue); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    NSCAssert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0, @"connect failed");
    NSString *rangeLine = range ? [NSString stringWithFormat:@"Range: %@\r\n", range] : @"";
    NSData *request = [[NSString stringWithFormat:@"%@ /audio.wav HTTP/1.1\r\nHost: 127.0.0.1\r\n%@Connection: close\r\n\r\n", method, rangeLine] dataUsingEncoding:NSASCIIStringEncoding];
    const uint8_t *bytes = request.bytes; NSUInteger remain = request.length;
    while (remain) { ssize_t n = send(fd, bytes, remain, 0); NSCAssert(n > 0, @"send failed"); bytes += n; remain -= (NSUInteger)n; }
    NSMutableData *response = [NSMutableData data]; uint8_t buffer[8192]; ssize_t n;
    while ((n = recv(fd, buffer, sizeof(buffer), 0)) > 0) [response appendBytes:buffer length:(NSUInteger)n];
    close(fd);
    return response;
}

static NSData *IPPCMRequestRange(NSURL *url, uint64_t start, uint64_t end) {
    int fd = socket(AF_INET, SOCK_STREAM, 0); NSCAssert(fd >= 0, @"socket failed");
    int noSignal = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    struct sockaddr_in address = {0}; address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)url.port.integerValue); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    NSCAssert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0, @"connect failed");
    NSString *requestText = [NSString stringWithFormat:@"GET /audio.wav HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=%llu-%llu\r\nConnection: close\r\n\r\n", (unsigned long long)start, (unsigned long long)end];
    NSData *request = [requestText dataUsingEncoding:NSASCIIStringEncoding];
    send(fd, request.bytes, request.length, 0);
    NSMutableData *response = [NSMutableData data]; uint8_t buffer[8192]; ssize_t n;
    while ((n = recv(fd, buffer, sizeof(buffer), 0)) > 0) [response appendBytes:buffer length:(NSUInteger)n];
    close(fd);
    return response;
}

static NSData *IPBody(NSData *response, NSInteger status) {
    NSString *head = [[NSString alloc] initWithData:response encoding:NSISOLatin1StringEncoding];
    NSCAssert(([head hasPrefix:[NSString stringWithFormat:@"HTTP/1.1 %ld", (long)status]]), @"unexpected HTTP status: %@", [head substringToIndex:MIN(head.length, (NSUInteger)100)]);
    NSRange separator = [head rangeOfString:@"\r\n\r\n"];
    NSCAssert(separator.location != NSNotFound, @"missing HTTP headers");
    return [response subdataWithRange:NSMakeRange(NSMaxRange(separator), response.length - NSMaxRange(separator))];
}

static uint32_t IPReadLE32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static void IPCheckFixture(NSString *path, BOOL useSMB) {
    IPPCMServer *server = useSMB
        ? [[IPPCMServer alloc] initWithProfile:@{@"fixturePath": path} password:@"unused" path:path.lastPathComponent size:0]
        : [[IPPCMServer alloc] initWithURL:[NSURL fileURLWithPath:path]];
    NSError *error = nil;
    NSURL *url = [server start:&error];
    NSCAssert(url && !error, @"could not start decoder for %@: %@", path.lastPathComponent, error);
    NSData *fullResponse = IPPCMRequest(url, @"GET", nil);
    NSData *full = IPBody(fullResponse, 200);
    NSCAssert(full.length > 44 + 4000, @"decoded output too short for %@ (%lu bytes)", path.lastPathComponent, (unsigned long)full.length);
    const uint8_t *wav = full.bytes;
    NSCAssert(memcmp(wav, "RIFF", 4) == 0 && memcmp(wav + 8, "WAVEfmt ", 8) == 0 && memcmp(wav + 36, "data", 4) == 0, @"invalid WAV header for %@", path.lastPathComponent);
    uint32_t expectedRate = [path.lastPathComponent isEqualToString:@"tone.opus"] ? 48000 : 44100;
    NSCAssert(IPReadLE32(wav + 24) == expectedRate && IPReadLE32(wav + 40) + 44 == full.length, @"incorrect WAV metadata for %@: rate=%u declared=%u actual=%lu", path.lastPathComponent, IPReadLE32(wav + 24), IPReadLE32(wav + 40), (unsigned long)full.length);

    NSUInteger channels = (NSUInteger)wav[22] | ((NSUInteger)wav[23] << 8);
    NSUInteger bytesPerFrame = channels * 2;
    NSUInteger targetFrame = useSMB
        ? (full.length - 44) / bytesPerFrame - 1000
        : MIN((NSUInteger)expectedRate * 6, (full.length - 44) / bytesPerFrame - 1000);
    NSUInteger offset = 44 + targetFrame * bytesPerFrame + 1;
    NSUInteger count = 1023;
    NSString *range = [NSString stringWithFormat:@"bytes=%lu-%lu", (unsigned long)offset, (unsigned long)(offset + count - 1)];
    NSData *rangeBody = IPBody(IPPCMRequest(url, @"GET", range), 206);
    NSCAssert(rangeBody.length == count, @"incorrect seek response length for %@ (%lu)", path.lastPathComponent, (unsigned long)rangeBody.length);
    const uint8_t *seekBytes = rangeBody.bytes, *fullBytes = (const uint8_t *)full.bytes + offset;
    if (memcmp(seekBytes, fullBytes, count) != 0) {
        NSUInteger mismatch = 0; while (mismatch < count && seekBytes[mismatch] == fullBytes[mismatch]) mismatch++;
        fprintf(stderr, "seek mismatch %s at range byte %lu: %u != %u; seek %02x%02x%02x%02x full %02x%02x%02x%02x\n", path.lastPathComponent.UTF8String, (unsigned long)mismatch, seekBytes[mismatch], fullBytes[mismatch], seekBytes[0],seekBytes[1],seekBytes[2],seekBytes[3],fullBytes[0],fullBytes[1],fullBytes[2],fullBytes[3]);
        NSCAssert(NO, @"seeked PCM differs from full decode for %@", path.lastPathComponent);
    }
    NSData *headBody = IPBody(IPPCMRequest(url, @"HEAD", nil), 200);
    NSCAssert(headBody.length == 0, @"HEAD sent a body");
    [server stop];
    fprintf(stdout, "decoded and seek-checked %s (%s source)\n", path.lastPathComponent.UTF8String, useSMB ? "mock SMB" : "file URL");
}

static void IPCheckLongSMBFixture(NSString *path) {
    IPPCMServer *server = [[IPPCMServer alloc] initWithProfile:@{@"fixturePath": path} password:@"unused" path:path.lastPathComponent size:0];
    NSError *error = nil; NSURL *url = [server start:&error];
    NSCAssert(url && !error, @"could not start long mock-SMB source: %@", error);
    uint64_t frames = 240ULL * 44100ULL;
    uint64_t start = 44 + (frames - 512) * 2;
    NSData *response = IPPCMRequestRange(url, start, start + 1023);
    NSString *head = [[NSString alloc] initWithData:response encoding:NSISOLatin1StringEncoding];
    NSRange separator = [head rangeOfString:@"\r\n\r\n"];
    NSCAssert(separator.location != NSNotFound && [head hasPrefix:@"HTTP/1.1 206"], @"long SMB near-tail range failed: %@", [head substringToIndex:MIN(head.length, 100)]);
    NSData *body = [response subdataWithRange:NSMakeRange(NSMaxRange(separator), response.length - NSMaxRange(separator))];
    NSCAssert(body.length == 1024, @"long SMB near-tail range returned %lu bytes", (unsigned long)body.length);
    NSDictionary *snapshot = [server diagnosticSnapshot]; NSArray *requests = snapshot[@"requests"];
    NSDictionary *last = requests.lastObject;
    NSCAssert([last[@"rangeStart"] unsignedLongLongValue] == start && [last[@"rangeEnd"] unsignedLongLongValue] == start + 1023,
              @"near-tail request diagnostics did not retain numeric range: %@", last);
    [server stop];
    fprintf(stdout, "served a near-tail range from a 240-second mock-SMB FLAC\n");
}

static void IPCheckDirectDecoderLongSMB(NSString *path) {
    IPPCMServer *decoder = [[IPPCMServer alloc] initWithProfile:@{@"fixturePath": path} password:@"unused" path:path.lastPathComponent size:0];
    NSError *error = nil;
    NSCAssert([decoder preparePCM:&error] && !error, @"direct SMB decoder prepare failed: %@", error);
    NSData *initial = [decoder readPCMFrames:4096 error:&error];
    NSCAssert(initial.length == 8192 && !error, @"direct SMB decoder initial read failed: %@", error);
    NSDictionary *snapshot = [decoder diagnosticSnapshot];
    int64_t tailFrame = [snapshot[@"durationFrames"] longLongValue] - 512;
    NSCAssert([decoder seekPCMFrame:tailFrame error:&error] && !error, @"direct SMB decoder seek failed: %@", error);
    NSData *tail = [decoder readPCMFrames:512 error:&error];
    NSCAssert(tail.length == 1024 && !error, @"direct SMB decoder returned short tail (%lu), snapshot %@, error %@", (unsigned long)tail.length, [decoder diagnosticSnapshot], error);
    snapshot = [decoder diagnosticSnapshot];
    NSCAssert([snapshot[@"lastReadError"] integerValue] == 0, @"direct SMB decoder recorded an error: %@", snapshot);
    [decoder closePCM];
    fprintf(stdout, "direct PCM decoder read and sought to the end of 240-second mock-SMB FLAC\n");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"usage: pcm-host-tests fixture-directory");
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        IPPCMServer *tagged = [[IPPCMServer alloc] initWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"tagged.flac"]]];
        NSError *tagError = nil;
        NSCAssert([tagged preparePCM:&tagError], @"tagged FLAC failed to open %@", tagError);
        NSDictionary *tags = tagged.metadata;
        NSCAssert([tags[@"title"] isEqual:@"Prueba FLAC"] && [tags[@"artist"] isEqual:@"Árbol"] && [tags[@"album"] isEqual:@"Álbum"], @"FLAC UTF8 tags missing %@", tags);
        NSCAssert([tags[@"trackNumber"] integerValue] == 3 && [tags[@"artworkData"] length] > 0, @"FLAC track number or cover missing");
        [tagged closePCM];
        for (NSString *name in @[@"tone.flac", @"tone.ogg", @"tone.opus"])
            IPCheckFixture([dir stringByAppendingPathComponent:name], NO);
        IPCheckFixture([dir stringByAppendingPathComponent:@"tone.flac"], YES);
        IPCheckLongSMBFixture([dir stringByAppendingPathComponent:@"long-tone.flac"]);
        IPCheckDirectDecoderLongSMB([dir stringByAppendingPathComponent:@"long-tone.flac"]);
    }
    return 0;
}

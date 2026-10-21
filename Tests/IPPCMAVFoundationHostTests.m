#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import "../Sources/IPPCMServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static NSData *IPPCMReadURL(NSURL *url) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    NSCAssert(fd >= 0, @"socket failed");
    struct sockaddr_in address = {0}; address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)url.port.integerValue); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    NSCAssert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0, @"connect failed");
    NSData *request = [@"GET /audio.wav HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    send(fd, request.bytes, request.length, 0);
    NSMutableData *response = [NSMutableData data]; uint8_t buffer[8192]; ssize_t n;
    while ((n = recv(fd, buffer, sizeof(buffer), 0)) > 0) [response appendBytes:buffer length:(NSUInteger)n];
    close(fd);
    NSString *headers = [[NSString alloc] initWithData:response encoding:NSISOLatin1StringEncoding];
    NSRange separator = [headers rangeOfString:@"\r\n\r\n"];
    NSCAssert(separator.location != NSNotFound && [headers hasPrefix:@"HTTP/1.1 200"], @"invalid WAV response");
    return [response subdataWithRange:NSMakeRange(NSMaxRange(separator), response.length - NSMaxRange(separator))];
}

static NSDictionary *IPLoadAsset(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    NSArray *keys = @[@"playable", @"duration", @"tracks"];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{ dispatch_semaphore_signal(done); }];
    NSCAssert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) == 0, @"AVURLAsset load timed out");
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:key error:&error];
        result[[key stringByAppendingString:@"Status"]] = @(status);
        if (error) result[[key stringByAppendingString:@"ErrorCode"]] = @(error.code);
    }
    result[@"playable"] = @(asset.playable);
    result[@"durationSeconds"] = @(CMTimeGetSeconds(asset.duration));
    result[@"audioTrackCount"] = @([[asset tracksWithMediaType:AVMediaTypeAudio] count]);
    return result;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"usage: pcm-avfoundation-tests fixture.flac");
        NSString *sourcePath = [NSString stringWithUTF8String:argv[1]];
        IPPCMServer *server = [[IPPCMServer alloc] initWithProfile:@{@"fixturePath": sourcePath} password:@"unused" path:[sourcePath lastPathComponent] size:0];
        NSError *error = nil; NSURL *streamURL = [server start:&error];
        NSCAssert(streamURL && !error, @"could not start PCM stream: %@", error);
        NSDictionary *streamResult = IPLoadAsset(streamURL);
        NSData *wav = IPPCMReadURL(streamURL);
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".wav"]];
        NSCAssert([wav writeToFile:wavPath atomically:YES], @"could not write local WAV probe");
        NSDictionary *fileResult = IPLoadAsset([NSURL fileURLWithPath:wavPath]);
        NSDictionary *diagnostics = [server diagnosticSnapshot];
        fprintf(stdout, "stream asset: %s\nlocal WAV asset: %s\nbridge: %s\n",
                [[streamResult description] UTF8String], [[fileResult description] UTF8String], [[diagnostics description] UTF8String]);
        NSCAssert([streamResult[@"playable"] boolValue] && [streamResult[@"audioTrackCount"] unsignedIntegerValue] == 1,
                  @"AVFoundation rejected loopback WAV: %@; bridge %@", streamResult, diagnostics);
        NSCAssert([fileResult[@"playable"] boolValue] && [fileResult[@"audioTrackCount"] unsignedIntegerValue] == 1,
                  @"AVFoundation rejected local WAV: %@", fileResult);
        NSCAssert(fabs([streamResult[@"durationSeconds"] doubleValue] - [fileResult[@"durationSeconds"] doubleValue]) < 0.01,
                  @"stream and local durations differ: %@ vs %@", streamResult, fileResult);
        [server stop]; [[NSFileManager defaultManager] removeItemAtPath:wavPath error:NULL];
    }
    return 0;
}

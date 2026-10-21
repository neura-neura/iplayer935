#import <Foundation/Foundation.h>
#import "../Sources/IPHTTPServer.h"
#import "../Sources/IPSMB.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

@implementation IPSMB
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password { return [super init]; }
- (BOOL)connect:(NSError **)error { return YES; }
- (NSArray *)list:(NSString *)path error:(NSError **)error { return @[]; }
- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    NSData *source = [@"0123456789" dataUsingEncoding:NSUTF8StringEncoding];
    if (offset >= source.length) return [NSData data];
    NSUInteger count = MIN(length, source.length - (NSUInteger)offset);
    return [source subdataWithRange:NSMakeRange((NSUInteger)offset, count)];
}
- (uint64_t)size:(NSString *)path error:(NSError **)error { return 10; }
- (void)disconnect {}
@end

static NSData *IPRequest(NSURL *url, NSString *method, NSString *range) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    NSCAssert(fd >= 0, @"socket failed");
    int noSignal = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)url.port.integerValue);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    NSCAssert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0, @"connect failed");
    NSString *request = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: 127.0.0.1\r\n%@Connection: close\r\n\r\n", method, url.path, range.length ? [NSString stringWithFormat:@"Range: %@\r\n", range] : @""];
    NSData *requestData = [request dataUsingEncoding:NSASCIIStringEncoding];
    const uint8_t *bytes = requestData.bytes;
    NSUInteger remaining = requestData.length;
    while (remaining) {
        ssize_t count = send(fd, bytes, remaining, 0);
        NSCAssert(count > 0, @"send failed");
        bytes += count;
        remaining -= (NSUInteger)count;
    }
    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[512];
    ssize_t count;
    while ((count = recv(fd, buffer, sizeof(buffer), 0)) > 0) [response appendBytes:buffer length:(NSUInteger)count];
    close(fd);
    return response;
}

static void IPAssertResponse(NSURL *url, NSString *method, NSString *range, NSString *status, NSString *body) {
    NSData *data = IPRequest(url, method, range);
    NSString *response = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %@", status];
    NSCAssert([response hasPrefix:header], @"unexpected status: %@", response);
    NSRange separator = [response rangeOfString:@"\r\n\r\n"];
    NSCAssert(separator.location != NSNotFound, @"missing response headers");
    NSString *bodyText = [response substringFromIndex:NSMaxRange(separator)];
    NSCAssert([bodyText isEqualToString:body], @"unexpected body %@ (expected %@)", bodyText, body);
}

int main(void) {
    @autoreleasepool {
        IPHTTPServer *server = [[IPHTTPServer alloc] initWithProfile:@{@"host": @"unused"}
                                                           password:@"never-logged"
                                                               path:@"song.mp3"
                                                               size:10];
        NSError *error = nil;
        NSURL *url = [server start:&error];
        NSCAssert(url != nil && error == nil, @"server start failed: %@", error);
        IPAssertResponse(url, @"GET", @"bytes=2-5", @"206 Partial Content", @"2345");
        IPAssertResponse(url, @"GET", @"bytes=-3", @"206 Partial Content", @"789");
        IPAssertResponse(url, @"GET", @"bytes=10-", @"416 Range Not Satisfiable", @"");
        IPAssertResponse(url, @"HEAD", nil, @"200 OK", @"");
        [server stop];
        puts("IPHTTPServer range host checks passed");
    }
    return 0;
}

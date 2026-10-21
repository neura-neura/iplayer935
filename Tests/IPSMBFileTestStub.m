#import "../Sources/IPSMB.h"
#include <errno.h>

uint64_t IPTestSMBBytesRead=0;

/** Local-only IPSMB substitute for host codec tests; it performs no SMB/network access. */
@implementation IPSMB {
    NSString *_fixturePath;
    BOOL _connected;
}
- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password {
    (void)password;
    self = [super init];
    if (self) _fixturePath = [profile[@"fixturePath"] copy];
    return self;
}
- (BOOL)connect:(NSError **)error {
    _connected = [[NSFileManager defaultManager] fileExistsAtPath:_fixturePath];
    if (!_connected && error) *error = [NSError errorWithDomain:@"IPSMBFileTestStub" code:ENOENT userInfo:nil];
    return _connected;
}
- (NSArray *)list:(NSString *)shareRelativePath error:(NSError **)error { (void)shareRelativePath; (void)error; return @[]; }
- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    (void)path;
    if (!_connected) { if (error) *error = [NSError errorWithDomain:@"IPSMBFileTestStub" code:ENOTCONN userInfo:nil]; return nil; }
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:_fixturePath];
    if (!file) { if (error) *error = [NSError errorWithDomain:@"IPSMBFileTestStub" code:EIO userInfo:nil]; return nil; }
    [file seekToFileOffset:offset]; NSData *data = [file readDataOfLength:length]; [file closeFile];
    IPTestSMBBytesRead+=data.length;
    return data ?: [NSData data];
}
- (uint64_t)size:(NSString *)path error:(NSError **)error {
    (void)path; NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:_fixturePath error:error];
    return [attrs[NSFileSize] unsignedLongLongValue];
}
- (void)disconnect { _connected = NO; }
@end

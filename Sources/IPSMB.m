#import "IPStrings.h"
#import "IPSMB.h"
#import <smb2/smb2.h>
#import <smb2/libsmb2.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>

static NSString * const IPSMBErrorDomain = @"IPSMBErrorDomain";
static const NSInteger IPSMBErrorInvalidArgument = 1;
static const NSInteger IPSMBErrorNotConnected = 2;

@interface IPSMB () {
    NSDictionary *_profile;
    NSString *_password;
    struct smb2_context *_context;
    BOOL _connected;
    NSString *_root;
    BOOL _validRoot;
}
- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message;
- (NSString *)normalizedPath:(NSString *)path error:(NSError **)error;
- (NSString *)serverPath:(NSString *)path error:(NSError **)error;
- (NSString *)shareRelativePathForServerPath:(NSString *)path;
@end

@implementation IPSMB

- (instancetype)initWithProfile:(NSDictionary *)profile password:(NSString *)password {
    self = [super init];
    if (self) {
        _profile = [profile copy] ?: @{};
        _password = [password copy] ?: @"";
        NSString *root = [_profile[@"root"] isKindOfClass:[NSString class]] ? _profile[@"root"] : @"";
        _root = [self normalizedPath:root error:NULL];
        _validRoot = (_root != nil);
    }
    return self;
}

- (void)setError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (error) {
        *error = [NSError errorWithDomain:IPSMBErrorDomain code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: IPL(@"SMB operation failed.")}];
    }
}

- (NSString *)normalizedPath:(NSString *)path error:(NSError **)error {
    if (![path isKindOfClass:[NSString class]] || [path hasPrefix:@"/"] || [path rangeOfString:@"\\"].location != NSNotFound) {
        [self setError:error code:IPSMBErrorInvalidArgument message:IPL(@"Path must be share-relative.")];
        return nil;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."] || [part rangeOfString:@":"].location != NSNotFound) {
            [self setError:error code:IPSMBErrorInvalidArgument message:IPL(@"Path contains an invalid component.")];
            return nil;
        }
        [parts addObject:part];
    }
    return [parts componentsJoinedByString:@"/"];
}

- (NSString *)serverPath:(NSString *)path error:(NSError **)error {
    NSString *relative = [self normalizedPath:path ?: @"" error:error];
    if (!relative) return nil;
    if (_root.length == 0) return relative;
    if (relative.length == 0) return _root;
    return [_root stringByAppendingFormat:@"/%@", relative];
}

- (NSString *)shareRelativePathForServerPath:(NSString *)path {
    return path;
}

- (BOOL)connect:(NSError **)error {
    if (error) *error = nil;
    [self disconnect];
    if (!_validRoot) {
        [self setError:error code:IPSMBErrorInvalidArgument message:IPL(@"SMB profile root is not a valid share-relative path.")];
        return NO;
    }
    NSString *host = [_profile[@"host"] isKindOfClass:[NSString class]] ? _profile[@"host"] : nil;
    NSString *share = [_profile[@"share"] isKindOfClass:[NSString class]] ? _profile[@"share"] : nil;
    NSString *username = [_profile[@"username"] isKindOfClass:[NSString class]] ? _profile[@"username"] : @"Guest";
    if (host.length == 0 || share.length == 0 || [share rangeOfString:@"/"].location != NSNotFound || [share rangeOfString:@"\\"].location != NSNotFound) {
        [self setError:error code:IPSMBErrorInvalidArgument message:IPL(@"SMB profile requires a host and share.")];
        return NO;
    }
    _context = smb2_init_context();
    if (!_context) {
        [self setError:error code:ENOMEM message:IPL(@"Could not create SMB context.")];
        return NO;
    }
    NSInteger timeout=[_profile[@"readTimeout"] integerValue];
    smb2_set_timeout(_context, timeout>0&&timeout<=20?(int)timeout:20);
    smb2_set_version(_context, SMB2_VERSION_ANY);
    /* libsmb2's public authentication selector takes the upstream NTLMSSP enum value 1. */
    smb2_set_authentication(_context, 1);
    smb2_set_user(_context, username.UTF8String);
    smb2_set_password(_context, _password.UTF8String);
    int status = smb2_connect_share(_context, host.UTF8String, share.UTF8String, username.UTF8String);
    if (status < 0) {
        /* Never include library diagnostics here: credential strings must not reach NSError/logs. */
        [self setError:error code:-status message:[NSString stringWithFormat:IPL(@"Could not connect to SMB share (error %d)."), status]];
        smb2_destroy_context(_context);
        _context = NULL;
        return NO;
    }
    _connected = YES;
    return YES;
}

- (NSArray *)list:(NSString *)shareRelativePath error:(NSError **)error {
    if (error) *error = nil;
    if (!_connected || !_context) {
        [self setError:error code:IPSMBErrorNotConnected message:IPL(@"SMB client is not connected.")];
        return nil;
    }
    NSString *serverPath = [self serverPath:shareRelativePath error:error];
    if (!serverPath) return nil;
    struct smb2dir *dir = smb2_opendir(_context, serverPath.UTF8String);
    if (!dir) {
        [self setError:error code:EIO message:IPL(@"Could not list SMB directory.")];
        return nil;
    }
    NSMutableArray *entries = [NSMutableArray array];
    struct smb2dirent *entry;
    while ((entry = smb2_readdir(_context, dir)) != NULL) {
        if (!entry->name || strcmp(entry->name, ".") == 0 || strcmp(entry->name, "..") == 0) continue;
        NSString *name = [NSString stringWithUTF8String:entry->name];
        if (!name) continue;
        NSString *itemPath = serverPath.length ? [serverPath stringByAppendingFormat:@"/%@", name] : name;
        [entries addObject:@{@"name": name,
                             @"path": [self shareRelativePathForServerPath:itemPath],
                             @"directory": @(entry->st.smb2_type == SMB2_TYPE_DIRECTORY),
                             @"size": @(entry->st.smb2_size), @"modifiedAt":@(entry->st.smb2_mtime)}];
    }
    smb2_closedir(_context, dir);
    return entries;
}

- (NSData *)read:(NSString *)path offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if (error) *error = nil;
    if (!_connected || !_context) {
        [self setError:error code:IPSMBErrorNotConnected message:IPL(@"SMB client is not connected.")];
        return nil;
    }
    NSString *serverPath = [self serverPath:path error:error];
    if (!serverPath) return nil;
    if ((uint64_t)length > UINT64_MAX - offset) {
        [self setError:error code:IPSMBErrorInvalidArgument message:IPL(@"Read range exceeds the supported file offset.")];
        return nil;
    }
    struct smb2fh *file = smb2_open(_context, serverPath.UTF8String, O_RDONLY);
    if (!file) {
        [self setError:error code:EIO message:IPL(@"Could not open SMB file for reading.")];
        return nil;
    }
    NSMutableData *result = [NSMutableData data];
    uint32_t maxRead = smb2_get_max_read_size(_context);
    if (maxRead == 0 || maxRead > 1024 * 1024) maxRead = 1024 * 1024;
    NSMutableData *buffer = [NSMutableData dataWithLength:MIN((NSUInteger)maxRead,length)];
    NSUInteger remaining = length;
    uint64_t currentOffset = offset;
    BOOL failed = NO;
    while (remaining > 0) {
        uint32_t amount = (uint32_t)MIN((NSUInteger)maxRead, remaining);
        int count = smb2_pread(_context, file, buffer.mutableBytes, amount, currentOffset);
        if (count < 0) { failed = YES; break; }
        if (count == 0) break;
        [result appendBytes:buffer.bytes length:(NSUInteger)count];
        remaining -= (NSUInteger)count;
        currentOffset += (uint64_t)count;
        if ((uint32_t)count < amount) break;
    }
    smb2_close(_context, file);
    if (failed) {
        [self setError:error code:EIO message:IPL(@"Could not read SMB file.")];
        return nil;
    }
    return result;
}

- (uint64_t)size:(NSString *)path error:(NSError **)error {
    if (error) *error = nil;
    if (!_connected || !_context) {
        [self setError:error code:IPSMBErrorNotConnected message:IPL(@"SMB client is not connected.")];
        return 0;
    }
    NSString *serverPath = [self serverPath:path error:error];
    if (!serverPath) return 0;
    struct smb2_stat_64 stat;
    memset(&stat, 0, sizeof(stat));
    if (smb2_stat(_context, serverPath.UTF8String, &stat) < 0) {
        [self setError:error code:EIO message:IPL(@"Could not get SMB file size.")];
        return 0;
    }
    return stat.smb2_size;
}

- (void)disconnect {
    if (_context) {
        if (_connected) smb2_disconnect_share(_context);
        smb2_destroy_context(_context);
        _context = NULL;
    }
    _connected = NO;
}

- (void)dealloc {
    [self disconnect];
}

@end

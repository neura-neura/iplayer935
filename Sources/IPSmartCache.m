#import "IPStrings.h"
#import "IPSmartCache.h"
#import "IPSMB.h"
#import <CommonCrypto/CommonDigest.h>
static NSString *CacheKey(NSDictionary *track){
    NSString *identity=[NSString stringWithFormat:@"%@|%@|%@|%@",track[@"id"]?:@"",track[@"endpointIdentity"]?:@"",track[@"size"]?:@0,track[@"modifiedAt"]?:@0];NSData *data=[identity dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *key=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[key appendFormat:@"%02x",digest[i]];return key;
}
@interface IPSmartCache ()
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic,strong) dispatch_queue_t worker;
@property(nonatomic,strong) NSMutableDictionary *entries;
@property(atomic,copy) NSDictionary *available;
@property(atomic,copy,readwrite) NSDictionary *status;
@property(atomic,copy) NSString *protectedKey;
@property(atomic,copy) NSSet *reservedKeys;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL settingEnabled;
@property(nonatomic) unsigned long long settingLimit;
@end
@implementation IPSmartCache
- (instancetype)initWithDirectory:(NSURL *)directory {
    if((self=[super init])){
        _directory=directory;_worker=dispatch_queue_create("org.neura.smart-cache",DISPATCH_QUEUE_SERIAL);[[NSFileManager defaultManager]createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"manifest.json"]];NSDictionary *saved=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL]:nil;
        if(![saved isKindOfClass:[NSDictionary class]])saved=@{};
        _entries=[saved[@"entries"]isKindOfClass:[NSDictionary class]]?[saved[@"entries"]mutableCopy]:[NSMutableDictionary new];_settingEnabled=saved[@"enabled"]?[saved[@"enabled"]boolValue]:YES;_settingLimit=saved[@"limit"]?[saved[@"limit"]unsignedLongLongValue]:256ULL*1024*1024;
        for(NSString *key in [_entries.allKeys copy])if(key.length!=64||![[NSFileManager defaultManager]fileExistsAtPath:[[directory URLByAppendingPathComponent:[key stringByAppendingString:@".media"]]path]])[_entries removeObjectForKey:key];
        for(NSURL *url in [[NSFileManager defaultManager]contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL])if([url.pathExtension isEqual:@"part"]||([url.pathExtension isEqual:@"media"]&&!_entries[url.lastPathComponent.stringByDeletingPathExtension]))[[NSFileManager defaultManager]removeItemAtURL:url error:NULL];
        [self updateStatus:nil title:nil bytes:0 total:0];
    }return self;
}
- (BOOL)enabled {@synchronized(self){return self.settingEnabled;}}
- (void)setEnabled:(BOOL)value {@synchronized(self){self.settingEnabled=value;self.generation++;}dispatch_async(self.worker,^{[self saveManifest];[self updateStatus:nil title:nil bytes:0 total:0];});}
- (unsigned long long)limitBytes {@synchronized(self){return self.settingLimit;}}
- (void)setLimitBytes:(unsigned long long)value {@synchronized(self){self.settingLimit=MAX(1024ULL*1024,value);self.generation++;self.reservedKeys=nil;}dispatch_async(self.worker,^{[self makeRoom:0];[self saveManifest];[self updateStatus:nil title:nil bytes:0 total:0];});}
- (void)saveManifest {NSDictionary *manifest=@{@"entries":self.entries,@"enabled":@(self.enabled),@"limit":@(self.limitBytes)};NSData *data=[NSJSONSerialization dataWithJSONObject:manifest options:0 error:NULL];if(data)[data writeToURL:[self.directory URLByAppendingPathComponent:@"manifest.json"] options:NSDataWritingAtomic error:NULL];}
- (unsigned long long)used {unsigned long long n=0;for(NSDictionary *entry in self.entries.allValues)n+=[entry[@"size"]unsignedLongLongValue];return n;}
- (void)updateStatus:(NSString *)error title:(NSString *)title bytes:(uint64_t)bytes total:(uint64_t)total {
    self.available=[self.entries copy];self.status=@{@"enabled":@(self.enabled),@"bytes":@([self used]),@"limit":@(self.limitBytes),@"count":@(self.entries.count),@"running":@(title!=nil),@"title":title?:@"",@"received":@(bytes),@"total":@(total),@"error":error?:@""};
}
- (NSURL *)file:(NSString *)key {return [self.directory URLByAppendingPathComponent:[key stringByAppendingString:@".media"]];}
- (NSURL *)localURLForTrack:(NSDictionary *)track {
    if(!track[@"id"])return nil;NSString *key=CacheKey(track);if(!self.available[key])return nil;NSURL *url=[self file:key];if(![[NSFileManager defaultManager]fileExistsAtPath:url.path])return nil;
    if([NSDate date].timeIntervalSince1970-[self.available[key][@"used"]doubleValue]<30)return url;
    dispatch_async(self.worker,^{NSMutableDictionary *entry=[self.entries[key]mutableCopy];if(entry){entry[@"used"]=@([NSDate date].timeIntervalSince1970);self.entries[key]=entry;[self saveManifest];}});return url;
}
- (BOOL)makeRoom:(uint64_t)size {
    if(size>self.limitBytes)return NO;
    NSArray *keys=[self.entries keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"used"]compare:b[@"used"]];}];
    uint64_t used=[self used];for(NSString *key in keys){if(used<=self.limitBytes-size)break;if([key isEqual:self.protectedKey]||[self.reservedKeys containsObject:key])continue;uint64_t old=[self.entries[key][@"size"]unsignedLongLongValue];if([[NSFileManager defaultManager]removeItemAtURL:[self file:key] error:NULL]){used-=old;[self.entries removeObjectForKey:key];}}
    return used<=self.limitBytes-size;
}
- (BOOL)valid:(NSUInteger)generation {@synchronized(self){return generation==self.generation&&self.settingEnabled;}}
- (void)protectTrack:(NSDictionary *)track {self.protectedKey=track[@"id"]?CacheKey(track):nil;}
- (void)cancel {@synchronized(self){self.generation++;}}
- (void)clear {[self cancel];dispatch_async(self.worker,^{for(NSString *key in [self.entries.allKeys copy])if(![key isEqual:self.protectedKey]&&[[NSFileManager defaultManager]removeItemAtURL:[self file:key] error:NULL])[self.entries removeObjectForKey:key];[self saveManifest];[self updateStatus:nil title:nil bytes:0 total:0];});}
- (void)flush {dispatch_sync(self.worker,^{});}
- (void)prefetchQueue:(NSArray *)queue index:(NSInteger)index profiles:(NSArray *)profiles password:(NSString *(^)(NSDictionary *))password {
    if(index<0||index>=(NSInteger)queue.count)return;[self cancel];self.protectedKey=CacheKey(queue[index]);if(!self.enabled)return;
    NSMutableArray *tracks=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
    // Next songs first; then retain the current song for a later offline replay.
    for(NSInteger n=index+1;n<=MIN(index+3,(NSInteger)queue.count-1);n++)if(![seen containsObject:queue[n][@"id"]?:@""]){[tracks addObject:[queue[n]copy]];[seen addObject:queue[n][@"id"]?:@""];}
    if(![seen containsObject:queue[index][@"id"]?:@""])[tracks addObject:[queue[index]copy]];
    NSMutableSet *reserved=[NSMutableSet new];for(NSDictionary *t in tracks)[reserved addObject:CacheKey(t)];self.reservedKeys=reserved;
    NSMutableDictionary *byID=[NSMutableDictionary new];for(NSDictionary *profile in profiles)if(profile[@"id"])byID[profile[@"id"]]=[profile copy];
    NSUInteger generation;@synchronized(self){generation=self.generation;}
    dispatch_async(self.worker,^{@autoreleasepool{
        NSString *lastError=nil;
        for(NSDictionary *track in tracks){@autoreleasepool{
            if(![self valid:generation])break;NSString *key=CacheKey(track);if(self.entries[key]||[track[@"downloaded"]boolValue]||track[@"unsupportedReason"]||[track[@"unavailableRemote"]boolValue])continue;
            NSDictionary *profile=byID[track[@"profileID"]];if(!profile||![track[@"endpointIdentity"]isEqual:profile[@"endpointIdentity"]?:profile[@"id"]])continue;
            NSMutableDictionary *settings=[profile mutableCopy];settings[@"readTimeout"]=@5;IPSMB *client=[[IPSMB alloc]initWithProfile:settings password:password?password(profile):@""];NSError *error=nil;
            if(![client connect:&error]){[client disconnect];lastError=IPL(@"Servidor no disponible; se conserva la caché anterior.");break;}
            uint64_t size=[client size:track[@"path"] error:&error];NSDictionary *fs=[[NSFileManager defaultManager]attributesOfFileSystemForPath:self.directory.path error:NULL];uint64_t free=[fs[NSFileSystemFreeSize]unsignedLongLongValue];
            if(error||!size||size!=[track[@"size"]unsignedLongLongValue]||free<64ULL*1024*1024||size>free-64ULL*1024*1024||![self makeRoom:size]){[client disconnect];lastError=IPL(@"No hay espacio suficiente o cambió el archivo remoto.");continue;}
            [self saveManifest];[self updateStatus:nil title:track[@"title"]?:IPL(@"Canción") bytes:0 total:size];NSURL *part=[self.directory URLByAppendingPathComponent:[key stringByAppendingString:@".part"]];[[NSFileManager defaultManager]createFileAtPath:part.path contents:nil attributes:nil];NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:part.path];uint64_t offset=0;BOOL ok=file!=nil;
            NSTimeInterval reported=0;
            while(ok&&offset<size&&[self valid:generation]){@autoreleasepool{
                NSUInteger amount=(NSUInteger)MIN(128ULL*1024,size-offset);NSData *data=[client read:track[@"path"] offset:offset length:amount error:&error];if(data.length!=amount){ok=NO;break;}
                @try{[file writeData:data];}@catch(NSException *e){ok=NO;break;}offset+=data.length;
                NSTimeInterval now=[NSDate date].timeIntervalSince1970;if(now-reported>=1){[self updateStatus:nil title:track[@"title"]?:IPL(@"Canción") bytes:offset total:size];reported=now;}[NSThread sleepForTimeInterval:.1];
            }}
            @try{[file closeFile];}@catch(NSException *e){ok=NO;}[client disconnect];
            if(ok&&offset==size&&[self valid:generation]&&[[NSFileManager defaultManager]moveItemAtURL:part toURL:[self file:key] error:&error]){self.entries[key]=@{@"size":@(size),@"used":@([NSDate date].timeIntervalSince1970)};[self saveManifest];[self updateStatus:nil title:nil bytes:0 total:0];}
            else {[[NSFileManager defaultManager]removeItemAtURL:part error:NULL];if([self valid:generation]){lastError=IPL(@"Se interrumpió la descarga; las canciones completas siguen disponibles.");break;}}
        }}
        [self updateStatus:lastError title:nil bytes:0 total:0];
    }});
}
@end

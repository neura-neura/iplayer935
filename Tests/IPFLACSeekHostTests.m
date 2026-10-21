#import <Foundation/Foundation.h>
#import "IPPCMServer.h"
extern uint64_t IPTestSMBBytesRead;
int main(int argc,const char **argv){@autoreleasepool{
    NSCAssert(argc==2,@"fixture required");NSString *path=[NSString stringWithUTF8String:argv[1]];NSError *error=nil;
    IPPCMServer *reference=[[IPPCMServer alloc]initWithURL:[NSURL fileURLWithPath:path]];NSCAssert([reference preparePCM:&error],@"reference failed %@",error);
    NSMutableData *full=[NSMutableData new];
    while(YES){NSData *part=[reference readPCMFrames:4096 error:&error];NSCAssert(part&&!error,@"reference decode failed %@",error);if(!part.length)break;[full appendData:part];}
    NSDictionary *info=reference.diagnosticSnapshot;int64_t frames=[info[@"durationFrames"]longLongValue];NSUInteger channels=[info[@"channels"]unsignedIntegerValue],bytesPerFrame=channels*2;[reference closePCM];
    NSCAssert(full.length==(uint64_t)frames*bytesPerFrame,@"reference frame count mismatch");
    uint64_t fileSize=[[[NSFileManager defaultManager]attributesOfItemAtPath:path error:NULL][NSFileSize]unsignedLongLongValue];
    for(int remote=0;remote<2;remote++){
        IPPCMServer *decoder=remote?[[IPPCMServer alloc]initWithProfile:@{@"fixturePath":path} password:@"unused" path:path.lastPathComponent size:0]:[[IPPCMServer alloc]initWithURL:[NSURL fileURLWithPath:path]];
        NSCAssert([decoder preparePCM:&error],@"open failed %@",error);
        NSArray *positions=@[@.93,@.1,@.63,@.35,@.99,@.01,@.5,@0];
        for(NSNumber *value in positions){
            int64_t target=MIN(frames-4096,(int64_t)(frames*value.doubleValue))+17;target=MAX(0,MIN(target,frames-4096));
            uint64_t before=IPTestSMBBytesRead;NSTimeInterval start=[NSDate timeIntervalSinceReferenceDate];
            NSCAssert([decoder seekPCMFrame:target error:&error]&&!error,@"seek failed %@",error);
            NSData *part=[decoder readPCMFrames:4096 error:&error];
            NSCAssert(part.length==4096*bytesPerFrame&&!error,@"short seek result at %@: %@",value,error);
            NSData *expected=[full subdataWithRange:NSMakeRange((NSUInteger)target*bytesPerFrame,part.length)];
            NSCAssert([part isEqual:expected],@"sample-exact seek failed at %@, %@",value,decoder.diagnosticSnapshot);
            NSDictionary *s=decoder.diagnosticSnapshot;
            if(value.doubleValue>=.9){NSCAssert([s[@"seekMode"]isEqual:@"flac-byte-probe"]&&[s[@"seekProbes"]unsignedIntegerValue]<=12,@"deep seek used sequential fallback: %@",s);if(remote)NSCAssert(IPTestSMBBytesRead-before<MAX((uint64_t)1048576,fileSize/2),@"deep SMB seek reread most of the file: %llu",IPTestSMBBytesRead-before);}
            printf("FLAC seek %.2f (%s): exact 4096 frames, %.3fs, %lu probes, %llu SMB bytes\n",value.doubleValue,remote?"SMB stub":"local",[NSDate timeIntervalSinceReferenceDate]-start,(unsigned long)[s[@"seekProbes"]unsignedIntegerValue],(unsigned long long)(IPTestSMBBytesRead-before));
        }[decoder closePCM];
    }
    puts("Native FLAC byte seeks passed: sample-exact forward/backward targets and bounded deep-seek reads without timestamp binary seek");
}return 0;}

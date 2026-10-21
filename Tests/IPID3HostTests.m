#import <Foundation/Foundation.h>
#import "IPID3.h"
#include <zlib.h>
static void PutSize(NSMutableData *d,NSUInteger n,BOOL sync){unsigned char p[4];for(int i=3;i>=0;i--){p[i]=n&(sync?127:255);n>>=sync?7:8;}[d appendBytes:p length:4];}
static NSData *FrameData(NSString *key,NSData *value,int version,int flags){NSMutableData *d=[[key dataUsingEncoding:NSASCIIStringEncoding]mutableCopy];if(version==2){NSUInteger n=value.length;unsigned char p[]={n>>16,n>>8,n};[d appendBytes:p length:3];}else{PutSize(d,value.length,version==4);unsigned char p[]={0,flags};[d appendBytes:p length:2];}[d appendData:value];return d;}
static NSMutableData *TagData(NSData *body,int version,int flags){unsigned char h[]={'I','D','3',version,0,flags};NSMutableData *d=[NSMutableData dataWithBytes:h length:6];PutSize(d,body.length,YES);[d appendData:body];return d;}
static NSDictionary *Read(NSData *data){NSError *error=nil;NSDictionary *tags=[IPID3 readMetadataWithReader:^NSData *(uint64_t offset,NSUInteger length){return [data subdataWithRange:NSMakeRange((NSUInteger)offset,MIN(length,data.length-(NSUInteger)offset))];} fileSize:data.length error:&error];NSCAssert(tags&&!error,@"ID3 read failed: %@",error);return tags;}
void IPID3Regression(void){
    unsigned char legacy[128]={0};memcpy(legacy,"TAG",3);memcpy(legacy+3,"Legacy title",12);memcpy(legacy+33,"Legacy artist",13);legacy[126]=7;legacy[127]=17;
    NSDictionary *tags=Read([NSData dataWithBytes:legacy length:128]);NSCAssert([tags[@"title"]isEqual:@"Legacy title"]&&[tags[@"trackNumber"]intValue]==7&&[tags[@"genre"]isEqual:@"Rock"],@"ID3v1.1 failed");
    unsigned char latin[]={0,'C','a','f',0xe9};NSData *text=[NSData dataWithBytes:latin length:sizeof(latin)];
    tags=Read(TagData(FrameData(@"TT2",text,2,0),2,0));NSCAssert([tags[@"title"]isEqual:@"Café"],@"ID3v2.2 Latin1 failed");
    unsigned char bom=1;NSMutableData *utf16=[NSMutableData dataWithBytes:&bom length:1];[utf16 appendData:[@"Canción" dataUsingEncoding:NSUTF16StringEncoding]];
    tags=Read(TagData(FrameData(@"TIT2",utf16,3,0),3,0));NSCAssert([tags[@"title"]isEqual:@"Canción"],@"ID3v2.3 UTF16 failed");
    unsigned char be[]={2,0,0x41,0x26,0x6b};tags=Read(TagData(FrameData(@"TIT2",[NSData dataWithBytes:be length:5],4,0),4,0));NSCAssert([tags[@"title"]isEqual:@"A♫"],@"UTF16BE failed");
    unsigned char multi[]={3,'A',0,'B',0};tags=Read(TagData(FrameData(@"TPE1",[NSData dataWithBytes:multi length:6],4,0),4,0));NSCAssert([tags[@"artist"]isEqual:@"A / B"],@"multi-value text failed");
    // v2.4 grouping + data length indicator, then frame unsynchronisation.
    unsigned char prefix=9;NSMutableData *grouped=[NSMutableData dataWithBytes:&prefix length:1];PutSize(grouped,text.length,YES);[grouped appendData:text];
    tags=Read(TagData(FrameData(@"TIT2",grouped,4,0x41),4,0));NSCAssert([tags[@"title"]isEqual:@"Café"],@"group/DLI failed");
    unsigned char unsync[]={0,'A',255,0,224,'B'};NSData *u=[NSData dataWithBytes:unsync length:6];
    tags=Read(TagData(FrameData(@"TIT2",u,4,2),4,0));NSCAssert([tags[@"title"]isEqual:@"AÿàB"],@"frame unsync failed");
    // v2.3 applies unsynchronisation after the frame's unescaped size is written.
    unsigned char raw[]={0,'A',255,224,'B'};NSMutableData *global=[FrameData(@"TIT2",[NSData dataWithBytes:raw length:5],3,0)mutableCopy];unsigned char zero=0;[global replaceBytesInRange:NSMakeRange(13,0) withBytes:&zero length:1];
    tags=Read(TagData(global,3,128));NSCAssert([tags[@"title"]isEqual:@"AÿàB"],@"global unsync failed");
    uLongf capacity=compressBound(text.length);NSMutableData *compressed=[NSMutableData dataWithLength:capacity];NSCAssert(compress(compressed.mutableBytes,&capacity,text.bytes,text.length)==Z_OK,@"fixture compression failed");compressed.length=capacity;
    for(int v=3;v<=4;v++){NSMutableData *value=[NSMutableData new];PutSize(value,text.length,v==4);[value appendData:compressed];tags=Read(TagData(FrameData(@"TIT2",value,v,v==3?128:9),v,0));NSCAssert([tags[@"title"]isEqual:@"Café"],@"compressed ID3 failed");}
    NSMutableData *ext=[NSMutableData new];PutSize(ext,6,NO);[ext increaseLengthBy:6];[ext appendData:FrameData(@"TIT2",text,3,0)];tags=Read(TagData(ext,3,64));NSCAssert([tags[@"title"]isEqual:@"Café"],@"extended header failed");
    NSMutableData *appended=[NSMutableData dataWithLength:256];NSMutableData *endTag=TagData(FrameData(@"TIT2",text,4,0),4,16);NSMutableData *footer=[[endTag subdataWithRange:NSMakeRange(0,10)]mutableCopy];memcpy(footer.mutableBytes,"3DI",3);[appended appendData:endTag];[appended appendData:footer];
    tags=Read(appended);NSCAssert([tags[@"title"]isEqual:@"Café"],@"appended v2.4 footer failed");
    // A large cover before text must be skipped without reading the entire artwork.
    NSMutableData *body=[FrameData(@"APIC",[NSMutableData dataWithLength:5*1024*1024],3,0)mutableCopy];[body appendData:FrameData(@"TIT2",text,3,0)];NSData *large=TagData(body,3,0);__block NSUInteger bytes=0;NSError *error=nil;
    tags=[IPID3 readMetadataWithReader:^NSData *(uint64_t offset,NSUInteger length){bytes+=length;return [large subdataWithRange:NSMakeRange((NSUInteger)offset,length)];} fileSize:large.length error:&error];NSCAssert([tags[@"title"]isEqual:@"Café"]&&!error&&bytes<65536,@"large cover blocked text or caused excessive reads");
    tags=[IPID3 readMetadataWithReader:^NSData *(uint64_t offset,NSUInteger length){return nil;} fileSize:large.length error:&error];NSCAssert(!tags&&error,@"read failure must remain retryable");
    NSMutableData *truncated=TagData(FrameData(@"TIT2",text,3,0),3,0);truncated.length-=2;error=nil;tags=[IPID3 readMetadataWithReader:^NSData *(uint64_t offset,NSUInteger length){return [truncated subdataWithRange:NSMakeRange((NSUInteger)offset,length)];} fileSize:truncated.length error:&error];NSCAssert(!tags&&error,@"truncated tags must not complete");
    puts("ID3v1.1/v2.2/v2.3/v2.4 encodings, compression, unsync, large-cover skipping and read failures passed");
}

#import <Foundation/Foundation.h>
#import "IPLibraryIndex.h"
#import "IPID3.h"
static void Wait(BOOL *done){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:15];while(!*done&&end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];NSCAssert(*done,@"index timed out");}
static NSData *Tag(NSString *name,NSString *text){NSData *value=[text dataUsingEncoding:NSUTF8StringEncoding];unsigned char enc=3;NSMutableData *payload=[NSMutableData dataWithBytes:&enc length:1];[payload appendData:value];NSMutableData *frame=[NSMutableData dataWithData:[name dataUsingEncoding:NSASCIIStringEncoding]];uint32_t n=(uint32_t)payload.length;unsigned char size[]={n>>24,n>>16,n>>8,n,0,0};[frame appendBytes:size length:6];[frame appendData:payload];return frame;}
extern void IPID3Regression(void);
int main(){@autoreleasepool{
    IPID3Regression();
    NSMutableData *body=[NSMutableData new];[body appendData:Tag(@"TIT2",@"Canción")];[body appendData:Tag(@"TPE1",@"Árbol")];[body appendData:Tag(@"TRCK",@"4/12")];
    NSUInteger n=body.length;unsigned char header[]={'I','D','3',3,0,0,(n>>21)&127,(n>>14)&127,(n>>7)&127,n&127};NSMutableData *id3=[NSMutableData dataWithBytes:header length:10];[id3 appendData:body];NSDictionary *tags=[IPID3 metadataFromData:id3];
    NSCAssert([tags[@"title"] isEqual:@"Canción"]&&[tags[@"artist"] isEqual:@"Árbol"]&&[tags[@"trackNumber"] integerValue]==4,@"ID3 Unicode tags failed");
    for(NSUInteger i=0;i<id3.length;i++)[IPID3 metadataFromData:[id3 subdataWithRange:NSMakeRange(0,i)]];
    IPLibraryIndex *index=[IPLibraryIndex new];NSMutableArray *tracks=[NSMutableArray new];
    for(int i=0;i<25154;i++)[tracks addObject:[@{@"id":[NSString stringWithFormat:@"%05d",i],@"profileID":@"p",@"endpointIdentity":@"e",@"title":[NSString stringWithFormat:@"Song %d",i],@"artist":@"Árbol",@"modifiedAt":@(i),@"favorite":@(i==3)}mutableCopy]];
    NSDate *start=[NSDate date];[index replaceTracks:tracks];__block BOOL done=NO;
    [index rowsForProfile:@{@"id":@"p",@"endpointIdentity":@"e"} mode:@"library" playlistIDs:nil sort:@"recent" query:@"arbol" completion:^(NSArray *rows,NSUInteger pending){NSCAssert(rows.count==25154&&[rows.firstObject[@"id"] isEqual:@"25153"],@"recent or accent search failed");done=YES;}];Wait(&done);
    printf("Indexed/sorted 25154 rows in %.3fs on host\n",-[start timeIntervalSinceNow]);
    done=NO;[index rowsForProfile:nil mode:@"songs" playlistIDs:@[@"00003",@"00001",@"00003"] sort:@"playlist" query:nil completion:^(NSArray *rows,NSUInteger pending){NSCAssert(rows.count==3&&rows[0]==rows[2],@"playlist duplicates/order lost");done=YES;}];Wait(&done);
    NSMutableDictionary *updated=tracks[3];updated[@"title"]=@"AAAA";[index updateTracks:@[updated]];
    done=NO;[index rowsForProfile:nil mode:@"favorites" playlistIDs:nil sort:@"title" query:nil completion:^(NSArray *rows,NSUInteger pending){NSCAssert(rows.count==1&&[rows[0][@"title"] isEqual:@"AAAA"],@"incremental update/cache invalidation failed");done=YES;}];Wait(&done);
    puts("ID3 bounded parsing and library index checks passed");
}return 0;}

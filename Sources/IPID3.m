#import "IPStrings.h"
#import "IPID3.h"
#include <string.h>
#include <errno.h>
#include <zlib.h>
static uint32_t BE(const unsigned char *p){return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];}
static uint32_t Sync(const unsigned char *p){return ((p[0]&127)<<21)|((p[1]&127)<<14)|((p[2]&127)<<7)|(p[3]&127);}
static BOOL ValidID(const unsigned char *p,NSUInteger n){for(NSUInteger i=0;i<n;i++)if(!((p[i]>='A'&&p[i]<='Z')||(p[i]>='0'&&p[i]<='9')))return NO;return YES;}
static NSData *UnSync(NSData *data){NSMutableData *out=[NSMutableData dataWithCapacity:data.length];const unsigned char *p=data.bytes;for(NSUInteger i=0;i<data.length;i++){[out appendBytes:p+i length:1];if(p[i]==255&&i+1<data.length&&p[i+1]==0)i++;}return out;}
static NSString *Clean(NSString *s){
    NSMutableArray *values=[NSMutableArray new];
    for(NSString *part in [s componentsSeparatedByString:@"\0"]){NSString *value=[part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];if(value.length)[values addObject:value];}
    return values.count?[values componentsJoinedByString:@" / "]:nil;
}
static NSString *Text(NSData *data){
    if(data.length<2)return nil;const unsigned char *p=data.bytes;
    NSStringEncoding encoding=p[0]==1?NSUTF16StringEncoding:p[0]==2?NSUTF16BigEndianStringEncoding:p[0]==3?NSUTF8StringEncoding:NSISOLatin1StringEncoding;
    NSUInteger n=data.length-1;if((p[0]==1||p[0]==2)&&n%2)n--;
    NSString *s=[[NSString alloc]initWithBytes:p+1 length:n encoding:encoding];
    if(!s&&p[0]==1)s=[[NSString alloc]initWithBytes:p+1 length:n encoding:NSUTF16LittleEndianStringEncoding];
    return Clean(s);
}
static NSString *Genre(NSString *s){
    NSArray *names=@[@"Blues",@"Classic Rock",@"Country",@"Dance",@"Disco",@"Funk",@"Grunge",@"Hip-Hop",@"Jazz",@"Metal",@"New Age",@"Oldies",@"Other",@"Pop",@"R&B",@"Rap",@"Reggae",@"Rock",@"Techno",@"Industrial",@"Alternative",@"Ska",@"Death Metal",@"Pranks",@"Soundtrack",@"Euro-Techno",@"Ambient",@"Trip-Hop",@"Vocal",@"Jazz+Funk",@"Fusion",@"Trance",@"Classical",@"Instrumental",@"Acid",@"House",@"Game",@"Sound Clip",@"Gospel",@"Noise",@"Alternative Rock",@"Bass",@"Soul",@"Punk",@"Space",@"Meditative",@"Instrumental Pop",@"Instrumental Rock",@"Ethnic",@"Gothic",@"Darkwave",@"Techno-Industrial",@"Electronic",@"Pop-Folk",@"Eurodance",@"Dream",@"Southern Rock",@"Comedy",@"Cult",@"Gangsta",@"Top 40",@"Christian Rap",@"Pop/Funk",@"Jungle",@"Native American",@"Cabaret",@"New Wave",@"Psychedelic",@"Rave",@"Showtunes",@"Trailer",@"Lo-Fi",@"Tribal",@"Acid Punk",@"Acid Jazz",@"Polka",@"Retro",@"Musical",@"Rock & Roll",@"Hard Rock"];
    NSString *number=s;if([s hasPrefix:@"("]){NSRange close=[s rangeOfString:@")"];if(close.location!=NSNotFound){NSString *tail=[s substringFromIndex:close.location+1];if(tail.length)return tail;number=[s substringWithRange:NSMakeRange(1,close.location-1)];}}
    if(number.length&&[number rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet]invertedSet]].location==NSNotFound){NSInteger i=number.integerValue;if(i>=0&&(NSUInteger)i<names.count)return names[i];}return s;
}
static void Error(NSError *__strong *error,NSInteger code,NSString *message){if(error&&!*error)*error=[NSError errorWithDomain:@"IPID3ErrorDomain" code:code userInfo:@{NSLocalizedDescriptionKey:message}];}
static void Frame(NSMutableDictionary *tags,NSString *key,NSData *raw,int version,unsigned char flags,BOOL tagUnsync,NSError *__strong *error){
    if(!raw.length)return;
    NSData *data=version==4&&((flags&2)||tagUnsync)?UnSync(raw):raw;
    const unsigned char *p=data.bytes;NSUInteger offset=0;uint32_t unpacked=0;BOOL compressed=NO;
    if(version==3){
        if(flags&0x40){Error(error,ENOTSUP,IPL(@"La etiqueta contiene un bloque cifrado."));return;}
        compressed=(flags&0x80)!=0;if(compressed){if(data.length<4)return;unpacked=BE(p);offset=4;}if(flags&0x20)offset++;
    }else if(version==4){
        if(flags&4){Error(error,ENOTSUP,IPL(@"La etiqueta contiene un bloque cifrado."));return;}
        if(flags&0x40)offset++;if(flags&1){if(data.length<offset+4)return;unpacked=Sync(p+offset);offset+=4;}compressed=(flags&8)!=0;
    }
    if(offset>=data.length)return;
    data=[data subdataWithRange:NSMakeRange(offset,data.length-offset)];
    if(compressed){if(!unpacked||unpacked>4*1024*1024){Error(error,EFBIG,IPL(@"Bloque ID3 comprimido demasiado grande."));return;}NSMutableData *decoded=[NSMutableData dataWithLength:unpacked];uLongf size=unpacked;if(uncompress(decoded.mutableBytes,&size,data.bytes,(uLong)data.length)!=Z_OK){Error(error,EINVAL,IPL(@"Bloque ID3 comprimido no válido."));return;}[decoded setLength:size];data=decoded;}
    NSDictionary *fields=@{@"TIT2":@"title",@"TT2":@"title",@"TPE1":@"artist",@"TP1":@"artist",@"TPE2":@"albumArtist",@"TP2":@"albumArtist",@"TALB":@"album",@"TAL":@"album",@"TCON":@"genre",@"TCO":@"genre",@"TRCK":@"trackNumber",@"TRK":@"trackNumber"};
    NSString *field=fields[key];
    if(field){NSString *text=Text(data);if(text.length){if([field isEqual:@"trackNumber"]){if(text.integerValue>0)tags[field]=@(text.integerValue);}else tags[field]=[field isEqual:@"genre"]?Genre(text):text;}return;}
    if(![key isEqual:@"APIC"]&&![key isEqual:@"PIC"])return;
    p=data.bytes;NSUInteger size=data.length;if(size<5)return;NSUInteger at=1;
    if([key isEqual:@"PIC"])at=4;else{while(at<size&&p[at])at++;at++;}
    if(at>=size)return;NSUInteger pictureType=p[at++];BOOL wide=p[0]==1||p[0]==2;
    while(at+(wide?1:0)<size){if(!p[at]&&(!wide||!p[at+1])){at+=wide?2:1;break;}at+=wide?2:1;}
    if(at<size&&(!tags[@"artworkData"]||pictureType==3))tags[@"artworkData"]=[data subdataWithRange:NSMakeRange(at,size-at)];
}
@implementation IPID3
+ (NSUInteger)tagLength:(NSData *)header {if(header.length<10)return 0;const unsigned char *p=header.bytes;if(memcmp(p,"ID3",3)||p[3]<2||p[3]>4)return 0;for(int i=6;i<10;i++)if(p[i]&128)return 0;return 10+Sync(p+6);}
+ (NSDictionary *)metadataFromData:(NSData *)data {
    NSUInteger length=[self tagLength:data];if(!length)return @{};const unsigned char *h=data.bytes;int version=h[3];BOOL unsync=(h[5]&128)!=0;
    NSData *body=[data subdataWithRange:NSMakeRange(10,MIN(length,data.length)-10)];if(version<4&&unsync)body=UnSync(body);
    const unsigned char *p=body.bytes;NSUInteger end=body.length,offset=0;
    if((h[5]&0x40)&&version>=3){if(end<4)return @{};offset=version==4?Sync(p):4+BE(p);if(offset>end)return @{};}
    NSMutableDictionary *tags=[NSMutableDictionary new];NSUInteger header=version==2?6:10;
    for(NSUInteger frames=0;frames<4096&&offset+header<=end;frames++){
        if(!ValidID(p+offset,version==2?3:4))break;
        NSString *key=[[NSString alloc]initWithBytes:p+offset length:version==2?3:4 encoding:NSASCIIStringEncoding];NSUInteger size=version==2?((p[offset+3]<<16)|(p[offset+4]<<8)|p[offset+5]):version==4?Sync(p+offset+4):BE(p+offset+4);unsigned char flags=version==2?0:p[offset+9];offset+=header;if(!size||size>end-offset)break;
        Frame(tags,key,[body subdataWithRange:NSMakeRange(offset,size)],version,flags,unsync,NULL);offset+=size;
    }if(![tags[@"artist"] length]&&tags[@"albumArtist"])tags[@"artist"]=tags[@"albumArtist"];[tags removeObjectForKey:@"albumArtist"];return tags;
}
+ (NSDictionary *)metadataWithReader:(NSData *(^)(uint64_t,NSUInteger))reader fileSize:(uint64_t)fileSize failure:(NSError *__strong *)error {
    if(error)*error=nil;
    __block NSData *window=nil;__block uint64_t base=UINT64_MAX;
    NSData *(^read)(uint64_t,NSUInteger)=^NSData *(uint64_t offset,NSUInteger size){
        if(offset>fileSize||size>fileSize-offset){Error(error,EIO,IPL(@"Etiqueta fuera de los límites del archivo."));return nil;}
        if(window&&offset>=base&&offset-base<=window.length&&size<=window.length-(NSUInteger)(offset-base))return [window subdataWithRange:NSMakeRange((NSUInteger)(offset-base),size)];
        if(size<16384){base=offset;window=reader(offset,(NSUInteger)MIN((uint64_t)16384,fileSize-offset));if(window.length<size){Error(error,EIO,IPL(@"No se pudo leer la etiqueta completa."));return nil;}return [window subdataWithRange:NSMakeRange(0,size)];}
        NSMutableData *data=[NSMutableData dataWithCapacity:size];while(data.length<size){NSUInteger amount=MIN((NSUInteger)65536,size-data.length);NSData *part=reader(offset+data.length,amount);if(part.length!=amount){Error(error,EIO,IPL(@"La lectura de etiquetas se interrumpió."));return nil;}[data appendData:part];}return data;
    };
    NSMutableDictionary *tags=[NSMutableDictionary new];
    if(fileSize<10)return tags;
    uint64_t start=0;NSData *header=read(0,10);if(!header)return nil;NSUInteger length=[self tagLength:header];
    if(!length&&fileSize>=20){for(NSNumber *tail in @[@10,@138]){uint64_t suffix=tail.unsignedLongLongValue;if(fileSize<suffix)continue;NSData *footer=read(fileSize-suffix,10);const unsigned char *f=footer.bytes;if(footer.length==10&&!memcmp(f,"3DI",3)&&f[3]==4){uint64_t body=Sync(f+6);if(body+10<=fileSize-suffix){start=fileSize-suffix-body-10;header=read(start,10);length=[self tagLength:header];if(length)break;}}}}
    if(length){
        if(length>fileSize-start){Error(error,EINVAL,IPL(@"La etiqueta ID3 está truncada."));return nil;}
        const unsigned char *h=header.bytes;int version=h[3];BOOL unsync=(h[5]&128)!=0;
        if(version==2&&(h[5]&0x40)){Error(error,ENOTSUP,IPL(@"Compresión global ID3v2.2 no definida."));return nil;}
        if(version<4&&unsync){
            if(length>8*1024*1024){Error(error,EFBIG,IPL(@"Etiqueta ID3 global demasiado grande."));return nil;}
            NSData *all=read(start,length);if(!all)return nil;
            NSData *body=UnSync([all subdataWithRange:NSMakeRange(10,all.length-10)]);NSMutableData *normalized=[[all subdataWithRange:NSMakeRange(0,10)]mutableCopy];unsigned char *bytes=normalized.mutableBytes;bytes[5]&=~128;NSUInteger n=body.length;for(int i=9;i>=6;i--){bytes[i]=n&127;n>>=7;}[normalized appendData:body];
            NSDictionary *decoded=[self metadataWithReader:^NSData *(uint64_t at,NSUInteger amount){return [normalized subdataWithRange:NSMakeRange((NSUInteger)at,amount)];} fileSize:normalized.length failure:error];if(!decoded)return nil;[tags addEntriesFromDictionary:decoded];
        }else{
            uint64_t offset=start+10,end=start+length;NSUInteger frameHeader=version==2?6:10;
            if(version>=3&&(h[5]&0x40)){NSData *ext=read(offset,4);if(!ext)return nil;NSUInteger skip=version==4?Sync(ext.bytes):4+BE(ext.bytes);if(skip<4||skip>end-offset){Error(error,EINVAL,IPL(@"Cabecera extendida ID3 no válida."));return nil;}offset+=skip;}
            for(NSUInteger frames=0;offset+frameHeader<=end;frames++){
                if(frames>=4096){Error(error,EFBIG,IPL(@"Demasiados bloques ID3."));return nil;}
                NSData *frame=read(offset,frameHeader);if(!frame)return nil;const unsigned char *p=frame.bytes;if(!p[0])break;
                if(!ValidID(p,version==2?3:4)){Error(error,EINVAL,IPL(@"Identificador de bloque ID3 no válido."));return nil;}
                NSString *key=[[NSString alloc]initWithBytes:p length:version==2?3:4 encoding:NSASCIIStringEncoding];NSUInteger size=version==2?((p[3]<<16)|(p[4]<<8)|p[5]):version==4?Sync(p+4):BE(p+4);unsigned char flags=version==2?0:p[9];offset+=frameHeader;
                if(size>end-offset){Error(error,EINVAL,IPL(@"Tamaño de bloque ID3 no válido."));return nil;}
                BOOL text=[key hasPrefix:@"T"],picture=[key isEqual:@"APIC"]||[key isEqual:@"PIC"];
                if(size&&((text&&size<=65536)||(picture&&size<=4*1024*1024))){NSData *value=read(offset,size);if(!value)return nil;Frame(tags,key,value,version,flags,unsync,error);if(error&&*error)return nil;}
                offset+=size;
            }
        }
    }
    if(fileSize>=128){NSData *tail=read(fileSize-128,128);if(!tail)return nil;NSDictionary *legacy=[self legacyMetadata:tail];for(NSString *key in legacy)if(!tags[key])tags[key]=legacy[key];}
    if(![tags[@"artist"] length]&&tags[@"albumArtist"])tags[@"artist"]=tags[@"albumArtist"];[tags removeObjectForKey:@"albumArtist"];
    return tags;
}
+ (NSDictionary *)readMetadataWithReader:(NSData *(^)(uint64_t,NSUInteger))reader fileSize:(uint64_t)fileSize error:(NSError **)error {
    NSError *failure=nil;NSDictionary *tags=[self metadataWithReader:reader fileSize:fileSize failure:&failure];if(error)*error=failure;return tags;
}
+ (NSDictionary *)legacyMetadata:(NSData *)data {
    if(data.length!=128||memcmp(data.bytes,"TAG",3))return @{};const unsigned char *p=data.bytes;NSMutableDictionary *tags=[NSMutableDictionary new];NSArray *keys=@[@"title",@"artist",@"album"];
    for(NSUInteger i=0;i<3;i++){NSString *s=[[NSString alloc]initWithBytes:p+3+30*i length:30 encoding:NSISOLatin1StringEncoding];s=Clean(s);if(s.length)tags[keys[i]]=s;}
    if(p[125]==0&&p[126])tags[@"trackNumber"]=@(p[126]);if(p[127]<80)tags[@"genre"]=Genre([NSString stringWithFormat:@"%u",p[127]]);return tags;
}
@end

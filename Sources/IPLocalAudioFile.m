#import "IPStrings.h"
#import "IPLocalAudioFile.h"
@interface IPLocalAudioFile ()
@property(nonatomic,strong) NSURL *directory;
@property(nonatomic,strong,readwrite) NSURL *URL;
@end
@implementation IPLocalAudioFile
- (instancetype)initWithDirectory:(NSURL *)directory {
    if((self=[super init])){
        _directory=directory;[[NSFileManager defaultManager]createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        // This directory belongs to this source. Leftover links only come from an earlier process.
        for(NSURL *url in [[NSFileManager defaultManager]contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL])[[NSFileManager defaultManager]removeItemAtURL:url error:NULL];
    }return self;
}
- (NSURL *)directoryURL {return self.directory;}
- (NSURL *)openFile:(NSURL *)file extension:(NSString *)extension error:(NSError **)error {
    [self close];NSString *ext=extension.lowercaseString;
    if([ext isEqual:@"alac"])ext=@"m4a";if([ext isEqual:@"wave"])ext=@"wav";
    NSSet *allowed=[NSSet setWithArray:@[@"mp3",@"m4a",@"m4b",@"mp4",@"aac",@"wav",@"aif",@"aiff",@"caf"]];
    if(!file.isFileURL||![allowed containsObject:ext]){if(error)*error=[NSError errorWithDomain:@"IPLocalAudioFile" code:1 userInfo:@{NSLocalizedDescriptionKey:IPL(@"La copia local no tiene una extensión de audio compatible.")}];return nil;}
    NSURL *link=[self.directory URLByAppendingPathComponent:[@"current" stringByAppendingPathExtension:ext]];
    if(![[NSFileManager defaultManager]linkItemAtURL:file toURL:link error:error])return nil;
    self.URL=link;return link;
}
- (void)close {if(self.URL)[[NSFileManager defaultManager]removeItemAtURL:self.URL error:NULL];self.URL=nil;}
- (void)dealloc {[self close];}
@end

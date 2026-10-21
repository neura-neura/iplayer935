#import <Foundation/Foundation.h>
/** Presents cached bytes to AVFoundation using an audio extension, without copying them. */
@interface IPLocalAudioFile : NSObject
@property(nonatomic,strong,readonly) NSURL *URL;
@property(nonatomic,strong,readonly) NSURL *directoryURL;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSURL *)openFile:(NSURL *)file extension:(NSString *)extension error:(NSError **)error;
- (void)close;
@end

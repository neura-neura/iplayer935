#import <UIKit/UIKit.h>
typedef NS_ENUM(NSInteger, IPControlIcon) { IPControlIconOptions, IPControlIconSelect, IPControlIconShuffle };
UIImage *IPControlImage(IPControlIcon kind);
typedef NS_ENUM(NSInteger, IPTabIcon) { IPTabIconServers, IPTabIconPlaylists, IPTabIconFavorites, IPTabIconDownloads };
UIImage *IPTabImage(IPTabIcon kind);

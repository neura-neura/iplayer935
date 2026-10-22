#import "IPStrings.h"
#import "IPMiniRoot.h"
#import "IPNow.h"
#import "IPLegacyAppearance.h"
#import "IPPlayer.h"
#import "IPStore.h"
#import <math.h>
static UIImage *MiniSymbol(NSInteger kind) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(32,32),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();CGContextSetFillColorWithColor(c,
#if defined(IP_IOS6)
[UIColor colorWithWhite:.2 alpha:1].CGColor
#else
[UIColor colorWithRed:1 green:.18 blue:.33 alpha:1].CGColor
#endif
);
    if(kind==1){CGContextFillRect(c,CGRectMake(9,7,4,18));CGContextFillRect(c,CGRectMake(19,7,4,18));}
    else if(kind==2){for(int i=0;i<3;i++)CGContextFillEllipseInRect(c,CGRectMake(6+i*8,14,4,4));}
    else {CGContextMoveToPoint(c,11,6);CGContextAddLineToPoint(c,26,16);CGContextAddLineToPoint(c,11,26);CGContextClosePath(c);CGContextFillPath(c);}
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return image;
}
@interface IPMiniRoot ()
@property(nonatomic,strong) UIView *mini;
@property(nonatomic,strong) UILabel *song,*artist;
@property(nonatomic,strong) UIButton *playButton,*nextButton;
@property(nonatomic,strong) UIView *progress;
@property(nonatomic,strong) UIImage *playIcon,*pauseIcon;
@end
@implementation IPMiniRoot
- (void)viewDidLoad {
    [super viewDidLoad];
    self.mini=[UIView new];self.mini.backgroundColor=[UIColor colorWithWhite:.98 alpha:1];
    UIView *line=[UIView new];line.backgroundColor=[UIColor colorWithWhite:.8 alpha:1];line.frame=CGRectMake(0,0,self.view.bounds.size.width,.5);line.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.mini addSubview:line];
    self.song=[UILabel new];self.song.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];self.song.textAlignment=NSTextAlignmentCenter;[self.mini addSubview:self.song];
    self.artist=[UILabel new];self.artist.font=[UIFont systemFontOfSize:10];self.artist.textAlignment=NSTextAlignmentCenter;self.artist.textColor=[UIColor grayColor];[self.mini addSubview:self.artist];
    UIButton *open=[UIButton buttonWithType:UIButtonTypeCustom];open.tag=91;open.accessibilityLabel=IPL(@"Abrir reproductor completo");[open addTarget:self action:@selector(openPlayer) forControlEvents:UIControlEventTouchUpInside];[self.mini addSubview:open];
    self.playButton=[UIButton buttonWithType:
#if defined(IP_IOS6)
UIButtonTypeCustom
#else
UIButtonTypeSystem
#endif
];self.playIcon=MiniSymbol(0);self.pauseIcon=MiniSymbol(1);[self.playButton addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];[self.mini addSubview:self.playButton];
    self.nextButton=[UIButton buttonWithType:
#if defined(IP_IOS6)
UIButtonTypeCustom
#else
UIButtonTypeSystem
#endif
];[self.nextButton setImage:MiniSymbol(2) forState:0];self.nextButton.accessibilityLabel=IPL(@"Más opciones de reproducción");[self.nextButton addTarget:self action:@selector(more) forControlEvents:UIControlEventTouchUpInside];[self.mini addSubview:self.nextButton];
    self.progress=[UIView new];self.progress.backgroundColor=[UIColor colorWithRed:1 green:.18 blue:.33 alpha:1];[self.mini addSubview:self.progress];
#if defined(IP_IOS6)
    UIImageView *surface=[[UIImageView alloc]initWithImage:IPLegacySurface(NO)];surface.frame=self.mini.bounds;surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.mini insertSubview:surface atIndex:0];
    self.song.backgroundColor=[UIColor clearColor];self.artist.backgroundColor=[UIColor clearColor];
    self.song.font=[UIFont boldSystemFontOfSize:13];self.song.textColor=[UIColor colorWithWhite:.15 alpha:1];
    self.progress.backgroundColor=IPLegacyAccent();
#endif
    [self.view addSubview:self.mini];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"IPPlaybackChanged" object:nil];
    [self refresh];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w=self.view.bounds.size.width,y=self.tabBar.frame.origin.y-48;
    self.mini.frame=CGRectMake(0,y,w,48);
    for(UIViewController *child in self.viewControllers) if(child.isViewLoaded) child.view.frame=CGRectMake(0,0,w,y);
    self.song.frame=CGRectMake(52,8,w-104,19);self.artist.frame=CGRectMake(52,27,w-104,14);
    [self.mini viewWithTag:91].frame=CGRectMake(48,0,w-96,47);self.playButton.frame=CGRectMake(4,0,44,47);self.nextButton.frame=CGRectMake(w-48,0,44,47);
    [self updateProgress];
    [self.view bringSubviewToFront:self.mini];[self.view bringSubviewToFront:self.tabBar];
}
- (void)refresh {
    IPPlayer *p=[IPPlayer shared];NSDictionary *t=p.track;
    self.song.text=t[@"title"]?:IPL(@"Sin reproducción");self.artist.text=t[@"artist"]?:IPL(@"Elige una canción");
    [self.playButton setImage:p.playing?self.pauseIcon:self.playIcon forState:0];self.playButton.accessibilityLabel=p.playing?IPL(@"Pausar"):IPL(@"Reproducir");
    self.playButton.enabled=t!=nil;self.nextButton.enabled=t!=nil;
    [self updateProgress];
}
- (void)openPlayer {
    if(![IPPlayer shared].track || self.presentedViewController)return;
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:[IPNow new]];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)toggle {[[IPPlayer shared]toggle];[self refresh];}
- (void)updateProgress {
    IPPlayer *p=[IPPlayer shared];double d=p.duration,t=p.elapsed;CGFloat fraction=isfinite(d)&&d>0&&isfinite(t)?MAX(0,MIN(1,t/d)):0;
    self.progress.frame=CGRectMake(0,47,self.mini.bounds.size.width*fraction,1);
}
- (void)more {
    if(self.presentedViewController)return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:[IPPlayer shared].track[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:IPL(@"Siguiente canción") style:0 handler:^(UIAlertAction *a){[[IPPlayer shared]next];}]];
    [menu addAction:[UIAlertAction actionWithTitle:IPL(@"Canción anterior") style:0 handler:^(UIAlertAction *a){[[IPPlayer shared]previous];}]];
    NSDictionary *track=[IPPlayer shared].track;
    [menu addAction:[UIAlertAction actionWithTitle:[track[@"favorite"]boolValue]?IPL(@"Quitar favorito"):IPL(@"Marcar favorito") style:0 handler:^(UIAlertAction *a){[[IPStore shared]setFavorite:![track[@"favorite"]boolValue] forTrack:track];}]];
    [menu addAction:[UIAlertAction actionWithTitle:IPL(@"Cancelar") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter]removeObserver:self];}
@end

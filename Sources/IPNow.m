#import "IPStrings.h"
#import "IPLocalLibrary.h"
#import "IPNow.h"
#import "IPLegacyAppearance.h"
#import "IPLegacyPlayerSettings.h"
#import "IPPlayer.h"
#import "IPControlIcons.h"
#import "IPCrossfade.h"
#import "IPCrossfadeSettings.h"
#import "IPStore.h"
#import <MediaPlayer/MediaPlayer.h>

static UIColor *IPAccent(void) {
#if defined(IP_IOS6)
    return IPLegacyAccent();
#else
    return [UIColor colorWithRed:1 green:.18 blue:.33 alpha:1];
#endif
}
static UIImage *IPSymbol(NSInteger kind, BOOL active) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(40, 40), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:
#if defined(IP_IOS6)
.22
#else
.17
#endif
alpha:1].CGColor);
    if (kind == 1 && active) {
        CGContextFillRect(c, CGRectMake(11, 8, 6, 24));
        CGContextFillRect(c, CGRectMake(23, 8, 6, 24));
    } else if (kind == 1) {
        CGContextMoveToPoint(c, 12, 7);
        CGContextAddLineToPoint(c, 32, 20);
        CGContextAddLineToPoint(c, 12, 33);
        CGContextClosePath(c);
        CGContextFillPath(c);
    } else {
        CGContextSaveGState(c);
        if (kind == 0) {
            CGContextTranslateCTM(c, 40, 0);
            CGContextScaleCTM(c, -1, 1);
        }
        for (int i = 0; i < 2; i++) {
            CGFloat x = 6 + i * 13;
            CGContextMoveToPoint(c, x, 10);
            CGContextAddLineToPoint(c, x + 14, 20);
            CGContextAddLineToPoint(c, x, 30);
            CGContextClosePath(c);
            CGContextFillPath(c);
        }
        CGContextRestoreGState(c);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
static UIImage *IPPlaceholder(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(280, 280), YES, 1);
    [[UIColor colorWithWhite:.93 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, 280, 280));
    [@"♫" drawInRect:CGRectMake(45, 45, 190, 190)
        withAttributes:@{
            NSFontAttributeName : [UIFont systemFontOfSize:144 weight:UIFontWeightLight],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:.76 alpha:1]
        }];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
@interface IPNow () <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIImageView *art;
@property(nonatomic, strong) UILabel *titleLabel, *subtitle, *origin, *elapsed, *remaining;
@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, strong) MPVolumeView *volume;
@property(nonatomic, strong) UIButton *previous, *play, *next, *favorite, *queueButton, *shuffleButton;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *artKey;
@property(nonatomic, strong) UIImage *placeholder, *playIcon, *pauseIcon;
#if defined(IP_IOS6)
@property(nonatomic,strong) UIView *scrubPanel,*transportPanel;
@property(nonatomic,strong) UILabel *albumLabel;
@property(nonatomic,strong) UIImage *shuffleOff,*shuffleOn,*routeImage;
@property(nonatomic,strong) NSNumber *appliedDark;
#endif
@end
@implementation IPNow
- (instancetype)init {
    if ((self = [super init]))
        self.hidesBottomBarWhenPushed = YES;
    return self;
}
- (UILabel *)label:(CGFloat)size color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size];
    l.textColor = color;
#if defined(IP_IOS6)
    l.backgroundColor=[UIColor clearColor];
#endif
    l.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:l];
    return l;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    #if defined(IP_IOS6)
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
#else
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
#endif
    [b setTitle:title forState:0];
    b.tintColor = IPAccent();
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.hidesBottomBarWhenPushed = YES;
    self.title = IPL(@"Reproduciendo");
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:IPControlImage(IPControlIconOptions) style:0 target:self action:@selector(audioSettings)];self.navigationItem.rightBarButtonItem.accessibilityLabel=IPL(@"Ajustes de audio");
    self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:IPL(@"Atrás") style:0 target:nil action:nil];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:IPL(@"Atrás") style:UIBarButtonItemStylePlain target:self action:@selector(closePlayer)];
#if defined(IP_IOS6)
    UIPanGestureRecognizer *back=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(edgeBack:)];back.delegate=self;[self.view addGestureRecognizer:back];
#else
    UIScreenEdgePanGestureRecognizer *back=[[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:self action:@selector(edgeBack:)];back.edges=UIRectEdgeLeft;[self.view addGestureRecognizer:back];
    [self.navigationController.interactivePopGestureRecognizer requireGestureRecognizerToFail:back];
#endif
    self.view.backgroundColor = [UIColor colorWithWhite:.985 alpha:1];
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.placeholder = IPPlaceholder();
    self.playIcon = IPSymbol(1, NO);
    self.pauseIcon = IPSymbol(1, YES);
    self.art = [UIImageView new];
    self.art.contentMode = UIViewContentModeScaleAspectFit;
    self.art.backgroundColor = [UIColor colorWithWhite:.93 alpha:1];
    self.art.image = self.placeholder;
    [self.view addSubview:self.art];
    self.titleLabel = [self label:18 color:[UIColor colorWithWhite:.12 alpha:1]];
    self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.subtitle = [self label:13 color:IPAccent()];
    self.origin = [self label:10 color:[UIColor grayColor]];
    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = IPAccent();
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:.85 alpha:1];
    self.slider.accessibilityLabel = IPL(@"Posición de reproducción");
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, 0);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 10, 10)] fill];
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [self.slider setThumbImage:thumb forState:UIControlStateNormal];
    [self.slider addTarget:self
                    action:@selector(seek:)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.slider];
    self.elapsed = [self label:10 color:[UIColor grayColor]];
    self.elapsed.textAlignment = NSTextAlignmentLeft;
    self.remaining = [self label:10 color:[UIColor grayColor]];
    self.remaining.textAlignment = NSTextAlignmentRight;
    self.previous = [self button:nil action:@selector(previousTrack)];
    [self.previous setImage:IPSymbol(0, NO) forState:0];
    self.previous.accessibilityLabel = IPL(@"Canción anterior");
    self.play = [self button:nil action:@selector(toggle)];
    self.play.accessibilityLabel = IPL(@"Reproducir o pausar");
    self.next = [self button:nil action:@selector(nextTrack)];
    [self.next setImage:IPSymbol(2, NO) forState:0];
    self.next.accessibilityLabel = IPL(@"Canción siguiente");
    self.volume = [MPVolumeView new];
    self.volume.tintColor = [UIColor colorWithWhite:.52 alpha:1];
    self.volume.showsRouteButton = YES;
    [self.view addSubview:self.volume];
    self.favorite = [self button:@"♡" action:@selector(favoriteTrack)];
    self.favorite.titleLabel.font = [UIFont systemFontOfSize:26];
    self.favorite.accessibilityLabel = IPL(@"Favorito");
    self.queueButton = [self button:@"☰" action:@selector(showQueue)];
    self.queueButton.titleLabel.font = [UIFont systemFontOfSize:23];
    self.queueButton.accessibilityLabel = IPL(@"A continuación");
    self.shuffleButton=[self button:nil action:@selector(toggleShuffle)];
    [self.shuffleButton setImage:IPControlImage(IPControlIconShuffle) forState:UIControlStateNormal];
    self.shuffleButton.accessibilityLabel=IPL(@"Reproducción aleatoria");
    self.shuffleButton.layer.cornerRadius=6;
    self.shuffleButton.accessibilityHint=IPL(@"Mantén pulsado para suspender o reanudar el fundido cruzado, si está habilitado.");
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(holdShuffle:)];hold.minimumPressDuration=.6;hold.delegate=self;[self.shuffleButton addGestureRecognizer:hold];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(refresh) name:@"IPCrossfadeChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh)
                                                 name:@"IPStoreChanged"
                                               object:nil];
#if defined(IP_IOS6)
    [self installLegacyPlayerAppearance];
    [self applyLegacyPlayerBackground];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=IPL(@"Player settings");
#endif
    [self refresh];
}
#if defined(IP_IOS6)
- (void)installLegacyPlayerAppearance {
    self.view.backgroundColor=[UIColor colorWithWhite:.87 alpha:1];self.art.backgroundColor=[UIColor colorWithWhite:.92 alpha:1];
    UINavigationBar *bar=self.navigationController.navigationBar;bar.barStyle=UIBarStyleDefault;bar.tintColor=[UIColor colorWithWhite:.65 alpha:1];
    [bar setBackgroundImage:IPLegacySurface(NO) forBarMetrics:UIBarMetricsDefault];
    bar.titleTextAttributes=@{UITextAttributeTextColor:[UIColor darkGrayColor],UITextAttributeTextShadowColor:[UIColor whiteColor]};
    UIView *heading=[[UIView alloc]initWithFrame:CGRectMake(0,0,180,43)];
    [heading addSubview:self.titleLabel];[heading addSubview:self.subtitle];
    self.titleLabel.font=[UIFont boldSystemFontOfSize:13];self.titleLabel.textColor=[UIColor colorWithWhite:.15 alpha:1];self.titleLabel.frame=CGRectMake(0,13,180,16);
    self.subtitle.font=[UIFont boldSystemFontOfSize:10];self.subtitle.textColor=[UIColor darkGrayColor];self.subtitle.frame=CGRectMake(0,0,180,13);
    self.albumLabel=[UILabel new];self.albumLabel.font=[UIFont boldSystemFontOfSize:10];self.albumLabel.textColor=[UIColor darkGrayColor];self.albumLabel.backgroundColor=[UIColor clearColor];self.albumLabel.textAlignment=NSTextAlignmentCenter;self.albumLabel.frame=CGRectMake(0,29,180,13);[heading addSubview:self.albumLabel];
    heading.autoresizingMask=UIViewAutoresizingFlexibleWidth;self.navigationItem.titleView=heading;
    self.scrubPanel=[UIView new];self.scrubPanel.backgroundColor=[UIColor colorWithWhite:.94 alpha:.94];[self.view addSubview:self.scrubPanel];
    for(UIView *view in @[self.slider,self.elapsed,self.remaining])[self.scrubPanel addSubview:view];
    self.elapsed.textColor=[UIColor darkGrayColor];self.remaining.textColor=[UIColor darkGrayColor];
    // Native iOS 6 sliders supply the metallic knob, including the volume slider.
    [self.slider setThumbImage:nil forState:UIControlStateNormal];self.slider.minimumTrackTintColor=[UIColor colorWithWhite:.44 alpha:1];self.slider.maximumTrackTintColor=[UIColor colorWithWhite:.75 alpha:1];
    self.transportPanel=[[UIImageView alloc]initWithImage:IPLegacySurface(NO)];self.transportPanel.userInteractionEnabled=YES;[self.view insertSubview:self.transportPanel aboveSubview:self.art];
    for(UIButton *button in @[self.previous,self.play,self.next]){
        [button setBackgroundImage:IPLegacyButton(NO,NO) forState:UIControlStateNormal];[button setBackgroundImage:IPLegacyButton(YES,NO) forState:UIControlStateHighlighted];[button setBackgroundImage:IPLegacyButton(YES,NO) forState:UIControlStateSelected];
    }
    for(UIButton *button in @[self.favorite,self.queueButton]){[button setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];[button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];button.titleLabel.shadowOffset=CGSizeMake(0,1);}
    self.shuffleOff=IPLegacyTint(IPControlImage(IPControlIconShuffle),[UIColor darkGrayColor]);self.shuffleOn=IPLegacyTint(IPControlImage(IPControlIconShuffle),IPLegacyAccent());
    // Keep the route control legible against the silver panel.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24,20),NO,0);
    CGContextRef route=UIGraphicsGetCurrentContext();CGContextSetStrokeColorWithColor(route,[UIColor darkGrayColor].CGColor);CGContextSetFillColorWithColor(route,[UIColor darkGrayColor].CGColor);CGContextSetLineWidth(route,1.5);
    CGContextMoveToPoint(route,3,13);CGContextAddLineToPoint(route,3,3);CGContextAddLineToPoint(route,21,3);CGContextAddLineToPoint(route,21,13);CGContextStrokePath(route);
    CGContextMoveToPoint(route,12,10);CGContextAddLineToPoint(route,5,18);CGContextAddLineToPoint(route,19,18);CGContextClosePath(route);CGContextFillPath(route);
    UIImage *routeImage=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();self.routeImage=routeImage;
    [self.volume setRouteButtonImage:routeImage forState:UIControlStateNormal];[self.volume setRouteButtonImage:IPLegacyTint(routeImage,IPLegacyAccent()) forState:UIControlStateHighlighted];
    self.origin.textColor=[UIColor colorWithWhite:.36 alpha:1];self.origin.font=[UIFont systemFontOfSize:9];
    self.art.userInteractionEnabled=YES;UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(toggleLegacyScrubber)];[self.art addGestureRecognizer:tap];
}
- (void)applyLegacyPlayerBackground {
    BOOL dark=IPLegacyPlayerIsDark();if(self.appliedDark&&self.appliedDark.boolValue==dark)return;
    self.appliedDark=@(dark);
    UIColor *foreground=dark?[UIColor lightGrayColor]:[UIColor darkGrayColor],*shadow=dark?[UIColor blackColor]:[UIColor whiteColor];
    self.view.backgroundColor=[UIColor colorWithWhite:dark?.06:.87 alpha:1];self.art.backgroundColor=[UIColor colorWithWhite:dark?.08:.92 alpha:1];
    UINavigationBar *bar=self.navigationController.navigationBar;bar.barStyle=dark?UIBarStyleBlack:UIBarStyleDefault;bar.tintColor=[UIColor colorWithWhite:dark?.14:.65 alpha:1];
    [bar setBackgroundImage:IPLegacySurface(dark) forBarMetrics:UIBarMetricsDefault];bar.titleTextAttributes=@{UITextAttributeTextColor:foreground,UITextAttributeTextShadowColor:shadow};
    self.titleLabel.textColor=dark?[UIColor whiteColor]:[UIColor colorWithWhite:.15 alpha:1];self.subtitle.textColor=foreground;self.albumLabel.textColor=foreground;
    self.scrubPanel.backgroundColor=[UIColor colorWithWhite:dark?0:.94 alpha:dark?.72:.94];self.elapsed.textColor=foreground;self.remaining.textColor=foreground;
    self.slider.minimumTrackTintColor=[UIColor colorWithWhite:dark?.7:.44 alpha:1];self.slider.maximumTrackTintColor=[UIColor colorWithWhite:dark?.25:.75 alpha:1];
    [(UIImageView *)self.transportPanel setImage:IPLegacySurface(dark)];
    self.playIcon=IPLegacyTint(IPSymbol(1,NO),foreground);self.pauseIcon=IPLegacyTint(IPSymbol(1,YES),foreground);
    [self.previous setImage:IPLegacyTint(IPSymbol(0,NO),foreground) forState:UIControlStateNormal];[self.next setImage:IPLegacyTint(IPSymbol(2,NO),foreground) forState:UIControlStateNormal];
    for(UIButton *button in @[self.previous,self.play,self.next]){[button setBackgroundImage:IPLegacyButton(NO,dark) forState:UIControlStateNormal];[button setBackgroundImage:IPLegacyButton(YES,dark) forState:UIControlStateHighlighted];[button setBackgroundImage:IPLegacyButton(YES,dark) forState:UIControlStateSelected];}
    for(UIButton *button in @[self.favorite,self.queueButton]){[button setTitleColor:foreground forState:UIControlStateNormal];[button setTitleShadowColor:shadow forState:UIControlStateNormal];button.titleLabel.shadowOffset=CGSizeMake(0,dark?-1:1);}
    self.shuffleOff=IPLegacyTint(IPControlImage(IPControlIconShuffle),foreground);
    [self.volume setRouteButtonImage:IPLegacyTint(self.routeImage,foreground) forState:UIControlStateNormal];
    self.origin.textColor=[UIColor colorWithWhite:dark?.6:.36 alpha:1];
}
- (void)toggleLegacyScrubber {self.scrubPanel.hidden=!self.scrubPanel.hidden;}
#endif
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
#if defined(IP_IOS6)
    CGFloat art=MIN(w,MAX(100,h-174));
    self.art.frame=CGRectMake((w-art)/2,0,art,art);
    self.scrubPanel.frame=CGRectMake((w-art)/2,0,art,49);
    self.slider.frame=CGRectMake(20,0,art-40,29);self.elapsed.frame=CGRectMake(22,29,70,15);self.remaining.frame=CGRectMake(art-92,29,70,15);
    self.transportPanel.frame=CGRectMake(0,art,w,h-art);
    CGFloat width=MIN(88,(w-24)/3),left=(w-width*3)/2;
    self.previous.frame=CGRectMake(left,art+7,width,49);self.play.frame=CGRectMake(left+width,art+7,width,49);self.next.frame=CGRectMake(left+2*width,art+7,width,49);
    self.volume.frame=CGRectMake(30,art+64,w-60,30);
    self.favorite.frame=CGRectMake(24,art+101,46,42);self.shuffleButton.frame=CGRectMake(w/2-23,art+101,46,42);self.queueButton.frame=CGRectMake(w-70,art+101,46,42);
    self.origin.frame=CGRectMake(12,h-22,w-24,15);
#else
    CGFloat art = MIN(w - 40, MAX(160, h - 258));
    self.art.frame = CGRectMake((w - art) / 2, 10, art, art);
    CGFloat y = art + 20;
    self.titleLabel.frame = CGRectMake(20, y, w - 40, 24);
    self.subtitle.frame = CGRectMake(20, y + 25, w - 40, 19);
    self.origin.frame = CGRectMake(20, y + 44, w - 40, 14);
    self.slider.frame = CGRectMake(24, y + 58, w - 48, 28);
    self.elapsed.frame = CGRectMake(25, y + 82, 80, 14);
    self.remaining.frame = CGRectMake(w - 105, y + 82, 80, 14);
    self.previous.frame = CGRectMake(w / 2 - 110, y + 102, 60, 50);
    self.play.frame = CGRectMake(w / 2 - 30, y + 102, 60, 50);
    self.next.frame = CGRectMake(w / 2 + 50, y + 102, 60, 50);
    self.volume.frame = CGRectMake(35, y + 158, w - 70, 30);
    self.favorite.frame = CGRectMake(19, h - 44, 46, 40);
    self.queueButton.frame = CGRectMake(w - 65, h - 44, 46, 40);
    self.shuffleButton.frame=CGRectMake(w/2-23,h-44,46,40);
#endif
}
#if defined(IP_IOS6)
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if(![gesture isKindOfClass:[UIPanGestureRecognizer class]])return [IPPlayer shared].crossfade.enabled&&[IPPlayer shared].crossfade.sessionControl;
    CGPoint origin=[gesture locationInView:self.view];CGPoint motion=[(UIPanGestureRecognizer *)gesture translationInView:self.view];
    return origin.x-motion.x<=24&&motion.x>0&&fabs(motion.x)>fabs(motion.y);
}
#endif
- (void)edgeBack:(UIPanGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateEnded)return;
    CGFloat x=[gesture translationInView:self.view].x,velocity=[gesture velocityInView:self.view].x;
    if(x>MAX(60,self.view.bounds.size.width*.22)||(x>20&&velocity>450))[self closePlayer];
}
- (void)closePlayer {
    if(self.navigationController.viewControllers.firstObject==self) [self dismissViewControllerAnimated:YES completion:nil];
    else [self.navigationController popViewControllerAnimated:YES];
}
- (NSString *)time:(double)t {
    if (!isfinite(t) || t < 0)
        return @"–:––";
    return [NSString stringWithFormat:@"%ld:%02ld", (long)t / 60, (long)t % 60];
}
- (void)refresh {
    IPPlayer *p = [IPPlayer shared];
    NSDictionary *t = p.track;
    self.titleLabel.text = t[@"title"] ?: IPL(@"Elige una canción");
    NSString *artist = t[@"artist"], *album = t[@"album"];
    self.subtitle.text = artist.length && album.length
                             ? [NSString stringWithFormat:@"%@ — %@", artist, album]
                         : artist.length ? artist
                         : album.length  ? album
                                         : @"";
#if defined(IP_IOS6)
    self.subtitle.text=artist?:@"";self.albumLabel.text=album?:@"";
#endif
    NSDictionary *profile = [[IPStore shared] profileForTrack:t];
    self.origin.text=[NSString stringWithFormat:@"%@%@",[[IPStore shared]localURL:t]?IPL(@"En el iPod · "):@"",IPProfileName(profile)?:t[@"sourceName"]?:@""];
    if(p.seeking)self.origin.text=[self.origin.text stringByAppendingString:IPL(@" · Buscando…")];
    if(p.crossfade.enabled)self.origin.text=[self.origin.text stringByAppendingString:p.crossfade.sessionSuspended?IPL(@" · Fundido suspendido"):IPL(@" · Fundido activo")];
    NSString *key = [NSString stringWithFormat:@"%@/%@", t[@"id"], t[@"artwork"]];
    if (![key isEqual:self.artKey]) {
        self.artKey = key;
        NSURL *u = [[IPStore shared] artworkURLForTrack:t];
        self.art.image = (u ? [UIImage imageWithContentsOfFile:u.path] : nil) ?: self.placeholder;
    }
    double d = p.duration, v = p.elapsed;
    if (!self.slider.tracking)
        self.slider.value = isfinite(d) && d > 0 && isfinite(v) ? v / d : 0;
    self.elapsed.text = [self time:v];
    self.remaining.text = isfinite(d) && isfinite(v)
                              ? [@"−" stringByAppendingString:[self time:MAX(0, d - v)]]
                              : @"–:––";
    [self.play setImage:p.playing ? self.pauseIcon : self.playIcon forState:0];
    [self.favorite setTitle:[t[@"favorite"] boolValue] ? @"♥" : @"♡" forState:0];
#if defined(IP_IOS6)
    self.play.selected=p.playing;
    [self.favorite setTitleColor:[t[@"favorite"]boolValue]?IPLegacyAccent():(self.appliedDark.boolValue?[UIColor lightGrayColor]:[UIColor darkGrayColor]) forState:UIControlStateNormal];
    [self.shuffleButton setImage:p.shuffleEnabled?self.shuffleOn:self.shuffleOff forState:UIControlStateNormal];
#endif
    self.shuffleButton.tintColor=p.shuffleEnabled?IPAccent():[UIColor grayColor];
    self.shuffleButton.backgroundColor=p.shuffleEnabled?[IPAccent() colorWithAlphaComponent:.12]:[UIColor clearColor];
    self.shuffleButton.accessibilityValue=p.shuffleEnabled?IPL(@"Activada"):IPL(@"Desactivada");
    self.shuffleButton.accessibilityTraits=UIAccessibilityTraitButton|(p.shuffleEnabled?UIAccessibilityTraitSelected:0);
}
- (void)seek:(UISlider *)s {
    [[IPPlayer shared] seek:s.value];
}
- (void)previousTrack {
    [[IPPlayer shared] previous];
    [self refresh];
}
- (void)nextTrack {
    [[IPPlayer shared] next];
    [self refresh];
}
- (void)toggle {
    [[IPPlayer shared] toggle];
    [self refresh];
}
- (void)audioSettings {
#if defined(IP_IOS6)
    [self.navigationController pushViewController:[IPLegacyPlayerSettings new] animated:YES];
#else
    [self.navigationController pushViewController:[IPCrossfadeSettings new] animated:YES];
#endif
}
#if !defined(IP_IOS6)
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {return [IPPlayer shared].crossfade.enabled&&[IPPlayer shared].crossfade.sessionControl;}
#endif
- (void)holdShuffle:(UILongPressGestureRecognizer *)gesture {if(gesture.state==UIGestureRecognizerStateBegan)[[IPPlayer shared]toggleCrossfadeSession];}
- (void)toggleShuffle {[[IPPlayer shared]toggleShuffle];[self refresh];}
- (void)favoriteTrack {
    NSDictionary *t = [IPPlayer shared].track;
    [[IPStore shared] setFavorite:![t[@"favorite"] boolValue] forTrack:t];
    [self refresh];
}
- (void)showQueue {
    IPPlayer *p = [IPPlayer shared];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:IPL(@"A continuación")
                         message:[NSString stringWithFormat:IPL(@"%ld de %lu"), (long)p.index + 1,
                                                            (unsigned long)p.queue.count]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = p.index + 1; i < MIN((NSInteger)p.queue.count, p.index + 6); i++) {
        NSInteger idx = i;
        NSDictionary *t = p.queue[i];
        [a addAction:[UIAlertAction actionWithTitle:t[@"title"] ?: IPL(@"Canción")
                                              style:0
                                            handler:^(UIAlertAction *x) {
                                                [p playTracks:p.queue index:idx];
                                                [self refresh];
                                            }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:IPL(@"Cancelar")
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
#if defined(IP_IOS6)
    // Settings temporarily use the silver navigation bar; restore even if the choice is unchanged.
    self.appliedDark=nil;[self applyLegacyPlayerBackground];
#endif
    if (!self.timer)
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1
                                                      target:self
                                                    selector:@selector(refresh)
                                                    userInfo:nil
                                                     repeats:YES];
    [self refresh];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 1);
        #if defined(IP_IOS6)
        [self.view.layer renderInContext:UIGraphicsGetCurrentContext()];
#else
        [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
#endif
        UIImage *preview=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSURL *url=[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"player-preview.png"];
        [UIImagePNGRepresentation(preview)writeToURL:url atomically:YES];
    });
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end

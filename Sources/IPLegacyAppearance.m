#import "IPLegacyAppearance.h"
#if defined(IP_IOS6)
static void Gradient(CGRect rect,CGFloat top,CGFloat bottom) {
    CGContextRef c=UIGraphicsGetCurrentContext();CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGFloat stops[]={top,top,top,1,bottom,bottom,bottom,1};
    CGGradientRef gradient=CGGradientCreateWithColorComponents(space,stops,NULL,2);
    CGContextDrawLinearGradient(c,gradient,CGPointMake(0,rect.origin.y),CGPointMake(0,CGRectGetMaxY(rect)),0);
    CGGradientRelease(gradient);CGColorSpaceRelease(space);
}
UIColor *IPLegacyAccent(void){return [UIColor colorWithRed:.94 green:.43 blue:.08 alpha:1];}
UIImage *IPLegacySurface(BOOL dark){
    static UIImage *light,*black;static dispatch_once_t once;
    dispatch_once(&once,^{
        for(int i=0;i<2;i++){
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(2,44),YES,0);
            Gradient(CGRectMake(0,0,2,44),i?.20:.97,i?.055:.73);
            [[UIColor colorWithWhite:i?.33:1 alpha:1]setFill];UIRectFill(CGRectMake(0,0,2,.5));
            [[UIColor colorWithWhite:i?0:.52 alpha:1]setFill];UIRectFill(CGRectMake(0,43.5,2,.5));
            UIImage *image=[UIGraphicsGetImageFromCurrentImageContext()resizableImageWithCapInsets:UIEdgeInsetsZero];
            UIGraphicsEndImageContext();if(i)black=image;else light=image;
        }
    });return dark?black:light;
}
UIImage *IPLegacyButton(BOOL pressed){
    static UIImage *normal,*down;static dispatch_once_t once;
    dispatch_once(&once,^{for(int i=0;i<2;i++){
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(44,44),NO,0);
        UIBezierPath *path=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(.5,.5,43,43) cornerRadius:5];
        CGContextSaveGState(UIGraphicsGetCurrentContext());[path addClip];Gradient(CGRectMake(0,0,44,44),i?.09:.23,i?.16:.065);CGContextRestoreGState(UIGraphicsGetCurrentContext());
        [[UIColor colorWithWhite:0 alpha:.9]setStroke];path.lineWidth=1;[path stroke];
        UIImage *image=[UIGraphicsGetImageFromCurrentImageContext()resizableImageWithCapInsets:UIEdgeInsetsMake(7,7,7,7)];
        UIGraphicsEndImageContext();if(i)down=image;else normal=image;
    }});return pressed?down:normal;
}
UIImage *IPLegacyTint(UIImage *image,UIColor *color){
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale);
    CGRect rect=(CGRect){CGPointZero,image.size};[image drawInRect:rect];
    [color setFill];UIRectFillUsingBlendMode(rect,kCGBlendModeSourceIn);
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return result;
}
void IPLegacyInstallAppearance(void){
    UINavigationBar *nav=[UINavigationBar appearance];nav.tintColor=[UIColor colorWithWhite:.65 alpha:1];
    [nav setBackgroundImage:IPLegacySurface(NO) forBarMetrics:UIBarMetricsDefault];
    nav.titleTextAttributes=@{UITextAttributeTextColor:[UIColor colorWithWhite:.18 alpha:1],UITextAttributeTextShadowColor:[UIColor whiteColor],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,1)]};
    [UIBarButtonItem appearance].tintColor=[UIColor colorWithWhite:.62 alpha:1];
    UITabBar *tabs=[UITabBar appearance];tabs.backgroundImage=IPLegacySurface(NO);tabs.selectedImageTintColor=[UIColor colorWithWhite:.25 alpha:1];
    // A recessed selection instead of the system's blue glow. Generated once at launch.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(80,49),YES,0);
    Gradient(CGRectMake(0,0,80,49),.59,.84);
    [[UIColor colorWithWhite:.4 alpha:1]setFill];UIRectFill(CGRectMake(0,0,80,1));UIRectFill(CGRectMake(0,0,1,49));
    [[UIColor colorWithWhite:1 alpha:.8]setFill];UIRectFill(CGRectMake(79,0,1,49));
    tabs.selectionIndicatorImage=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    [[UITabBarItem appearance]setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor darkGrayColor],UITextAttributeTextShadowColor:[UIColor whiteColor],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,1)]} forState:UIControlStateNormal];
    [[UITabBarItem appearance]setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor blackColor]} forState:UIControlStateSelected];
    [UISearchBar appearance].tintColor=[UIColor colorWithWhite:.78 alpha:1];
    [UISlider appearance].minimumTrackTintColor=[UIColor colorWithWhite:.52 alpha:1];
    [UISlider appearance].maximumTrackTintColor=[UIColor colorWithWhite:.25 alpha:1];
}
#endif

#if defined(IP_IOS6)
#import <UIKit/UIKit.h>
UIColor *IPLegacyAccent(void);
UIImage *IPLegacySurface(BOOL dark);
UIImage *IPLegacyButton(BOOL pressed);
UIImage *IPLegacyTint(UIImage *image,UIColor *color);
void IPLegacyInstallAppearance(void);
#endif

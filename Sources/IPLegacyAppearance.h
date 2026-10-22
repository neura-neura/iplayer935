#if defined(IP_IOS6)
#import <UIKit/UIKit.h>
UIColor *IPLegacyAccent(void);
UIImage *IPLegacySurface(BOOL dark);
BOOL IPLegacyPlayerIsDark(void);
UIImage *IPLegacyButton(BOOL pressed,BOOL dark);
UIImage *IPLegacyTint(UIImage *image,UIColor *color);
void IPLegacyInstallAppearance(void);
#endif

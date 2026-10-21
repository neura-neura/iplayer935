#import <Foundation/Foundation.h>

/** Uses the primary system language only; other languages fall back to English. */
FOUNDATION_EXPORT NSString *IPLanguageForIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *IPInterfaceLanguage(void);
FOUNDATION_EXPORT NSString *IPL(NSString *key);

FOUNDATION_EXPORT NSString * const IPLanguageChangedNotification;
/** system (default), en, es, or zh-Hans. The setting affects only this app. */
FOUNDATION_EXPORT NSString *IPLanguagePreference(void);
FOUNDATION_EXPORT void IPSetLanguagePreference(NSString *preference);
FOUNDATION_EXPORT void IPRefreshSystemLanguage(void);

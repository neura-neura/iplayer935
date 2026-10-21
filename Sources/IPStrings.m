#import "IPStrings.h"

NSString * const IPLanguageChangedNotification = @"IPLanguageChanged";
static NSString * const IPPreferenceKey = @"IPInterfaceLanguagePreference";

NSString *IPLanguageForIdentifier(NSString *identifier) {
    NSString *base = [[[identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString]
                      componentsSeparatedByString:@"-"].firstObject;
    if ([base isEqualToString:@"es"]) return @"es";
    if ([base isEqualToString:@"zh"]) return @"zh-Hans";
    return @"en";
}

static NSString *ValidPreference(NSString *value) {
    return [@[@"en", @"es", @"zh-Hans"] containsObject:value ?: @""] ? value : @"system";
}

@interface IPStringCatalog : NSObject
@property(atomic, strong) NSDictionary *snapshot;
@property(nonatomic, strong) NSDictionary *english;
- (BOOL)update;
@end
@implementation IPStringCatalog
- (NSDictionary *)readLanguage:(NSString *)language {
    // Read an explicit resource path: do not rely on NSBundle's cached language negotiation.
    NSString *path = [[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:[language stringByAppendingString:@".lproj"]] stringByAppendingPathComponent:@"Localizable.strings"];
    return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}
- (instancetype)init {
    if ((self = [super init])) { _english = [self readLanguage:@"en"]; [self update]; }
    return self;
}
- (BOOL)update {
    @synchronized (self) {
        NSString *preference = ValidPreference([[NSUserDefaults standardUserDefaults] stringForKey:IPPreferenceKey]);
        NSString *language = [preference isEqual:@"system"] ? IPLanguageForIdentifier([NSLocale preferredLanguages].firstObject) : preference;
        NSDictionary *old = self.snapshot;
        if ([old[@"language"] isEqual:language] && [old[@"preference"] isEqual:preference]) return NO;
        NSDictionary *strings = old[@"strings"];
        if (![old[@"language"] isEqual:language]) {
            NSMutableDictionary *merged = [self.english mutableCopy];
            if (![language isEqual:@"en"]) [merged addEntriesFromDictionary:[self readLanguage:language]];
            strings = [merged copy];
        }
        // One atomic immutable snapshot keeps background lookups safe during a switch.
        self.snapshot = @{@"language":language, @"preference":preference, @"strings":strings};
        return YES;
    }
}
@end
static IPStringCatalog *Catalog(void) {
    static IPStringCatalog *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [IPStringCatalog new]; });
    return catalog;
}
static void NotifyLanguageChanged(void) {
    void (^notify)(void) = ^{ [[NSNotificationCenter defaultCenter] postNotificationName:IPLanguageChangedNotification object:nil]; };
    if ([NSThread isMainThread]) notify(); else dispatch_async(dispatch_get_main_queue(), notify);
}
NSString *IPInterfaceLanguage(void) { return Catalog().snapshot[@"language"]; }
NSString *IPLanguagePreference(void) { return Catalog().snapshot[@"preference"]; }
void IPSetLanguagePreference(NSString *preference) {
    IPStringCatalog *catalog = Catalog();
    [[NSUserDefaults standardUserDefaults] setObject:ValidPreference(preference) forKey:IPPreferenceKey];
    if ([catalog update]) NotifyLanguageChanged();
}
void IPRefreshSystemLanguage(void) { if ([Catalog() update]) NotifyLanguageChanged(); }
NSString *IPL(NSString *key) { return Catalog().snapshot[@"strings"][key] ?: key; }

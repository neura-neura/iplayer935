#import "IPStrings.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc > 1, @"Expected interface language argument");
        NSDictionary *cases = @{@"es-MX":@"es", @"es_419":@"es", @"en-GB":@"en",
                                @"zh-CN":@"zh-Hans", @"zh-Hant-TW":@"zh-Hans", @"zh_HK":@"zh-Hans",
                                @"fr-FR":@"en", @"ja":@"en", @"":@"en", @"esoteric":@"en"};
        for (NSString *identifier in cases) NSCAssert([IPLanguageForIdentifier(identifier) isEqual:cases[identifier]], @"Wrong locale mapping: %@", identifier);
        NSCAssert([IPLanguageForIdentifier(nil) isEqual:@"en"], @"Missing language must use English");
        NSString *language = [NSString stringWithUTF8String:argv[1]];
        if (argc > 2 && strcmp(argv[2], "restored") == 0) {
            NSCAssert([IPLanguagePreference() isEqual:@"zh-Hans"], @"Explicit preference did not survive process restart");
        }
        NSCAssert([IPInterfaceLanguage() isEqual:language], @"Unexpected language: %@", IPInterfaceLanguage());
        NSDictionary *labels = @{@"en":@"Servers", @"es":@"Servidores", @"zh-Hans":@"服务器"};
        NSCAssert([IPL(@"Servidores") isEqual:labels[language]], @"Wrong server label: %@", IPL(@"Servidores"));
        NSCAssert([IPL(@"__missing_key__") isEqual:@"__missing_key__"], @"Unknown keys must remain unchanged");
        NSString *credit = IPL(@"Hecho por: neura-neura");
        NSCAssert([credit rangeOfString:@"neura-neura"].location != NSNotFound, @"Credit link lost its target");
        NSCAssert([IPL(@"__fallback_probe__") isEqual:@"English fallback"], @"Missing locale entry did not fall back to English");
        dispatch_apply(2000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
            NSCAssert([IPL(@"Servidores") isEqual:labels[language]], @"Concurrent lookup changed language");
        });
        if (argc > 2 && strcmp(argv[2], "persist") == 0) {
            IPSetLanguagePreference(@"zh-Hans");
            [[NSUserDefaults standardUserDefaults] synchronize];
            puts("Saved explicit Chinese preference for next process");
            return 0;
        }
        __block NSUInteger changes = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:IPLanguageChangedNotification object:nil queue:nil usingBlock:^(NSNotification *n) { changes++; }];
        for (NSString *choice in @[@"en", @"es", @"zh-Hans"]) {
            IPSetLanguagePreference(choice);
            NSCAssert([IPLanguagePreference() isEqual:choice] && [IPInterfaceLanguage() isEqual:choice], @"Explicit choice was not applied immediately");
            NSCAssert([IPL(@"Servidores") isEqual:labels[choice]], @"Catalog stayed in the previous language");
        }
        NSUInteger previous = changes;
        IPSetLanguagePreference(@"zh-Hans");
        NSCAssert(changes == previous, @"Choosing the same language must not rebuild UI");
        IPSetLanguagePreference(@"unsupported");
        NSCAssert([IPLanguagePreference() isEqual:@"system"], @"Invalid preference must use the system setting");
        NSString *system = IPLanguageForIdentifier([NSLocale preferredLanguages].firstObject);
        NSCAssert([IPInterfaceLanguage() isEqual:system] && [IPL(@"Servidores") isEqual:labels[system]], @"System selection failed after explicit choice");
        previous = changes;
        IPRefreshSystemLanguage();
        NSCAssert(changes == previous, @"An unchanged system language must not rebuild UI");
        dispatch_group_t readers = dispatch_group_create();
        NSSet *validLabels = [NSSet setWithArray:labels.allValues];
        for (NSUInteger reader = 0; reader < 4; reader++) dispatch_group_async(readers, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (NSUInteger i = 0; i < 2000; i++) {
                @autoreleasepool { NSCAssert([validLabels containsObject:IPL(@"Servidores")], @"Partial catalog during switch"); }
            }
        });
        for (NSString *choice in @[@"en", @"es", @"zh-Hans", @"system"]) IPSetLanguagePreference(choice);
        dispatch_group_wait(readers, DISPATCH_TIME_FOREVER);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IPInterfaceLanguagePreference"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        printf("Localization passed: %s, system/explicit selection, immediate switching, fallback, author link and concurrent lookups\n", language.UTF8String);
    }
    return 0;
}

// Compiled and force-included only in the separate iOS 6 target.
#if defined(IP_IOS6) && defined(__OBJC__)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#define UITableViewCellAccessoryDetailButton UITableViewCellAccessoryDetailDisclosureButton
#define UITableViewCellSelectionStyleDefault UITableViewCellSelectionStyleBlue
#define UIFontWeightLight (-0.4)
#define UIFontWeightMedium (0.23)
@interface IPLegacyAlertAction : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic) NSInteger style;
@property(nonatomic,copy) void (^handler)(IPLegacyAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(IPLegacyAlertAction *))handler;
@end
@interface IPLegacyAlertController : UIViewController <UIAlertViewDelegate,UIActionSheetDelegate>
@property(nonatomic,readonly) NSArray<UITextField *> *textFields;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style;
- (void)addAction:(IPLegacyAlertAction *)action;
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))handler;
- (void)showFrom:(UIViewController *)parent;
@end
@class IPLegacySearchController;
@protocol IPLegacySearchResultsUpdating <NSObject>
- (void)updateSearchResultsForSearchController:(IPLegacySearchController *)controller;
@end
@interface IPLegacySearchController : NSObject <UISearchBarDelegate>
@property(nonatomic,strong,readonly) UISearchBar *searchBar;
@property(nonatomic,weak) id<IPLegacySearchResultsUpdating> searchResultsUpdater;
@property(nonatomic) BOOL dimsBackgroundDuringPresentation;
- (instancetype)initWithSearchResultsController:(UIViewController *)controller;
@end
@interface IPLegacyURLComponents : NSObject
@property(nonatomic,copy,readonly) NSString *host,*path;
+ (instancetype)componentsWithString:(NSString *)string;
@end
#define UIAlertController IPLegacyAlertController
#define UIAlertAction IPLegacyAlertAction
#define UISearchController IPLegacySearchController
#define UISearchResultsUpdating IPLegacySearchResultsUpdating
#define NSURLComponents IPLegacyURLComponents
#endif

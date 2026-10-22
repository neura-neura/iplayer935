#if defined(IP_IOS6)
#import "IPLegacyCompatibility.h"
#import <objc/runtime.h>
#import "IPPlayer.h"

@implementation IPLegacyAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(IPLegacyAlertAction *))handler {
    IPLegacyAlertAction *a=[self new];a.title=title;a.style=style;a.handler=handler;return a;
}
@end
@interface IPLegacyAlertController ()
@property(nonatomic,copy) NSString *messageText;
@property(nonatomic) NSInteger menuStyle;
@property(nonatomic,strong) NSMutableArray *items,*fields;
@property(nonatomic,strong) id nativeAlert;
@end
static NSMutableSet *activeAlerts;
@implementation IPLegacyAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style {
    IPLegacyAlertController *a=[self new];a.title=title;a.messageText=message;a.menuStyle=style;a.items=[NSMutableArray new];a.fields=[NSMutableArray new];return a;
}
- (NSArray *)textFields {return self.fields;}
- (void)addAction:(IPLegacyAlertAction *)action {[self.items addObject:action];}
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))handler {
    UITextField *field=[UITextField new];if(handler)handler(field);[self.fields addObject:field];
}
- (void)showFrom:(UIViewController *)parent {
    if(!activeAlerts)activeAlerts=[NSMutableSet new];[activeAlerts addObject:self];
    if(self.menuStyle==UIAlertControllerStyleActionSheet){
        UIActionSheet *sheet=[[UIActionSheet alloc]initWithTitle:self.messageText.length?[NSString stringWithFormat:@"%@\n%@",self.title?:@"",self.messageText]:self.title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        for(IPLegacyAlertAction *a in self.items){NSInteger i=[sheet addButtonWithTitle:a.title];if(a.style==UIAlertActionStyleCancel)sheet.cancelButtonIndex=i;else if(a.style==UIAlertActionStyleDestructive)sheet.destructiveButtonIndex=i;}
        self.nativeAlert=sheet;[sheet showInView:parent.view.window?:parent.view];
    }else{
        UIAlertView *alert=[[UIAlertView alloc]initWithTitle:self.title message:self.messageText delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
        for(IPLegacyAlertAction *a in self.items){NSInteger i=[alert addButtonWithTitle:a.title];if(a.style==UIAlertActionStyleCancel)alert.cancelButtonIndex=i;}
        if(self.fields.count){UITextField *configured=self.fields[0];alert.alertViewStyle=UIAlertViewStylePlainTextInput;UITextField *actual=[alert textFieldAtIndex:0];actual.text=configured.text;actual.placeholder=configured.placeholder;actual.keyboardType=configured.keyboardType;actual.autocapitalizationType=configured.autocapitalizationType;actual.secureTextEntry=configured.secureTextEntry;self.fields[0]=actual;}
        self.nativeAlert=alert;[alert show];
    }
}
- (void)complete:(NSInteger)index {
    // Release action blocks after dismissal: callers can capture their alert to read text fields.
    IPLegacyAlertAction *action=index>=0&&(NSUInteger)index<self.items.count?self.items[index]:nil;
    void (^handler)(IPLegacyAlertAction *)=[action.handler copy];
    for(IPLegacyAlertAction *a in self.items)a.handler=nil;
    self.nativeAlert=nil;[activeAlerts removeObject:self];if(handler)handler(action);
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {[self complete:index];}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {[self complete:index];}
@end
@implementation IPLegacySearchController
- (instancetype)initWithSearchResultsController:(UIViewController *)controller {if((self=[super init])){_searchBar=[[UISearchBar alloc]initWithFrame:CGRectMake(0,0,320,44)];_searchBar.delegate=self;}return self;}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {[self.searchResultsUpdater updateSearchResultsForSearchController:self];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {[bar resignFirstResponder];}
@end
@interface IPLegacyURLComponents ()
@property(nonatomic,copy,readwrite) NSString *host,*path;
@end
@implementation IPLegacyURLComponents
+ (instancetype)componentsWithString:(NSString *)string {
    // NSURL in iOS 6 requires escaping spaces/Unicode before parsing; its path is decoded.
    NSURL *url=[NSURL URLWithString:[string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if(!url)return nil;IPLegacyURLComponents *c=[self new];c.host=url.host;c.path=url.path;return c;
}
@end
// These categories are linked only into the iOS 6 IPA. They never patch the iOS 9 process.
@implementation NSArray (IPLegacyFirst)
- (id)firstObject {return self.count?self[0]:nil;}
@end
@implementation NSString (IPLegacyString)
- (BOOL)containsString:(NSString *)value {return [self rangeOfString:value].location!=NSNotFound;}
- (CGRect)boundingRectWithSize:(CGSize)size options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attributes context:(NSStringDrawingContext *)context {
    return (CGRect){CGPointZero,[self sizeWithFont:attributes[NSFontAttributeName]?:[UIFont systemFontOfSize:17] constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping]};
}
- (void)drawInRect:(CGRect)rect withAttributes:(NSDictionary *)attributes {
    [(UIColor *)attributes[NSForegroundColorAttributeName] set];[self drawInRect:rect withFont:attributes[NSFontAttributeName]?:[UIFont systemFontOfSize:17]];
}
@end
@implementation UIFont (IPLegacyWeight)
+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight {return weight>0?[UIFont boldSystemFontOfSize:size]:[UIFont systemFontOfSize:size];}
@end
@implementation UIImage (IPLegacyRendering)
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)mode {return self;}
@end
@implementation UIView (IPLegacyTint)
- (UIColor *)tintColor {return objc_getAssociatedObject(self,@selector(tintColor))?:[UIColor colorWithRed:1 green:.18 blue:.33 alpha:1];}
- (void)setTintColor:(UIColor *)color {objc_setAssociatedObject(self,@selector(tintColor),color,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if([self isKindOfClass:[UIButton class]])[(UIButton *)self setTitleColor:color forState:UIControlStateNormal];}
@end
@implementation UIScrollView (IPLegacyKeyboard)
- (void)setKeyboardDismissMode:(UIScrollViewKeyboardDismissMode)mode {}
@end
@implementation UIViewController (IPLegacyPresentation)
+ (void)load {
    Method a=class_getInstanceMethod(self,@selector(presentViewController:animated:completion:));Method b=class_getInstanceMethod(self,@selector(ip6_presentViewController:animated:completion:));method_exchangeImplementations(a,b);
}
- (void)ip6_presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if([controller isKindOfClass:[IPLegacyAlertController class]]){[(IPLegacyAlertController *)controller showFrom:self];if(completion)completion();}
    else [self ip6_presentViewController:controller animated:animated completion:completion];
}
- (void)setEdgesForExtendedLayout:(UIRectEdge)edges {}
- (void)setDefinesPresentationContext:(BOOL)value {}
@end
@implementation AVMetadataItem (IPLegacyIdentifier)
- (NSString *)identifier {return [self.key isKindOfClass:[NSString class]]?(NSString *)self.key:self.commonKey;}
@end

#endif

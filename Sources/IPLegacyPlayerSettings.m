#import "IPLegacyPlayerSettings.h"
#if defined(IP_IOS6)
#import "IPLegacyAppearance.h"
#import "IPCrossfadeSettings.h"
#import "IPStrings.h"
@implementation IPLegacyPlayerSettings
- (instancetype)init {return [super initWithStyle:UITableViewStyleGrouped];}
- (void)viewDidLoad {[super viewDidLoad];self.title=IPL(@"Player settings");self.tableView.rowHeight=48;}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationBar *bar=self.navigationController.navigationBar;bar.barStyle=UIBarStyleDefault;bar.tintColor=[UIColor colorWithWhite:.65 alpha:1];
    [bar setBackgroundImage:IPLegacySurface(NO) forBarMetrics:UIBarMetricsDefault];
    bar.titleTextAttributes=@{UITextAttributeTextColor:[UIColor darkGrayColor],UITextAttributeTextShadowColor:[UIColor whiteColor]};
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?2:1;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return section==0?IPL(@"Player background"):IPL(@"Audio");}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {return section==0?IPL(@"Your background choice is saved and applied when you return to the player."):nil;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(path.section==0){cell.textLabel.text=path.row?IPL(@"Black"):IPL(@"Silver");cell.accessoryType=IPLegacyPlayerIsDark()==(path.row==1)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
    else{cell.textLabel.text=IPL(@"Fundido cruzado");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if(path.section==0){[[NSUserDefaults standardUserDefaults]setObject:path.row?@"black":@"silver" forKey:@"IPPlayerBackground"];[[NSUserDefaults standardUserDefaults]synchronize];[table reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];}
    else [self.navigationController pushViewController:[IPCrossfadeSettings new] animated:YES];
}
@end
#endif

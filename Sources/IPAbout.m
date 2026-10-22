#import "IPStrings.h"
#import "IPAbout.h"

@implementation IPAbout
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IPL(@"Acerca de");
    self.tableView.rowHeight = 44;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 160)];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon-60@2x.png"]];
    icon.frame = CGRectMake((header.bounds.size.width - 80) / 2, 24, 80, 80);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    icon.layer.cornerRadius = 18;
    icon.clipsToBounds = YES;
    icon.isAccessibilityElement = NO;
    [header addSubview:icon];
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 116, header.bounds.size.width, 28)];
    name.text = @"iPlayer935";
    name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    name.textAlignment = NSTextAlignmentCenter;
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:name];
    self.tableView.tableHeaderView = header;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = IPL(@"Versión");
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 64; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
#if defined(IP_IOS6)
    UIButton *link=[UIButton buttonWithType:UIButtonTypeCustom];link.frame=CGRectMake(0,0,tableView.bounds.size.width,64);link.titleLabel.font=[UIFont systemFontOfSize:13];[link setTitle:IPL(@"Hecho por: neura-neura") forState:UIControlStateNormal];[link setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];[link addTarget:self action:@selector(openRepository) forControlEvents:UIControlEventTouchUpInside];return link;
#else
    UITextView *credit = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 64)];
    credit.backgroundColor = [UIColor clearColor];
    credit.editable = NO;
    credit.scrollEnabled = NO;
    credit.textContainerInset = UIEdgeInsetsMake(14, 12, 10, 12);
    NSString *text = IPL(@"Hecho por: neura-neura");
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [UIColor grayColor],
        NSParagraphStyleAttributeName: paragraph
    }];
    NSURL *repository = [NSURL URLWithString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"IPRepositoryURL"]];
    if (repository) [value addAttribute:NSLinkAttributeName value:repository range:[text rangeOfString:@"neura-neura"]];
    credit.linkTextAttributes = @{NSForegroundColorAttributeName:self.view.tintColor};
    credit.attributedText = value;
    return credit;
#endif
}
#if defined(IP_IOS6)
- (void)openRepository {NSURL *url=[NSURL URLWithString:[[NSBundle mainBundle]objectForInfoDictionaryKey:@"IPRepositoryURL"]];if(url)[[UIApplication sharedApplication]openURL:url];}
#endif
@end

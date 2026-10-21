#import "IPLanguageSettings.h"
#import "IPStrings.h"

@implementation IPLanguageSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = IPL(@"Idioma");
    self.tableView.rowHeight = 56;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 4; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return IPL(@"El cambio se aplica al instante y se guarda solo para esta app. Conserva la música, la cola y las cachés. Idioma del sistema usa inglés si el idioma principal no es español, inglés o chino.");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSArray *values = @[@"system", @"es", @"en", @"zh-Hans"];
    NSArray *names = @[IPL(@"Idioma del sistema"), @"Español", @"English", @"简体中文"];
    cell.textLabel.text = names[path.row];
    if (path.row == 0) {
        NSString *language = IPLanguageForIdentifier([NSLocale preferredLanguages].firstObject);
        cell.detailTextLabel.text = (@{@"es":@"Español", @"en":@"English", @"zh-Hans":@"简体中文"})[language];
    }
    BOOL selected = [IPLanguagePreference() isEqual:values[path.row]];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (selected) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    IPSetLanguagePreference((@[@"system", @"es", @"en", @"zh-Hans"])[path.row]);
}
@end

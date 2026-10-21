#import "IPStrings.h"
#import "IPCacheSettings.h"
#import "IPSmartCache.h"
#import "IPStore.h"
#import "IPPlayer.h"
@interface IPCacheSettings ()
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation IPCacheSettings
- (instancetype)init {return [super initWithStyle:UITableViewStyleGrouped];}
- (void)viewDidLoad {[super viewDidLoad];self.title=IPL(@"Caché automática");self.tableView.rowHeight=60;}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refresh];self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.timer invalidate];self.timer=nil;}
- (void)refresh {[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return 5;}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {return IPL(@"Prepara las tres siguientes canciones y después la actual. Las copias completas funcionan sin conexión y las antiguas se reemplazan al llenar el límite. Las descargas manuales se conservan aparte. Si falla la conexión durante una descarga, esa canción aún no estará disponible sin conexión. Al vaciar se conserva la canción en uso.");}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"cache"];if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cache"];cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone;cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.detailTextLabel.numberOfLines=2;
    IPSmartCache *cache=[IPStore shared].smartCache;NSDictionary *s=cache.status;
    if(path.row==0){cell.textLabel.text=IPL(@"Preparar siguientes canciones");cell.detailTextLabel.text=IPL(@"Se aplica al reproducir una cola.");UISwitch *toggle=[UISwitch new];toggle.on=cache.enabled;[toggle addTarget:self action:@selector(enabled:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}
    else if(path.row==1){cell.textLabel.text=IPL(@"Espacio máximo");cell.detailTextLabel.text=[NSString stringWithFormat:@"%.0f MB",cache.limitBytes/1048576.0];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
    else if(path.row==2){cell.textLabel.text=IPL(@"Disponibles sin conexión");cell.detailTextLabel.text=[NSString stringWithFormat:IPL(@"%@ canciones · %.1f MB"),s[@"count"], [s[@"bytes"]doubleValue]/1048576];}
    else if(path.row==3){cell.textLabel.text=[s[@"running"]boolValue]?IPL(@"Preparando canción"):cache.enabled?IPL(@"En espera"):IPL(@"Desactivada");cell.detailTextLabel.text=[s[@"running"]boolValue]?[NSString stringWithFormat:@"%@ · %.0f %%",s[@"title"],[s[@"total"]doubleValue]>0?100*[s[@"received"]doubleValue]/[s[@"total"]doubleValue]:0]:[s[@"error"]length]?s[@"error"]:IPL(@"Las copias guardadas se conservan al cerrar.");}
    else{cell.textLabel.text=IPL(@"Vaciar caché automática");cell.detailTextLabel.text=IPL(@"Conserva las descargas manuales.");cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
    return cell;
}
- (void)enabled:(UISwitch *)toggle {[IPStore shared].smartCache.enabled=toggle.on;if(toggle.on&&[IPPlayer shared].playing)[[IPStore shared]preparePlaybackCacheForQueue:[IPPlayer shared].queue index:[IPPlayer shared].index];[self refresh];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];IPSmartCache *cache=[IPStore shared].smartCache;
    if(path.row==1){UIAlertController *menu=[UIAlertController alertControllerWithTitle:IPL(@"Espacio de caché automática") message:nil preferredStyle:UIAlertControllerStyleActionSheet];for(NSNumber *size in @[@128,@256,@512]){[menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ MB",size] style:0 handler:^(UIAlertAction *action){cache.limitBytes=size.unsignedLongLongValue*1048576;[self refresh];}]];}[menu addAction:[UIAlertAction actionWithTitle:IPL(@"Cancelar") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:menu animated:YES completion:nil];}
    else if(path.row==4){[cache clear];[self refresh];}
}
@end

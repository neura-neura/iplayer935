#import "IPStrings.h"
#import "IPLibraryPreparation.h"
#import "IPStore.h"
@implementation IPLibraryPreparation
- (instancetype)init {return [super initWithStyle:UITableViewStyleGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=IPL(@"Preparación local");
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(refresh) name:@"IPLibraryPreparationChanged" object:nil];
    UILabel *note=[[UILabel alloc]initWithFrame:CGRectMake(16,0,self.view.bounds.size.width-32,140)];note.font=[UIFont systemFontOfSize:13];note.numberOfLines=0;note.text=IPL(@"Puedes buscar y escuchar música mientras se prepara la biblioteca optimizada. Tus etiquetas y audio ya guardados se conservan. Al finalizar, las siguientes aperturas usan la base preparada. Si pausas o cierras durante la conversión, la biblioteca sigue disponible y puedes reintentar después.");
    CGFloat noteHeight=ceil([note sizeThatFits:CGSizeMake(note.bounds.size.width,CGFLOAT_MAX)].height);
    CGRect noteFrame=note.frame;noteFrame.size.height=noteHeight;note.frame=noteFrame;
    UIView *footer=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,noteHeight+10)];[footer addSubview:note];self.tableView.tableFooterView=footer;
}
- (void)dealloc {[[NSNotificationCenter defaultCenter]removeObserver:self];}
- (void)refresh {[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return 4;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *s=[IPStore shared].preparationStatus;BOOL ready=[IPStore shared].database!=nil;
    cell.detailTextLabel.numberOfLines=2;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(path.row==0){cell.textLabel.text=IPL(@"Estado");cell.detailTextLabel.text=ready?IPL(@"Biblioteca optimizada"):s[@"phase"]?:IPL(@"Biblioteca disponible");}
    else if(path.row==1){cell.textLabel.text=IPL(@"Canciones preparadas");cell.detailTextLabel.text=[NSString stringWithFormat:IPL(@"%@ de %@"),s[@"completed"]?:@0,s[@"total"]?:@([IPStore shared].tracks.count)];}
    else if(path.row==2){cell.textLabel.text=IPL(@"Detalle");cell.detailTextLabel.text=[s[@"error"]length]?s[@"error"]:ready?IPL(@"Las listas usan índices persistentes."):IPL(@"Puedes navegar y reproducir durante este proceso.");}
    else{cell.textLabel.text=ready?IPL(@"Preparación terminada"):[s[@"running"]boolValue]?IPL(@"Pausar preparación"):IPL(@"Continuar o reintentar");if(!ready){cell.textLabel.textColor=self.view.tintColor;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}}
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {if(path.row==3&&![IPStore shared].database){if([[IPStore shared].preparationStatus[@"running"]boolValue])[[IPStore shared]pausePreparation];else [[IPStore shared]resumePreparation];}[table deselectRowAtIndexPath:path animated:YES];}
@end

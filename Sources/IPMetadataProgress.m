#import "IPStrings.h"
#import "IPMetadataProgress.h"
#import "IPStore.h"
@interface IPMetadataProgress ()
@property(nonatomic,strong) NSDictionary *status;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation IPMetadataProgress
- (instancetype)init {return [super initWithStyle:UITableViewStyleGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=IPL(@"Caché de etiquetas");
    self.tableView.rowHeight=56;
    UILabel *note=[[UILabel alloc]initWithFrame:CGRectMake(18,0,self.view.bounds.size.width-36,145)];note.numberOfLines=0;note.font=[UIFont systemFontOfSize:13];note.textColor=[UIColor grayColor];
    note.text=IPL(@"Las etiquetas guardadas se conservan al cerrar la app. Solo se leen canciones nuevas, modificadas o pendientes. Los archivos sin etiquetas también quedan registrados y no se repiten. Puedes pausar y continuar después. La caché de etiquetas no descarga canciones completas.");
    CGFloat noteHeight=ceil([note sizeThatFits:CGSizeMake(note.bounds.size.width,CGFLOAT_MAX)].height);
    CGRect noteFrame=note.frame;noteFrame.size.height=noteHeight;note.frame=noteFrame;
    UIView *footer=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,noteHeight+10)];[footer addSubview:note];self.tableView.tableFooterView=footer;
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refresh];self.timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.timer invalidate];self.timer=nil;}
- (void)refresh {self.status=[[IPStore shared]metadataCacheStatusForProfile:self.profile];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==0?6:section==1?2:1;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return section==0?self.profile[@"name"]:section==1?IPL(@"Actividad"):IPL(@"Control");}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"status"];
    if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"status"];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.textLabel.textColor=[UIColor blackColor];cell.detailTextLabel.textColor=[UIColor grayColor];cell.detailTextLabel.numberOfLines=2;
    NSDictionary *s=self.status;
    if(path.section==0){
        NSArray *labels=@[IPL(@"Progreso guardado"),IPL(@"Canciones revisadas"),IPL(@"Con etiquetas"),IPL(@"Sin etiquetas en el archivo"),IPL(@"Pendientes"),IPL(@"Lecturas fallidas")];
        NSUInteger total=[s[@"total"]unsignedIntegerValue],cached=[s[@"cached"]unsignedIntegerValue],empty=[s[@"empty"]unsignedIntegerValue];
        NSArray *values=@[[NSString stringWithFormat:@"%.1f %%",total?100.0*cached/total:100], [NSString stringWithFormat:IPL(@"%lu de %lu"),(unsigned long)cached,(unsigned long)total],[@(cached-empty)stringValue],[s[@"empty"]description],[s[@"pending"]description],[s[@"failed"]description]];
        cell.textLabel.text=labels[path.row];cell.detailTextLabel.text=values[path.row];
    }else if(path.section==1){
        if(path.row==0){cell.textLabel.text=[s[@"paused"]boolValue]?IPL(@"Pausado"):[s[@"running"]boolValue]?IPL(@"Leyendo etiquetas"):[s[@"pending"]unsignedIntegerValue]?IPL(@"En espera"):IPL(@"Caché completa");cell.detailTextLabel.text=[s[@"current"]length]?s[@"current"]:IPL(@"No se vuelve a leer lo ya guardado.");}
        else {cell.textLabel.text=IPL(@"Último error");cell.detailTextLabel.text=[s[@"error"]length]?s[@"error"]:IPL(@"Sin errores de lectura en esta sesión.");}
    }else {cell.textLabel.text=[s[@"paused"]boolValue]?IPL(@"Continuar cacheado"):IPL(@"Pausar cacheado");cell.detailTextLabel.text=IPL(@"El avance guardado se conserva.");cell.textLabel.textColor=self.view.tintColor;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {if(path.section!=2)return;[[IPStore shared]setMetadataPaused:![self.status[@"paused"]boolValue] forProfile:self.profile];[self refresh];[tableView deselectRowAtIndexPath:path animated:YES];}
@end

#import "IPStrings.h"
#import "IPCrossfadeSettings.h"
#import "IPCrossfade.h"
#import "IPPlayer.h"
#import "IPLegacyAppearance.h"
@interface IPFadeGraph : UIView
@property(nonatomic) IPFadeCurve curve;
@end
@implementation IPFadeGraph
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext();CGRect plot=CGRectInset(self.bounds,14,16);
    CGContextSetStrokeColorWithColor(c,[UIColor colorWithWhite:.85 alpha:1].CGColor);CGContextSetLineWidth(c,.5);
    for(int i=0;i<=4;i++){CGFloat y=plot.origin.y+plot.size.height*i/4;CGContextMoveToPoint(c,plot.origin.x,y);CGContextAddLineToPoint(c,CGRectGetMaxX(plot),y);}CGContextStrokePath(c);
    NSArray *colors=@[
#if defined(IP_IOS6)
IPLegacyAccent(),
#else
[UIColor colorWithRed:1 green:.18 blue:.33 alpha:1],
#endif
[UIColor colorWithRed:0 green:.6 blue:.6 alpha:1]];
    for(int channel=0;channel<2;channel++){CGContextSetStrokeColorWithColor(c,[colors[channel]CGColor]);CGContextSetLineWidth(c,2);
        for(int i=0;i<=48;i++){float out,in;IPFadeGains(i/48.,self.curve,&out,&in);CGFloat x=plot.origin.x+plot.size.width*i/48,y=CGRectGetMaxY(plot)-plot.size.height*(channel?in:out);if(i==0)CGContextMoveToPoint(c,x,y);else CGContextAddLineToPoint(c,x,y);}CGContextStrokePath(c);
    }
}
@end
@interface IPCrossfadeSettings ()
@property(nonatomic,strong) IPFadeGraph *graph;
@end
@implementation IPCrossfadeSettings
- (instancetype)init {return [super initWithStyle:UITableViewStyleGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=IPL(@"Fundido cruzado");self.tableView.rowHeight=65;
    self.graph=[[IPFadeGraph alloc]initWithFrame:CGRectMake(16,0,self.view.bounds.size.width-32,120)];self.graph.backgroundColor=[UIColor clearColor];self.graph.curve=[IPPlayer shared].crossfade.curve;
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,120)];[header addSubview:self.graph];self.tableView.tableHeaderView=header;
    self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:IPL(@"Atrás") style:0 target:nil action:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(refresh) name:@"IPCrossfadeChanged" object:nil];
}
- (void)dealloc {[[NSNotificationCenter defaultCenter]removeObserver:self];}
- (void)refresh {self.graph.curve=[IPPlayer shared].crossfade.curve;[self.graph setNeedsDisplay];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 4;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?1:2;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return @[IPL(@"Activación"),IPL(@"Mezcla"),IPL(@"Cuándo aplicarlo"),IPL(@"Control de sesión")][section];}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
#if defined(IP_IOS6)
    if(section==1)return IPL(@"Orange: outgoing track. Green: incoming track. Equal power keeps the mix energy constant; linear reduces both volumes evenly.");
#endif
    if(section==1)return IPL(@"Rosa: canción saliente. Verde: entrante. Potencia constante conserva la energía de la mezcla; lineal reduce ambos volúmenes de forma uniforme.");
    if(section==3)return IPL(@"Mantén pulsadas las flechas de aleatorio en Reproduciendo para suspender o reanudar el efecto durante esta sesión. Un toque sigue cambiando el modo aleatorio. Solo se abren dos canciones durante la transición; la duración efectiva puede ser menor con canciones cortas o si la conexión tarda.");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.detailTextLabel.numberOfLines=2;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    IPCrossfade *s=[IPPlayer shared].crossfade;NSInteger key=path.section*10+path.row;
    if(key==10){cell.textLabel.text=IPL(@"Curva del fundido");cell.detailTextLabel.text=s.curve==IPFadeCurveEqualPower?IPL(@"Potencia constante"):IPL(@"Lineal");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
    else if(key==11){cell.textLabel.text=IPL(@"Duración");cell.detailTextLabel.text=[NSString stringWithFormat:IPL(@"%.0f segundos"),s.duration];UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(0,0,140,36)];slider.minimumValue=1;slider.maximumValue=10;slider.value=s.duration;slider.accessibilityLabel=IPL(@"Duración del fundido en segundos");[slider addTarget:self action:@selector(previewDuration:) forControlEvents:UIControlEventValueChanged];[slider addTarget:self action:@selector(saveDuration:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];cell.accessoryView=slider;}
    else if(key==31){cell.textLabel.text=s.sessionSuspended?IPL(@"Suspendido en esta sesión"):IPL(@"Disponible en esta sesión");cell.detailTextLabel.text=IPL(@"Toca para suspender o reanudar el fundido.");cell.selectionStyle=UITableViewCellSelectionStyleDefault;cell.textLabel.enabled=s.enabled&&s.sessionControl;}
    else{UISwitch *toggle=[UISwitch new];toggle.tag=key;
        if(key==0){cell.textLabel.text=IPL(@"Activar fundido cruzado");toggle.on=s.enabled;}
        if(key==20){cell.textLabel.text=IPL(@"Al cambiar manualmente");cell.detailTextLabel.text=IPL(@"Siguiente, anterior o una canción elegida.");toggle.on=s.manualSkip;}
        if(key==21){cell.textLabel.text=IPL(@"Al terminar la canción");cell.detailTextLabel.text=IPL(@"Mezcla con la siguiente antes de llegar al final.");toggle.on=s.automaticAdvance;}
        if(key==30){cell.textLabel.text=IPL(@"Pulsación larga en aleatorio");toggle.on=s.sessionControl;}
        toggle.enabled=key==0||s.enabled;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }return cell;
}
- (void)previewDuration:(UISlider *)slider {UITableViewCell *cell=(id)slider.superview;while(cell&&![cell isKindOfClass:[UITableViewCell class]])cell=(id)cell.superview;cell.detailTextLabel.text=[NSString stringWithFormat:IPL(@"%.0f segundos"),round(slider.value)];}
- (void)saveDuration:(UISlider *)slider {[IPPlayer shared].crossfade.duration=round(slider.value);[[IPPlayer shared]crossfadeSettingsChanged];}
- (void)toggle:(UISwitch *)toggle {IPCrossfade *s=[IPPlayer shared].crossfade;switch(toggle.tag){case 0:s.enabled=toggle.on;s.sessionSuspended=NO;break;case 20:s.manualSkip=toggle.on;break;case 21:s.automaticAdvance=toggle.on;break;case 30:s.sessionControl=toggle.on;break;}[[IPPlayer shared]crossfadeSettingsChanged];}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if(path.section==3&&path.row==1){[[IPPlayer shared]toggleCrossfadeSession];return;}
    if(path.section!=1||path.row!=0)return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:IPL(@"Curva del fundido") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *labels=@[IPL(@"Lineal"),IPL(@"Potencia constante")];
    for(NSInteger i=0;i<labels.count;i++)[a addAction:[UIAlertAction actionWithTitle:labels[i] style:0 handler:^(UIAlertAction *action){[IPPlayer shared].crossfade.curve=i;[[IPPlayer shared]crossfadeSettingsChanged];}]];
    [a addAction:[UIAlertAction actionWithTitle:IPL(@"Cancelar") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
@end

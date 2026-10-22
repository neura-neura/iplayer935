#import "IPStrings.h"
#import "IPLocalLibrary.h"
#import "IPLanguageSettings.h"
#import "IPAbout.h"
#import "IPDiagnostics.h"
#import "IPCodecCheck.h"
#import "IPNow.h"
#import "IPControlIcons.h"
#import "IPMiniRoot.h"
#import "IPLibraryDB.h"
#import "IPLibraryPreparation.h"
#import "IPMetadataProgress.h"
#import "IPCacheSettings.h"
#import "IPPlayer.h"
#import "IPSMB.h"
#import "IPStore.h"
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
static IPStore *S(void) { return [IPStore sharedStore]; }
static void Message(UIViewController *v, NSString *s) {
    if (!s.length)
        return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"iPlayer935"
                                                               message:s
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:IPL(@"Aceptar")
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [v presentViewController:a animated:YES completion:nil];
}
@interface IPList : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) UIBarButtonItem *optionsItem, *selectionItem;
@property(nonatomic,strong) NSMutableOrderedSet *selectedTrackIDs;
@property(nonatomic, copy) NSString *mode;
@property(nonatomic, strong) NSMutableDictionary *profile;
@property(nonatomic, strong) NSMutableDictionary *playlist;
@property(nonatomic, strong) NSArray *rows;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, copy) NSString *sortKey;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) BOOL visible, needsReload;
@property(nonatomic) NSUInteger queryGeneration, pendingMetadata, totalRows;
@property(nonatomic) BOOL loadingPage;
@property(nonatomic) BOOL metadataReloadScheduled, preservePosition;
@property(nonatomic,strong) NSTimer *refreshTimer;
@end
@interface IPProfileEditor : UITableViewController
@property(nonatomic, strong) NSMutableDictionary *profile;
@property(nonatomic, strong) NSArray *fields;
@property(nonatomic, strong) NSArray *fieldLabels, *fieldHints;
@end
@implementation IPProfileEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.profile ? IPL(@"Editar servidor") : IPL(@"Agregar servidor");
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.tableFooterView = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 290, 70)];
    UILabel *note = (UILabel *)self.tableView.tableFooterView;
    note.numberOfLines = 0;
    note.font = [UIFont systemFontOfSize:12];
    note.text = IPL(@"La contraseña se guarda en Keychain. Cambiar host, recurso o subcarpeta crea una "
                @"biblioteca distinta; las copias anteriores se conservan.");
    if ([self.profile[@"isExample"]boolValue]) note.text=[IPL(@"This is a fictional example. Edit the profile with your own server details before connecting.") stringByAppendingFormat:@"\n\n%@",note.text];
    note.frame=CGRectMake(0,0,self.view.bounds.size.width,ceil([note sizeThatFits:CGSizeMake(self.view.bounds.size.width-32,CGFLOAT_MAX)].height)+24);
    NSArray *labels = @[
        IPL(@"Nombre"), IPL(@"Host o IP (sin smb://)"), IPL(@"Recurso compartido"), IPL(@"Subcarpeta"), IPL(@"Usuario SMB"),
        IPL(@"Contraseña (vacía: conservar)")
    ];
    NSArray *keys = @[ @"name", @"host", @"share", @"root", @"username", @"password" ];
    self.fieldLabels = labels;
    self.fieldHints = @[
        IPL(@"Choose a display name, e.g. My Music Server."),
        IPL(@"Enter your server's IP or hostname, e.g. 192.168.1.10 or music-server.local. No smb:// or folder path."),
        IPL(@"Enter the SMB share name, e.g. Music. For smb://server/Music, enter Music, not the server's disk path."),
        IPL(@"Folder inside the share, e.g. Albums/Rock. Leave empty to use the entire share."),
        IPL(@"Enter your SMB account username. Leave empty only if the share allows guest access."),
        IPL(@"Enter that SMB account's password. Leave empty to keep the saved password, if any.")
    ];
    NSMutableArray *a = [NSMutableArray new];
    for (int i = 0; i < 6; i++) {
        UITextField *f = [UITextField new];
        f.placeholder = labels[i];
        f.text = i < 5 ? self.profile[keys[i]] : @"";
        if (i == 3)
            f.font = [UIFont systemFontOfSize:12];
        f.secureTextEntry = i == 5;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        [a addObject:f];
    }
    self.fields = a;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self
                                                      action:@selector(save)];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return 6;
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)p {
    CGRect hint = [self.fieldHints[p.row] boundingRectWithSize:CGSizeMake(t.bounds.size.width-30, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin
            attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12]} context:nil];
    return 68 + ceil(hint.size.height) + 12;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:0 reuseIdentifier:nil];
    UITextField *f = self.fields[p.row];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, t.bounds.size.width-30, 18)];
    label.text = self.fieldLabels[p.row];
    label.font = [UIFont boldSystemFontOfSize:12];
    [c.contentView addSubview:label];
    f.frame = CGRectMake(15, 26, t.bounds.size.width-30, 36);
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(15, 68, t.bounds.size.width-30,
        [self tableView:t heightForRowAtIndexPath:p]-80)];
    hint.text = self.fieldHints[p.row];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = [UIColor darkGrayColor];
    hint.numberOfLines = 0;
    [c.contentView addSubview:hint];
    [c.contentView addSubview:f];
    return c;
}
- (NSString *)value:(NSUInteger)i {
    return [(UITextField *)self.fields[i] text] ?: @"";
}
- (void)save {
    if (![self value:0].length || ![self value:1].length || ![self value:2].length) {
        Message(self, IPL(@"Completa nombre, host y recurso compartido."));
        return;
    }
    NSString *host = [self value:1];
    NSString *root = [[self value:3] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if ([host containsString:@"/"] || [root.pathComponents containsObject:@".."]) {
        Message(self, IPL(@"Usa solo el host y una subcarpeta sin «..»."));
        return;
    }
    NSError *e = nil;
    BOOL fresh = !self.profile;
    NSMutableDictionary *p =
        self.profile
            ?: [@{@"id" : [NSUUID UUID].UUIDString, @"endpointIdentity" : [NSUUID UUID].UUIDString}
                   mutableCopy];
    NSDictionary *endpoint = @{
        @"host" : host,
        @"share" : [self value:2],
        @"root" :
            [root stringByTrimmingCharactersInSet:[NSCharacterSet
                                                      characterSetWithCharactersInString:@"/"]],
        @"username" : [self value:4]
    };
    if (fresh) {
        [p addEntriesFromDictionary:endpoint];
        [S().profiles addObject:p];
    } else if (![S() setEndpoint:endpoint forProfileID:p[@"id"] error:&e]) {
        Message(self, e.localizedDescription);
        return;
    }
    p[@"name"] = [self value:0];
    if ([self value:5].length && ![S() setPassword:[self value:5] forProfileID:p[@"id"] error:&e]) {
        Message(self, e.localizedDescription);
        return;
    }
    [S() save];
#if defined(IP_IOS6)
    // The legacy navigation transition does not rebuild a previously loaded server list.
    // Mark it dirty before popping, so its next viewWillAppear reads the saved profiles.
    [[NSNotificationCenter defaultCenter]postNotificationName:@"IPStoreChanged" object:S()];
#endif
    [self.navigationController popViewControllerAnimated:YES];
}
@end
@implementation IPList
- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *preference=[@"sort-" stringByAppendingString:self.playlist[@"id"]?:self.profile[@"id"]?:self.mode?:@"library"];
    self.sortKey=[[NSUserDefaults standardUserDefaults]stringForKey:preference] ?: (self.playlist?@"playlist":@"title");
    self.selectedTrackIDs=[NSMutableOrderedSet new];
    self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:IPL(@"Atrás") style:UIBarButtonItemStylePlain target:nil action:nil];
    self.optionsItem=[[UIBarButtonItem alloc]initWithImage:IPControlImage(IPControlIconOptions) style:UIBarButtonItemStylePlain target:self action:@selector(options)];
    self.optionsItem.accessibilityLabel=IPL(@"Opciones");
    [self updateSelectionControls];
    if (![self.mode isEqual:@"servers"] && ![self.mode isEqual:@"playlists"]) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.searchResultsUpdater = self;
        self.search.dimsBackgroundDuringPresentation = NO;
        self.search.searchBar.placeholder = IPL(@"Título, artista, álbum, género");
        self.tableView.tableHeaderView = self.search.searchBar;
        self.definesPresentationContext = YES;
    }
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(localMediaChanged) name:@"IPLocalLibraryChanged" object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(preparationChanged) name:@"IPLibraryPreparationChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:@"IPStoreChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(favoriteChanged:)
                                                 name:@"IPFavoriteChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trackMetadataChanged:) name:@"IPTrackMetadataChanged" object:nil];
}
- (void)preparationChanged {if(self.visible&&[self.mode isEqual:@"servers"])[self.tableView reloadData];}
- (void)trackMetadataChanged:(NSNotification *)notification {
    self.needsReload = YES;
    if (self.visible) {
        [self.tableView reloadRowsAtIndexPaths:self.tableView.indexPathsForVisibleRows ?: @[] withRowAnimation:UITableViewRowAnimationNone];
        if(!self.metadataReloadScheduled){self.metadataReloadScheduled=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{self.metadataReloadScheduled=NO;self.preservePosition=YES;[self reload];});}
    }
}
- (void)favoriteChanged:(NSNotification *)notification {
    if ([self.mode isEqual:@"favorites"]) {
        [self reload];
    } else if (self.visible) {
        [self.tableView reloadRowsAtIndexPaths:self.tableView.indexPathsForVisibleRows ?: @[]
                             withRowAnimation:UITableViewRowAnimationNone];
    }
}
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    self.visible = YES;
    if (self.needsReload || !self.rows) [self reload];
    if(self.profile){[S() refreshProfileIfNeeded:self.profile];[self prioritizeMetadata];}
    if(self.profile&&!self.refreshTimer)self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(checkLibraryChanges) userInfo:nil repeats:YES];
}
- (void)localMediaChanged {if(IPIsLocalProfile(self.profile))[self checkLibraryChanges];}
- (void)checkLibraryChanges {if(self.profile&&self.visible)[S() refreshProfileIfNeeded:self.profile];}
- (void)prioritizeMetadata {
    NSMutableArray *tracks=[NSMutableArray new];
    for(NSIndexPath *path in self.tableView.indexPathsForVisibleRows)if((NSUInteger)path.row<self.rows.count)[tracks addObject:self.rows[path.row]];
    NSMutableDictionary *profile=self.profile;
    if(!profile&&tracks.count)profile=[S() profileForTrack:tracks.firstObject];
    if(profile)[S() ensureMetadataForProfile:profile priorityTracks:tracks];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {[self prioritizeMetadata];}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {if(!decelerate)[self prioritizeMetadata];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.visible = NO;
    [self.refreshTimer invalidate];self.refreshTimer=nil;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)s {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.25];
}
- (void)reload {
    if (!self.visible) { self.needsReload = YES; return; }
    self.needsReload = NO;
    BOOL ready=S().libraryLoaded;
    for(UIBarButtonItem *item in self.navigationItem.rightBarButtonItems)item.enabled=ready;
    if(!ready){
        self.rows=[self.mode isEqual:@"servers"]?[@[S().localProfile] arrayByAddingObjectsFromArray:S().profiles]:@[];
        self.status=IPL(@"Cargando biblioteca guardada…");[self.tableView reloadData];return;
    }
    if([self.status isEqual:IPL(@"Cargando biblioteca guardada…")])self.status=nil;
    NSMutableArray *a = [NSMutableArray new];
    if ([self.mode isEqual:@"servers"]) {
        [a addObject:S().localProfile];
        [a addObjectsFromArray:S().profiles];
        self.title = IPL(@"Servidores");
    } else if ([self.mode isEqual:@"playlists"]) {
        [a addObjectsFromArray:S().playlists];
        self.title = IPL(@"Playlists");
    } else {
        if(self.tableView.dragging||self.tableView.decelerating){self.needsReload=YES;[self performSelector:@selector(reload) withObject:nil afterDelay:.5];return;}
        ++self.queryGeneration;self.loadingPage=NO;
        self.title=IPProfileName(self.profile)?:self.playlist[@"name"]?:([self.mode isEqual:@"favorites"]?IPL(@"Favoritos"):IPL(@"Descargas"));
        NSUInteger limit=self.preservePosition?MAX((NSUInteger)200,self.rows.count):200;
        self.preservePosition=NO;
        [self fetchPage:0 limit:limit];
        return;
    }
    self.rows = a;
    [self.tableView reloadData];
}
- (void)fetchPage:(NSUInteger)offset limit:(NSUInteger)limit {
    if(self.loadingPage)return;
    self.loadingPage=YES;NSUInteger token=self.queryGeneration;
    [S() queryProfile:self.profile mode:self.mode playlistIDs:self.playlist[@"trackIDs"] sort:self.sortKey query:self.search.searchBar.text offset:offset limit:limit completion:^(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records){
        if(token!=self.queryGeneration)return;
        self.loadingPage=NO;self.totalRows=total;self.pendingMetadata=pending;
        NSArray *page=[S() materializeTrackRecords:records];
        self.rows=offset?[self.rows arrayByAddingObjectsFromArray:page]:page;
        if([self.status hasPrefix:IPL(@"Cargando biblioteca")])self.status=nil;
        [self.tableView reloadData];[self restoreSelection];[self prioritizeMetadata];
    }];
}
- (BOOL)hasMoreRows {return self.search&&self.rows.count<self.totalRows;}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    if([self hasMoreRows]&&path.row+30>=self.rows.count)[self fetchPage:self.rows.count limit:200];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return self.rows.count+([self hasMoreRows]?1:0);
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (self.status.length)
        return self.status;
    if([self.mode isEqual:@"servers"]&&[S().preparationStatus[@"running"]boolValue])return [NSString stringWithFormat:IPL(@"%@ · %@/%@ · Puedes usar la biblioteca"),S().preparationStatus[@"phase"],S().preparationStatus[@"completed"],S().preparationStatus[@"total"]];
    if (self.profile)
        return [NSString
            stringWithFormat:IPL(@"%@ · %lu canciones"), IPProfileName(self.profile),
                             (unsigned long)self.totalRows];
    if ([self.mode isEqual:@"servers"]) {
        NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:@"lastProfile"];
        for (NSDictionary *p in [@[S().localProfile]arrayByAddingObjectsFromArray:S().profiles])
            if ([p[@"id"] isEqual:last])
                return [IPL(@"Último usado: ") stringByAppendingString:IPProfileName(p)];
    }
    if ([self.mode isEqual:@"downloads"])
        return
            [NSString stringWithFormat:IPL(@"%.0f / %.0f MB · límite configurable"),
                                       S().cacheBytes / 1048576.0, S().cacheLimitBytes / 1048576.0];
    return self.rows.count ? IPL(@"Toca para abrir · ⓘ para acciones")
                           : IPL(@"Sin elementos. Usa + u Opciones para comenzar.");
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"row"];
    if (!c)
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                   reuseIdentifier:@"row"];
    if((NSUInteger)p.row>=self.rows.count){c.textLabel.text=IPL(@"Cargando más canciones…");c.detailTextLabel.text=nil;c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
    c.selectionStyle=UITableViewCellSelectionStyleDefault;
    NSDictionary *r = self.rows[p.row];
    BOOL server = [self.mode isEqual:@"servers"], list = [self.mode isEqual:@"playlists"];
    c.textLabel.text =
        server ? [NSString
                     stringWithFormat:@"%@%@", [r[@"default"] boolValue] ? @"★ " : @"", IPProfileName(r)]
        : list ? r[@"name"]
               : [NSString stringWithFormat:@"%@%@ %@", [r[@"favorite"] boolValue] ? @"★ " : @"",
                                            [r[@"downloaded"] boolValue] ? @"↓" : @"",
                                            r[@"title"] ?: IPL(@"Sin título")];
    c.detailTextLabel.text=server&&IPIsLocalProfile(r)?IPL(@"iTunes and local files"):server?[NSString stringWithFormat:@"%@/%@ · %@",r[@"host"],r[@"share"],r[@"username"]?:@""]:list?[NSString stringWithFormat:IPL(@"%lu canciones%@%@"),(unsigned long)[r[@"trackIDs"] count],r[@"sourceName"]?@" · ":@"",r[@"sourceName"]?:@""]:[NSString stringWithFormat:@"%@ · %@ · %@%@",r[@"artist"]?:@"",r[@"album"]?:@"",IPProfileName([S() profileForTrack:r])?:r[@"sourceName"]?:IPL(@"Origen no disponible"),r[@"unsupportedReason"]?IPL(@" · ⚠ formato"):([r[@"unavailableRemote"] boolValue]?IPL(@" · sin acceso remoto"):@"")];
    c.accessoryType = server&&IPIsLocalProfile(r)?UITableViewCellAccessoryNone:UITableViewCellAccessoryDetailButton;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    if((NSUInteger)p.row>=self.rows.count)return;
    if(t.editing){if(t.allowsMultipleSelectionDuringEditing){[self.selectedTrackIDs addObject:self.rows[p.row][@"id"]];[self updateSelectionControls];}return;}
    NSMutableDictionary *r = self.rows[p.row];
    if ([self.mode isEqual:@"servers"]) {
        if ([r[@"isExample"]boolValue]) {
            IPProfileEditor *editor=[IPProfileEditor new];editor.profile=r;
            [self.navigationController pushViewController:editor animated:YES];return;
        }
        [[NSUserDefaults standardUserDefaults] setObject:r[@"id"] forKey:@"lastProfile"];
        IPList *v = [IPList new];
        v.mode = @"library";
        v.profile = r;
        [self.navigationController pushViewController:v animated:YES];
    } else if ([self.mode isEqual:@"playlists"]) {
        IPList *v = [IPList new];
        v.mode = @"songs";
        v.playlist = r;
        [self.navigationController pushViewController:v animated:YES];
    } else {
        if (r[@"unsupportedReason"]) {
            Message(self, IPL(r[@"unsupportedReason"]));
            return;
        }
        NSUInteger token=self.queryGeneration;NSString *selectedID=r[@"id"];
        [S() queryProfile:self.profile mode:self.mode playlistIDs:self.playlist[@"trackIDs"] sort:self.sortKey query:self.search.searchBar.text offset:0 limit:0 completion:^(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records){
            if(token!=self.queryGeneration)return;
            NSUInteger selected=(NSUInteger)p.row;
            if(selected>=ids.count||![ids[selected]isEqual:selectedID])selected=[ids indexOfObject:selectedID];
            if(selected!=NSNotFound)[[IPPlayer shared]playTracks:[S() queueForTrackIDs:ids] index:selected];
        }];
        [t deselectRowAtIndexPath:p animated:YES];
    }
}
- (void)action:(UIAlertController *)a title:(NSString *)title block:(void (^)(void))b {
    [a addAction:[UIAlertAction actionWithTitle:title
                                          style:0
                                        handler:^(UIAlertAction *x) {
                                            b();
                                        }]];
}
- (void)presentMenu:(UIAlertController *)a {
    [a addAction:[UIAlertAction actionWithTitle:IPL(@"Cancelar")
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)p {
    if(!S().libraryLoaded||(NSUInteger)p.row>=self.rows.count)return;
    NSMutableDictionary *r = self.rows[p.row];
    if([self.mode isEqual:@"servers"]&&IPIsLocalProfile(r))return;
    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:r[@"name"] ?: r[@"title"]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    if ([self.mode isEqual:@"servers"]) {
        [self action:a
               title:IPL(@"Editar perfil")
               block:^{
                   IPProfileEditor *v = [IPProfileEditor new];
                   v.profile = r;
                   [self.navigationController pushViewController:v animated:YES];
               }];
        [self action:a
               title:IPL(@"Probar conexión")
               block:^{
                   [self test:r];
               }];
        [self action:a
               title:IPL(@"Marcar predeterminado")
               block:^{
                   for (NSMutableDictionary *d in S().profiles)
                       d[@"default"] = @NO;
                   r[@"default"] = @YES;
                   [S() save];
                   [self reload];
               }];
        [self action:a
               title:IPL(@"Borrar contraseña guardada")
               block:^{
                   NSError *e = nil;
                   [S() deletePasswordForProfileID:r[@"id"] error:&e];
                   if (e)
                       Message(self, e.localizedDescription);
               }];
        [self action:a
               title:IPL(@"Eliminar perfil…")
               block:^{
                   [self confirm:IPL(@"Eliminar perfil, credencial y descargas de este origen. Se "
                                 @"quitarán sus referencias de playlists.")
                           block:^{
                               NSError *e = nil;
                               [S() deleteProfile:r error:&e];
                               if (e)
                                   Message(self, e.localizedDescription);
                               [self reload];
                           }];
               }];
    } else if ([self.mode isEqual:@"playlists"]) {
        [self action:a
               title:IPL(@"Renombrar")
               block:^{
                   [self namePlaylist:r];
               }];
        [self action:a
               title:IPL(@"Descargar playlist")
               block:^{
                   NSMutableArray *tracks = [NSMutableArray new];
                   NSSet *requested = [NSSet setWithArray:r[@"trackIDs"] ?: @[]];
                   for (NSDictionary *x in S().tracks)
                       if ([requested containsObject:x[@"id"]])
                           [tracks addObject:x];
                   [self download:tracks];
               }];
        [self action:a
               title:IPL(@"Eliminar playlist")
               block:^{
                   [S().playlists removeObject:r];
                   [S() save];
                   [self reload];
               }];
    } else {
        [self action:a
               title:[r[@"favorite"] boolValue] ? IPL(@"Quitar favorito") : IPL(@"Marcar favorito")
               block:^{
                   [S() setFavorite:![r[@"favorite"] boolValue] forTrack:r];
               }];
        if(![r[@"profileID"]isEqual:IPLocalProfileID])[self action:a
               title:IPL(@"Descargar canción")
               block:^{
                   [self download:@[ r ]];
               }];
        [self action:a
               title:IPL(@"Añadir a playlist")
               block:^{
                   [self choosePlaylist:r];
               }];
        if ([r[@"downloaded"] boolValue])
            [self action:a
                   title:IPL(@"Borrar descarga")
                   block:^{
                       NSError *e = nil;
                       [S() removeDownloadForTrack:r error:&e];
                       if (e)
                           Message(self, e.localizedDescription);
                       [self reload];
                   }];
        if (self.playlist) {
            [self action:a
                   title:IPL(@"Quitar de playlist")
                   block:^{
                       [self.playlist[@"trackIDs"] removeObject:r[@"id"]];
                       [S() save];
                       [self reload];
                   }];
        }
        NSString*info=[NSString stringWithFormat:IPL(@"%@\n%@\n%@ · pista %@ · %@ s\n%@\n%@"),r[@"title"],r[@"path"],r[@"genre"]?:@"",r[@"trackNumber"]?:@"",r[@"duration"]?:@"",[S() profileForTrack:r][@"name"]?:r[@"sourceName"]?:IPL(@"Sin perfil"),r[@"unsupportedReason"]?:@""];
        [self action:a
               title:IPL(@"Ver metadatos y origen")
               block:^{
                   Message(self, info);
               }];
    }
    [self presentMenu:a];
}
- (void)confirm:(NSString *)text block:(void (^)(void))block {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:IPL(@"Confirmar")
                                                               message:text
                                                        preferredStyle:1];
    [self action:a title:IPL(@"Continuar") block:block];
    [self presentMenu:a];
}
- (void)updateSelectionControls {
    BOOL songs=![self.mode isEqual:@"servers"]&&![self.mode isEqual:@"playlists"];
    if(songs&&self.tableView.editing){self.selectionItem=[[UIBarButtonItem alloc]initWithTitle:IPL(@"Hecho") style:UIBarButtonItemStyleDone target:self action:@selector(add)];}
    else if(songs){self.selectionItem=[[UIBarButtonItem alloc]initWithImage:IPControlImage(IPControlIconSelect) style:UIBarButtonItemStylePlain target:self action:@selector(add)];self.selectionItem.accessibilityLabel=IPL(@"Seleccionar canciones");}
    else self.selectionItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    self.navigationItem.rightBarButtonItems=@[self.optionsItem,self.selectionItem];
    BOOL selecting=self.tableView.editing&&self.tableView.allowsMultipleSelectionDuringEditing;
    self.navigationItem.title=selecting?[NSString stringWithFormat:IPL(@"%lu seleccionadas"),(unsigned long)self.selectedTrackIDs.count]:self.title;
    self.optionsItem.accessibilityLabel=selecting?IPL(@"Acciones de selección"):IPL(@"Opciones");
    for(UIBarButtonItem *item in self.navigationItem.rightBarButtonItems)item.enabled=S().libraryLoaded;
}
- (void)restoreSelection {
    if(self.tableView.editing&&self.tableView.allowsMultipleSelectionDuringEditing)for(NSUInteger i=0;i<self.rows.count;i++)if([self.selectedTrackIDs containsObject:self.rows[i][@"id"]])[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self updateSelectionControls];
}
- (void)tableView:(UITableView *)table didDeselectRowAtIndexPath:(NSIndexPath *)path {
    if(table.editing&&table.allowsMultipleSelectionDuringEditing&&(NSUInteger)path.row<self.rows.count){[self.selectedTrackIDs removeObject:self.rows[path.row][@"id"]];[self updateSelectionControls];}
}
- (NSIndexPath *)tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {return (NSUInteger)path.row<self.rows.count?path:nil;}
- (void)add {
    if(!S().libraryLoaded)return;
    if([self.mode isEqual:@"servers"])[self.navigationController pushViewController:[IPProfileEditor new] animated:YES];
    else if([self.mode isEqual:@"playlists"])[self namePlaylist:nil];
    else {
        BOOL editing=!self.tableView.editing;[self.selectedTrackIDs removeAllObjects];
        self.tableView.allowsMultipleSelectionDuringEditing=YES;
        [self.tableView setEditing:editing animated:YES];[self updateSelectionControls];
        if(!editing){[self.tableView reloadData];if(self.needsReload)[self reload];}
    }
}
- (void)selectionOptions {
    NSArray *ids=self.selectedTrackIDs.array;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:IPL(@"%lu canciones seleccionadas"),(unsigned long)ids.count] message:ids.count?nil:IPL(@"Marca canciones y toca este botón para elegir una acción.") preferredStyle:UIAlertControllerStyleActionSheet];
    if(ids.count){
        [self action:a title:IPL(@"Reproducir selección") block:^{NSArray *queue=[S() queueForTrackIDs:ids];[self add];[[IPPlayer shared]playTracks:queue index:0];}];
        [self action:a title:IPL(@"Agregar a playlist") block:^{[self choosePlaylistsForIDs:ids];}];
        [self action:a title:IPL(@"Marcar favoritas") block:^{[S() setFavorite:YES forTracks:[S() materializeTrackIDs:ids]];}];
        [self action:a title:IPL(@"Quitar de favoritos") block:^{[S() setFavorite:NO forTracks:[S() materializeTrackIDs:ids]];}];
        [self action:a title:IPL(@"Descargar selección") block:^{[self download:[S() materializeTrackIDs:ids]];}];
    }
    [self action:a title:[NSString stringWithFormat:IPL(@"Seleccionar las %lu canciones cargadas"),(unsigned long)self.rows.count] block:^{for(NSDictionary *track in self.rows)[self.selectedTrackIDs addObject:track[@"id"]];[self restoreSelection];}];
    if(ids.count)[self action:a title:IPL(@"Desmarcar todas") block:^{[self.selectedTrackIDs removeAllObjects];[self.tableView reloadData];[self updateSelectionControls];}];
    [self presentMenu:a];
}
- (void)namePlaylist:(NSMutableDictionary *)p {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:IPL(@"Nombre de playlist")
                                                               message:nil
                                                        preferredStyle:1];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = p[@"name"];
    }];
    [self action:a
           title:IPL(@"Guardar")
           block:^{
               NSString *n = a.textFields.firstObject.text;
               if (!n.length)
                   return;
               NSMutableDictionary *d =
                   p ?: [@{@"id" : [NSUUID UUID].UUIDString,
                           @"trackIDs" : [NSMutableArray new]} mutableCopy];
               d[@"name"] = n;
               if (!p)
                   [S().playlists addObject:d];
               [S() save];
               [self reload];
           }];
    [self presentMenu:a];
}
- (void)choosePlaylist:(NSDictionary *)track {[self choosePlaylistsForIDs:@[track[@"id"]]];}
- (void)choosePlaylistsForIDs:(NSArray *)ids {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:IPL(@"Agregar a playlist") message:S().playlists.count?nil:IPL(@"Crea una playlist en la pestaña Playlists.") preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSMutableDictionary *p in S().playlists)[self action:a title:p[@"name"] block:^{
        NSMutableArray *existing=p[@"trackIDs"];NSMutableSet *seen=[NSMutableSet setWithArray:existing];
        for(NSString *tid in ids)if(![seen containsObject:tid]){[existing addObject:tid];[seen addObject:tid];}
        [S() save];Message(self,IPL(@"Selección agregada a la playlist."));
    }];
    [self presentMenu:a];
}
- (void)download:(NSArray *)tracks {
    unsigned long long bytes = 0;
    for (NSDictionary *t in tracks)
        if (![S() localURL:t])
            bytes += [t[@"size"] unsignedLongLongValue];
    [self
        confirm:[NSString
                    stringWithFormat:
                        IPL(@"Descargar %lu canciones · hasta %.1f MB. Disponible en caché: %.1f MB."),
                        (unsigned long)tracks.count, bytes / 1048576.0,
                        (S().cacheLimitBytes > S().cacheBytes ? S().cacheLimitBytes - S().cacheBytes
                                                              : 0) /
                            1048576.0]
          block:^{
              [S() downloadTracks:tracks
                  progress:^(NSString *m) {
                      self.status = m;
                      [self.tableView reloadData];
                  }
                  completion:^(NSError *e) {
                      self.status = nil;
                      [self reload];
                      [IPDiagnostics write];
                      Message(self, e ? e.localizedDescription : IPL(@"Descarga completada."));
                  }];
          }];
}
- (void)test:(NSDictionary *)p {
    if ([p[@"isExample"]boolValue]) { Message(self,IPL(@"This is a fictional example. Edit the profile with your own server details before connecting.")); return; }
    self.status = IPL(@"Probando acceso SMB…");
    [self.tableView reloadData];
    NSDictionary *profile = [p copy];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSError *e = nil;
        IPSMB *s = [[IPSMB alloc] initWithProfile:profile
                                         password:[S() passwordForProfile:profile error:NULL]];
        BOOL ok = [s connect:&e];
        if (ok)
            ok = [s list:@"" error:&e] != nil;
        [s disconnect];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.status = nil;
            [self reload];
            Message(self, ok ? IPL(@"Conexión y lectura de carpeta correctas.")
                             : (e.localizedDescription
                                    ?: IPL(@"No se pudo acceder. Edita el perfil e introduce una "
                                       @"cuenta SMB autorizada.")));
        });
    });
}
- (void)options {
    if(!S().libraryLoaded)return;
    if(self.tableView.editing&&self.tableView.allowsMultipleSelectionDuringEditing){[self selectionOptions];return;}
    UIAlertController *a = [UIAlertController alertControllerWithTitle:self.title
                                                               message:nil
                                                        preferredStyle:0];
        [self action:a
           title:IPL(@"Reproduciendo")
           block:^{
               if(![IPPlayer shared].track)return;
               [self presentViewController:[[UINavigationController alloc]initWithRootViewController:[IPNow new]] animated:YES completion:nil];
           }];
    if ([self.mode isEqual:@"servers"]) [self action:a title:IPL(@"Idioma") block:^{[self.navigationController pushViewController:[IPLanguageSettings new] animated:YES];}];
    if ([self.mode isEqual:@"servers"]) [self action:a title:IPL(@"Acerca de") block:^{[self.navigationController pushViewController:[IPAbout new] animated:YES];}];
    [self action:a title:IPL(@"Preparación de la biblioteca") block:^{[self.navigationController pushViewController:[IPLibraryPreparation new] animated:YES];}];
    if (self.profile) {
        [self action:a title:IPL(@"Estado de la caché de etiquetas") block:^{IPMetadataProgress *progress=[IPMetadataProgress new];progress.profile=self.profile;[self.navigationController pushViewController:progress animated:YES];}];
        [self
            action:a
             title:IPIsLocalProfile(self.profile)?IPL(@"Refresh local library"):IPL(@"Actualizar biblioteca y M3U")
             block:^{
                 self.status = IPL(@"Escaneando…");
                 [S() scanProfile:self.profile
                     progress:^(NSString *m) {
                         self.status = m;
                         [self.tableView reloadData];
                     }
                     completion:^(NSError *e) {
                         self.status = nil;
                         [self reload];
                         if(IPIsLocalProfile(self.profile)){Message(self,e?e.localizedDescription:S().lastScanWarning?:IPL(@"Local library updated. Tags and artwork are cached automatically."));return;}
                         NSUInteger skipped = 0;
                         for (NSDictionary *p in S().playlists)
                             if ([p[@"profileID"] isEqual:self.profile[@"id"]])
                                 skipped += [p[@"skippedEntries"] unsignedIntegerValue];
                         [IPDiagnostics write];
                         Message(self,
                                 e ? e.localizedDescription
                                   : [NSString
                                         stringWithFormat:
                                             IPL(@"Biblioteca indexada. Los metadatos se completan "
                                             @"automáticamente. Las M3U están "
                                             @"en Playlists. Referencias sin resolver: %lu. %@"),
                                             (unsigned long)skipped, S().lastScanWarning ?: @""]);
                     }];
             }];
        if(!IPIsLocalProfile(self.profile)){
        [self action:a
               title:IPL(@"Probar conexión")
               block:^{
                   [self test:self.profile];
               }];
        [self
            action:a
             title:IPL(@"Reimportar M3U")
             block:^{
                 self.status = IPL(@"Leyendo playlists…");
                 [S() reimportPlaylistsForProfile:self.profile
                     progress:^(NSString *m) {
                         self.status = m;
                         [self.tableView reloadData];
                     }
                     completion:^(NSError *e) {
                         self.status = nil;
                         [self reload];
                         [IPDiagnostics write];
                         NSUInteger matched = 0, unresolved = 0;
                         for (NSDictionary *playlist in S().playlists) {
                             if (![playlist[@"profileID"] isEqual:self.profile[@"id"]] ||
                                 !playlist[@"sourcePath"]) continue;
                             matched += [playlist[@"trackIDs"] count];
                             unresolved += [playlist[@"skippedEntries"] unsignedIntegerValue];
                         }
                         Message(self,
                                 e ? e.localizedDescription
                                   : [NSString stringWithFormat:IPL(@"Playlists importadas. Referencias enlazadas: %lu. Sin resolver: %lu."),
                                      (unsigned long)matched, (unsigned long)unresolved]);
                     }];
             }];

        } else [self action:a title:IPL(@"Local music folders") block:^{Message(self,IPL(@"Local includes iTunes music and readable audio files in this app's Documents folder or /var/mobile/Media. Copy files into Documents using file sharing, or into a music folder under /var/mobile/Media using a file manager. Photos and system folders are skipped. Protected or cloud-only iTunes items cannot be played. This built-in source cannot be edited or deleted."));}];
    }
    if (self.search) {
        [self action:a title:IPL(@"Seleccionar canciones") block:^{[self add];}];
        NSArray *keys=self.playlist?@[@"playlist",@"recent",@"title",@"artist",@"album",@"genre",@"trackNumber"]:@[@"recent",@"title",@"artist",@"album",@"genre",@"trackNumber"];
        NSDictionary *labels=@{@"playlist":IPL(@"Orden de la playlist"),@"recent":IPL(@"Más recientes"),@"title":IPL(@"Título (A–Z)"),@"artist":IPL(@"Artista"),@"album":IPL(@"Álbum"),@"genre":IPL(@"Género"),@"trackNumber":IPL(@"Número de pista")};
        for(NSString *key in keys)[self action:a title:[NSString stringWithFormat:@"%@%@",[self.sortKey isEqual:key]?@"✓ ":IPL(@"Ordenar: "),labels[key]] block:^{self.sortKey=key;NSString *preference=[@"sort-" stringByAppendingString:self.playlist[@"id"]?:self.profile[@"id"]?:self.mode?:@"library"];[[NSUserDefaults standardUserDefaults]setObject:key forKey:preference];[self reload];}];
    }
    if (self.playlist)
        [self action:a
               title:self.tableView.editing ? IPL(@"Terminar orden") : IPL(@"Cambiar orden")
               block:^{
                   self.tableView.allowsMultipleSelectionDuringEditing = NO;
                   [self.tableView setEditing:!self.tableView.editing animated:YES];
                   [self updateSelectionControls];
               }];
    if ([self.mode isEqual:@"downloads"]) {
        [self action:a title:IPL(@"Caché automática") block:^{[self.navigationController pushViewController:[IPCacheSettings new] animated:YES];}];
        [self action:a
               title:IPL(@"Límite de caché (MB)")
               block:^{
                   UIAlertController *c = [UIAlertController
                       alertControllerWithTitle:IPL(@"Límite de caché en MB")
                                        message:IPL(@"No borra descargas existentes. El límite debe "
                                                @"ser mayor al uso actual.")
                                 preferredStyle:1];
                   [c addTextFieldWithConfigurationHandler:^(UITextField *f) {
                       f.keyboardType = UIKeyboardTypeNumberPad;
                       f.text =
                           [NSString stringWithFormat:@"%.0f", S().cacheLimitBytes / 1048576.0];
                   }];
                   [self action:c
                          title:IPL(@"Guardar")
                          block:^{
                              long long v = [c.textFields.firstObject.text longLongValue];
                              if (v < 16 || v > 32768 ||
                                  (unsigned long long)v * 1048576 < S().cacheBytes) {
                                  Message(self, IPL(@"Elige de 16 a 32768 MB, superior al uso actual."));
                                  return;
                              }
                              S().cacheLimitBytes = (unsigned long long)v * 1048576;
                              [S() save];
                              [self reload];
                          }];
                   [self presentMenu:c];
               }];
        [self action:a
               title:IPL(@"Vaciar todas las descargas…")
               block:^{
                   [self confirm:IPL(@"Se borrarán solo las copias de audio locales. Se conservarán "
                                 @"favoritos y playlists.")
                           block:^{
                               NSError *e = nil;
                               [S() clearCache:&e];
                               if (e)
                                   Message(self, e.localizedDescription);
                               [self reload];
                           }];
               }];
    }
    [self presentMenu:a];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)p {return (NSUInteger)p.row<self.rows.count;}
- (BOOL)tableView:(UITableView *)t canMoveRowAtIndexPath:(NSIndexPath *)p {
    return (NSUInteger)p.row<self.rows.count && self.playlist != nil && [self.sortKey isEqual:@"playlist"] && !self.search.searchBar.text.length;
}
- (void)tableView:(UITableView *)t
    moveRowAtIndexPath:(NSIndexPath *)a
           toIndexPath:(NSIndexPath *)b {
    NSMutableArray *ids = self.playlist[@"trackIDs"];
    NSString *song = self.rows[a.row][@"id"];
    [ids removeObject:song];
    [ids insertObject:song atIndex:MIN((NSUInteger)b.row, ids.count)];
    [S() save];
    [self reload];
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)t
           editingStyleForRowAtIndexPath:(NSIndexPath *)p {
    return UITableViewCellEditingStyleNone;
}
@end
@interface IPAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation IPAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = [UIColor colorWithRed:1 green:.18 blue:.33 alpha:1];
    [self installInterfaceShowingLanguageSettings:NO];
    [self.window makeKeyAndVisible];
    [app beginReceivingRemoteControlEvents];
#if defined(IP_IOS6)
    [self becomeFirstResponder];
#endif
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(languageChanged) name:IPLanguageChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(libraryLoaded) name:@"IPLibraryLoaded" object:nil];
    // Return control to UIKit before opening/parsing the saved library.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[S() loadLibrary];});
    return YES;
}
#if defined(IP_IOS6)
- (BOOL)canBecomeFirstResponder {return YES;}
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    IPPlayer *p=[IPPlayer shared];switch(event.subtype){
        case UIEventSubtypeRemoteControlPlay:if(!p.playing)[p toggle];break;
        case UIEventSubtypeRemoteControlPause:if(p.playing)[p toggle];break;
        case UIEventSubtypeRemoteControlTogglePlayPause:[p toggle];break;
        case UIEventSubtypeRemoteControlNextTrack:[p next];break;
        case UIEventSubtypeRemoteControlPreviousTrack:[p previous];break;
        default:break;
    }
}
#endif
- (void)languageChanged {
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;
    UINavigationController *nav = (UINavigationController *)tabs.selectedViewController;
    [self installInterfaceShowingLanguageSettings:[nav.topViewController isKindOfClass:[IPLanguageSettings class]]];
}
- (void)installInterfaceShowingLanguageSettings:(BOOL)showLanguage {
    // Rebuild only the small UI tree; keep the store, audio engine, queue and caches alive.
    NSUInteger selected = [(UITabBarController *)self.window.rootViewController selectedIndex];
    UITabBarController *t = [IPMiniRoot new];
    NSMutableArray *a = [NSMutableArray new];
    NSArray *names = @[ IPL(@"Servidores"), IPL(@"Playlists"), IPL(@"Favoritos"), IPL(@"Descargas") ];
    NSArray *modes = @[ @"servers", @"playlists", @"favorites", @"downloads" ];
    for (int i = 0; i < 4; i++) {
        IPList *l = [IPList new];
        l.mode = modes[i];
        l.title = names[i];
        UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:l];
        n.tabBarItem = [[UITabBarItem alloc] initWithTitle:names[i] image:IPTabImage((IPTabIcon)i) tag:i];
        n.tabBarItem.accessibilityLabel = names[i];
        [a addObject:n];
    }
    t.viewControllers = a;
    self.window.rootViewController = t;
    t.selectedIndex = MIN(selected, a.count - 1);
    if (showLanguage) [(UINavigationController *)a[0] pushViewController:[IPLanguageSettings new] animated:NO];
    __weak UITabBarController *w = t;
    [IPPlayer shared].changed = ^(NSString *error) {
        if (error.length) {
            UIViewController *v = w.selectedViewController;
            while (v.presentedViewController)
                v = v.presentedViewController;
            Message(v, error);
        }
    };
}
- (void)libraryLoaded {
    [[IPPlayer shared]restoreSession];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[IPDiagnostics write];[IPCodecCheck run];});
}
- (void)applicationDidEnterBackground:(UIApplication *)a {
    [[IPPlayer shared]flushSession];
    [S() pausePreparation];
    [S() stopAutomaticMetadata];
    [S() cancelMetadata];
    [S() save];
    [S() flushPersistence];
    [IPDiagnostics write];
}
- (void)applicationWillTerminate:(UIApplication *)app {[[IPPlayer shared]flushSession];}
- (void)applicationDidBecomeActive:(UIApplication *)app {
    IPRefreshSystemLanguage();
    if(S().libraryLoaded)[S() resumePreparation];
    UITabBarController *tabs=(UITabBarController *)self.window.rootViewController;
    UINavigationController *nav=(UINavigationController *)tabs.selectedViewController;
    if([nav.topViewController isKindOfClass:[IPList class]]){IPList *list=(IPList *)nav.topViewController;if(list.profile)[S() refreshProfileIfNeeded:list.profile];[list prioritizeMetadata];}
}
@end

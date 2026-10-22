#import <Foundation/Foundation.h>
/** Persistent records and sort keys. SQLite work is serialized; iOS 9 compatible SQL only. */
@interface IPLibraryDB : NSObject
- (instancetype)initWithURL:(NSURL *)url;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSError *error;
- (NSDictionary *)state;
/** Updates only the small settings/profile record; never reads or rewrites tracks. */
- (BOOL)updateState:(NSDictionary *)state;
- (NSArray *)trackIDs;
- (NSDictionary *)track:(NSString *)tid;
- (NSArray *)recordsForIDs:(NSArray *)ids;
- (NSArray *)recordsForProfileID:(NSString *)profileID;
- (BOOL)commitState:(NSDictionary *)state tracks:(NSArray *)tracks IDs:(NSArray *)ids;
- (BOOL)updateTracks:(NSArray *)tracks;
/** Import remains invisible to normal readers until finishImport succeeds. */
@property(nonatomic,copy) BOOL (^importProgress)(NSUInteger completed, NSString *phase);
- (BOOL)beginImport;
- (BOOL)buildImportIndexes;
- (BOOL)finishImport;
- (NSDictionary *)metadataStatus:(NSDictionary *)profile;
- (NSArray *)pendingMetadata:(NSDictionary *)profile before:(double)date limit:(NSUInteger)limit;
- (NSDictionary *)diagnosticCounts;
- (void)queryProfile:(NSDictionary *)profile
                mode:(NSString *)mode
         playlistIDs:(NSArray *)playlistIDs
                sort:(NSString *)sort
               query:(NSString *)query
              offset:(NSUInteger)offset
               limit:(NSUInteger)limit
          completion:(void (^)(NSArray *ids, NSUInteger total, NSUInteger pending,
                               NSArray *records))completion;
@end

@class IPTrackCollection;
/** Immutable queue of IDs; resolves only the current and upcoming songs. */
@interface IPTrackList : NSArray
@property(nonatomic, copy, readonly) NSArray *trackIDs;
- (instancetype)initWithIDs:(NSArray *)ids collection:(IPTrackCollection *)collection;
@end
/** Mutable legacy-store interface backed by SQLite, with identity-preserving materialization. */
@interface IPTrackCollection : NSMutableArray
- (instancetype)initWithDatabase:(IPLibraryDB *)database IDs:(NSArray *)ids;
@property(nonatomic, copy, readonly) NSArray *trackIDs;
@property(nonatomic, copy, readonly) NSArray *materializedTracks;
@property(nonatomic, copy, readonly) NSArray *changedTracks;
- (void)acknowledgeTracks:(NSArray *)records;
#if defined(IP_IOS6)
/** Merge tags only into already visible/resolved objects; never hydrate the whole library. */
- (void)mergeMaterializedMetadata:(NSArray *)updates acknowledged:(BOOL)acknowledged;
- (nullable NSMutableDictionary *)materializedTrackForID:(NSString *)tid;
#endif
- (NSMutableDictionary *)trackForID:(NSString *)tid;
- (NSArray *)materializeIDs:(NSArray *)ids;
- (NSArray *)materializeRecords:(NSArray *)records;
- (NSArray *)queueForIDs:(NSArray *)ids;
- (void)replaceProfileRecords:(NSArray *)records previous:(NSDictionary *)previous;
@end

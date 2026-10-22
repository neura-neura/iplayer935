#import <Foundation/Foundation.h>

@class IPSmartCache, IPLibraryDB;
NS_ASSUME_NONNULL_BEGIN

typedef void (^IPStoreProgress)(NSString *message);
typedef void (^IPStoreCompletion)(NSError * _Nullable error);

/** Offline library, account credentials, and explicitly requested SMB downloads. */
@interface IPStore : NSObject
#if defined(IP_IOS6)
@property(atomic,readonly) BOOL legacyLibraryWritePending;
#endif

+ (instancetype)sharedStore;
+ (instancetype)shared;
/** Built-in source, separate from editable SMB profiles. */
@property(nonatomic,strong,readonly) NSMutableDictionary *localProfile;

/** Mutable model dictionaries are exposed for the existing UIKit screens. Call save after edits. */
@property (nonatomic, strong, readonly) NSMutableArray<NSMutableDictionary *> *profiles;
@property (nonatomic, strong, readonly) NSMutableArray<NSMutableDictionary *> *tracks;
@property (nonatomic, strong, readonly) NSMutableArray<NSMutableDictionary *> *playlists;

/** Maximum cache size in bytes. Defaults to 2 GiB. */
@property (nonatomic) unsigned long long cacheLimitBytes;
/** Current size of completed cached files in bytes. */
@property (nonatomic, readonly) unsigned long long cacheBytes;
/** Summary of the most recent scan's unsupported formats and unmatched playlist references. */
@property (nonatomic, copy, readonly, nullable) NSString *lastScanWarning;

@property(nonatomic,strong,readonly) IPSmartCache *smartCache;
- (void)preparePlaybackCacheForQueue:(NSArray *)queue index:(NSInteger)index;
/** Profiles are available immediately; the large library loads off the UI thread. */
@property(nonatomic,readonly) BOOL libraryLoaded;
- (void)loadLibrary;
@property(nonatomic,copy,readonly) NSDictionary *preparationStatus;
- (void)pausePreparation;
- (void)resumePreparation;
@property(nonatomic,strong,readonly,nullable) IPLibraryDB *database;
- (nullable NSMutableDictionary *)trackWithID:(NSString *)tid;
- (NSArray *)materializeTrackIDs:(NSArray *)ids;
- (NSArray *)materializeTrackRecords:(NSArray *)records;
- (NSArray *)queueForTrackIDs:(NSArray *)ids;
- (void)queryProfile:(nullable NSDictionary *)profile mode:(NSString *)mode playlistIDs:(nullable NSArray *)playlistIDs sort:(nullable NSString *)sort query:(nullable NSString *)query offset:(NSUInteger)offset limit:(NSUInteger)limit completion:(void (^)(NSArray *ids,NSUInteger total,NSUInteger pending,NSArray *records))completion;
- (void)save;
/** Persists a favorite toggle without serializing the full library. Call on the main thread. */
- (BOOL)setFavorite:(BOOL)favorite forTrack:(NSDictionary *)track;
- (void)setFavorite:(BOOL)favorite forTracks:(NSArray *)tracks;
/** Waits for queued atomic library writes to reach disk. Call from app background handling. */
- (void)flushPersistence;
- (nullable NSMutableDictionary *)profileForTrack:(NSDictionary *)track;
- (nullable NSURL *)localURLForTrack:(NSDictionary *)track;
- (nullable NSURL *)localURL:(NSDictionary *)track;
- (nullable NSURL *)artworkURLForTrack:(NSDictionary *)track;

- (BOOL)setPassword:(NSString *)password forProfileID:(NSString *)profileID error:(NSError **)error;
- (nullable NSString *)passwordForProfileID:(NSString *)profileID error:(NSError **)error;
- (nullable NSString *)passwordForProfile:(NSDictionary *)profile error:(NSError **)error;
- (BOOL)deletePasswordForProfileID:(NSString *)profileID error:(NSError **)error;

/** Deletes profile credentials and its cached tracks. Playlist references are pruned. */
- (BOOL)deleteProfile:(NSMutableDictionary *)profile error:(NSError **)error;
/** Replaces endpoint settings and rotates endpointIdentity, so stale track IDs cannot match. */
- (BOOL)setEndpoint:(NSDictionary *)endpoint forProfileID:(NSString *)profileID error:(NSError **)error;

- (BOOL)removeDownloadForTrack:(NSDictionary *)track error:(NSError **)error;
- (BOOL)clearCache:(NSError **)error;

/** Refreshes the profile's persistent library recursively. Existing favorites are retained. */
- (void)scanProfile:(NSMutableDictionary *)profile
           progress:(nullable IPStoreProgress)progress
         completion:(nullable IPStoreCompletion)completion;

/** Fills missing AV metadata incrementally after the library has already been committed. */
- (void)enrichProfile:(NSMutableDictionary *)profile
             progress:(nullable IPStoreProgress)progress
           completion:(nullable IPStoreCompletion)completion;
/** Stops the active metadata request and prevents further enrichment work. */
- (void)cancelMetadata;
/** Refreshes AV metadata for one selected track, for example when its detail view opens. */
- (void)refreshMetadataForTrack:(NSDictionary *)track completion:(nullable IPStoreCompletion)completion;
/** Applies software-decoder tags and downsizes artwork off the main thread. */
- (void)applyDecodedMetadata:(NSDictionary *)metadata toTrack:(NSDictionary *)track completion:(nullable IPStoreCompletion)completion;
/** Background tag indexing prioritizes visible rows and reuses one SMB connection for MP3. */
- (void)ensureMetadataForProfile:(NSDictionary *)profile priorityTracks:(NSArray *)tracks;
- (void)refreshProfileIfNeeded:(NSMutableDictionary *)profile;
- (void)stopAutomaticMetadata;
@property(atomic) BOOL playbackActive;
- (NSDictionary *)metadataCacheStatusForProfile:(NSDictionary *)profile;
- (void)setMetadataPaused:(BOOL)paused forProfile:(NSDictionary *)profile;
- (NSUInteger)metadataPendingCountForProfile:(NSDictionary *)profile;
/** Re-reads known M3U files for the profile without recursively scanning its media tree. */
- (void)reimportPlaylistsForProfile:(NSMutableDictionary *)profile
                           progress:(nullable IPStoreProgress)progress
                         completion:(nullable IPStoreCompletion)completion;

/** Downloads only the supplied tracks. Files are written through bounded-memory temporary files. */
- (void)downloadTracks:(NSArray<NSDictionary *> *)tracks
              progress:(nullable IPStoreProgress)progress
            completion:(nullable IPStoreCompletion)completion;

@end

NS_ASSUME_NONNULL_END

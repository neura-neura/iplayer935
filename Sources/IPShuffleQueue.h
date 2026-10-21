#import <Foundation/Foundation.h>
/** Permutes queue positions, keeping metadata lazy and duplicate playlist entries distinct. */
@interface IPShuffleQueue : NSArray
@property(nonatomic,strong,readonly) NSArray *originalQueue;
@property(nonatomic,copy,readonly) NSArray *order;
@property(nonatomic,copy,readonly) NSArray *trackIDs;
- (instancetype)initWithQueue:(NSArray *)queue currentIndex:(NSUInteger)index;
- (instancetype)initWithQueue:(NSArray *)queue order:(NSArray *)order;
- (NSUInteger)originalIndexAtIndex:(NSUInteger)index;
@end

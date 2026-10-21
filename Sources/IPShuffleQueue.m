#import "IPShuffleQueue.h"
#include <stdlib.h>
@implementation IPShuffleQueue
- (instancetype)initWithQueue:(NSArray *)queue currentIndex:(NSUInteger)index {
    if(!queue.count)return [self initWithQueue:queue order:@[]];
    index=MIN(index,queue.count-1);
    NSMutableArray *order=[NSMutableArray arrayWithCapacity:queue.count];
    [order addObject:@(index)];
    for(NSUInteger i=0;i<queue.count;i++)if(i!=index)[order addObject:@(i)];
    // Unbiased Fisher–Yates over the remaining positions; current audio stays untouched.
    for(NSUInteger i=order.count-1;i>1;i--){NSUInteger j=1+arc4random_uniform((uint32_t)i);[order exchangeObjectAtIndex:i withObjectAtIndex:j];}
    return [self initWithQueue:queue order:order];
}
- (instancetype)initWithQueue:(NSArray *)queue order:(NSArray *)order {
    if((self=[super init])){_originalQueue=[queue copy];_order=[order copy];}return self;
}
- (NSUInteger)count {return self.order.count;}
- (id)objectAtIndex:(NSUInteger)index {return self.originalQueue[[self originalIndexAtIndex:index]];}
- (NSUInteger)originalIndexAtIndex:(NSUInteger)index {return [self.order[index]unsignedIntegerValue];}
- (id)copyWithZone:(NSZone *)zone {return self;}
- (NSArray *)trackIDs {
    NSArray *ids=[self.originalQueue respondsToSelector:@selector(trackIDs)]?[(id)self.originalQueue trackIDs]:[self.originalQueue valueForKey:@"id"];
    NSMutableArray *result=[NSMutableArray arrayWithCapacity:self.count];for(NSNumber *n in self.order)[result addObject:ids[n.unsignedIntegerValue]];return result;
}
@end

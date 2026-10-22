#import "IPControlIcons.h"
#import <math.h>
UIImage *IPControlImage(IPControlIcon kind) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,26),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();CGContextSetLineWidth(c,1.8);CGContextSetLineCap(c,kCGLineCapRound);CGContextSetLineJoin(c,kCGLineJoinRound);
#if defined(IP_IOS6)
    if(kind==IPControlIconOptions){
        // Compact settings wheel suits the native embossed bar-button treatment.
        CGContextSetLineWidth(c,4);
        for(int i=0;i<8;i++){CGFloat a=i*M_PI/4;CGContextMoveToPoint(c,13+7*cos(a),13+7*sin(a));CGContextAddLineToPoint(c,13+11*cos(a),13+11*sin(a));}CGContextStrokePath(c);
        CGContextSetLineWidth(c,3);CGContextStrokeEllipseInRect(c,CGRectMake(6,6,14,14));
    }else
#endif
    if(kind==IPControlIconOptions){
        CGContextStrokeEllipseInRect(c,CGRectMake(2,2,22,22));
        for(int i=0;i<3;i++)CGContextFillEllipseInRect(c,CGRectMake(6+i*6,11.5,3,3));
    }else if(kind==IPControlIconSelect){
        for(int i=0;i<2;i++){CGFloat y=6+i*12;CGContextMoveToPoint(c,2,y);CGContextAddLineToPoint(c,4,y+2);CGContextAddLineToPoint(c,8,y-3);CGContextMoveToPoint(c,12,y);CGContextAddLineToPoint(c,24,y);}CGContextStrokePath(c);
    }else{
        CGContextMoveToPoint(c,2,6);CGContextAddLineToPoint(c,7,6);CGContextAddLineToPoint(c,19,20);CGContextAddLineToPoint(c,24,20);
        CGContextMoveToPoint(c,2,20);CGContextAddLineToPoint(c,7,20);CGContextAddLineToPoint(c,19,6);CGContextAddLineToPoint(c,24,6);
        CGContextMoveToPoint(c,21,3);CGContextAddLineToPoint(c,24,6);CGContextAddLineToPoint(c,21,9);
        CGContextMoveToPoint(c,21,17);CGContextAddLineToPoint(c,24,20);CGContextAddLineToPoint(c,21,23);CGContextStrokePath(c);
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *DrawTabIcon(IPTabIcon kind) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26,26),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(c,[UIColor blackColor].CGColor);
    CGContextSetFillColorWithColor(c,[UIColor blackColor].CGColor);
    CGContextSetLineWidth(c,1.7);
    CGContextSetLineCap(c,kCGLineCapRound);
    CGContextSetLineJoin(c,kCGLineJoinRound);
    if(kind==IPTabIconServers){
        for(int i=0;i<2;i++){
            CGFloat y=4+i*11;
            UIBezierPath *box=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3,y,20,7) cornerRadius:2];
            CGContextAddPath(c,box.CGPath);CGContextStrokePath(c);
            CGContextFillEllipseInRect(c,CGRectMake(6,y+2.5,2,2));
            CGContextMoveToPoint(c,12,y+3.5);CGContextAddLineToPoint(c,19,y+3.5);CGContextStrokePath(c);
        }
    }else if(kind==IPTabIconPlaylists){
        for(int i=0;i<3;i++){
            CGFloat y=5+i*6;
            CGContextMoveToPoint(c,3,y);CGContextAddLineToPoint(c,i==0?22:13,y);CGContextStrokePath(c);
        }
        CGContextMoveToPoint(c,21,10);CGContextAddLineToPoint(c,21,21);
        CGContextMoveToPoint(c,21,10);CGContextAddLineToPoint(c,24,9);CGContextStrokePath(c);
        CGContextFillEllipseInRect(c,CGRectMake(16,19,6,4));
    }else if(kind==IPTabIconFavorites){
        for(int i=0;i<10;i++){
            CGFloat angle=-M_PI_2+i*M_PI/5,radius=i%2?5:11;
            CGFloat x=13+cos(angle)*radius,y=13+sin(angle)*radius;
            if(i==0)CGContextMoveToPoint(c,x,y);else CGContextAddLineToPoint(c,x,y);
        }
        CGContextClosePath(c);CGContextFillPath(c);
    }else{
        CGContextMoveToPoint(c,13,3);CGContextAddLineToPoint(c,13,17);
        CGContextMoveToPoint(c,8,12);CGContextAddLineToPoint(c,13,17);CGContextAddLineToPoint(c,18,12);
        CGContextMoveToPoint(c,4,18);CGContextAddLineToPoint(c,4,23);CGContextAddLineToPoint(c,22,23);CGContextAddLineToPoint(c,22,18);CGContextStrokePath(c);
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *IPTabImage(IPTabIcon kind) {
    // Four small template images, drawn once and reused across language changes.
    static NSArray *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ images=@[DrawTabIcon(IPTabIconServers),DrawTabIcon(IPTabIconPlaylists),DrawTabIcon(IPTabIconFavorites),DrawTabIcon(IPTabIconDownloads)]; });
    return images[(NSUInteger)kind];
}

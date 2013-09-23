//
//  ZXHVisionCameraTargetView.m
//  Vision
//
//  Created by 曾 宪华 on 13-9-9.
//  Copyright (c) 2013年 Patrick Piemonte. All rights reserved.
//

#import "ZXHVisionCameraTargetView.h"

#import <QuartzCore/QuartzCore.h>

@implementation ZXHVisionCameraTargetView

- (void)_CameraTargetViewCommonInit
{
    self.clipsToBounds = NO;
    self.userInteractionEnabled = NO;
    self.layer.shadowColor = [UIColor colorWithRed:0.04 green:0.21 blue:0.48 alpha:1].CGColor;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowOpacity = 1;
    self.layer.shadowRadius = 2;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _CameraTargetViewCommonInit];
    }
    return self;
}

- (void)awakeFromNib
{
    [self _CameraTargetViewCommonInit];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.20 green:0.70 blue:1.0 alpha:1.0].CGColor);
    CGContextStrokeRectWithWidth(context, rect, 2);
    
    CGFloat innerLineLength = 6;
    
    CGContextMoveToPoint(context, rect.origin.x, rect.origin.y + rect.size.height/2);
    CGContextAddLineToPoint(context, rect.origin.x + innerLineLength, rect.origin.y + rect.size.height/2);
    
    CGContextMoveToPoint(context, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height/2);
    CGContextAddLineToPoint(context, rect.origin.x + rect.size.width - innerLineLength, rect.origin.y + rect.size.height/2);
    
    CGContextMoveToPoint(context, rect.origin.x + rect.size.width/2, rect.origin.y);
    CGContextAddLineToPoint(context, rect.origin.x + rect.size.width/2, rect.origin.y + innerLineLength);
    
    CGContextMoveToPoint(context, rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height);
    CGContextAddLineToPoint(context, rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height - innerLineLength);
    
    CGContextStrokePath(context);
    
    CGContextRestoreGState(context);
}

- (void)showAnimated:(BOOL)animated
{
    self.transform = CGAffineTransformMakeScale(2, 2);
    self.alpha = 0;
    
    void (^animations)(void) = ^{
        self.transform = CGAffineTransformMakeScale(1, 1);
        self.alpha = 1;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:animations];
    }
    else {
        animations();
    }
}

- (void)hideAnimated:(BOOL)animated
{
    void (^animations)(void) = ^{
        self.alpha = 0;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:animations];
    }
    else {
        animations();
    }
}


@end

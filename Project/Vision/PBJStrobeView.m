//
//  PBJStrobeView.m
//  Vision
//
//  Created by Patrick Piemonte on 7/23/13.
//  Copyright (c) 2013 Patrick Piemonte. All rights reserved.
//

#import "PBJStrobeView.h"

#import <QuartzCore/QuartzCore.h>

@interface PBJStrobeView ()
{
    UIImageView *_strobeView;
    UIImageView *_strobeViewRecord;
    UIImageView *_strobeViewRecordIdle;
}

@end

@implementation PBJStrobeView

- (UIImageView *)_strobeView
{
    UIImage *strobeDisc = [UIImage imageNamed:@"capture_rec_base"];
    UIImageView *strobeView = [[UIImageView alloc] initWithImage:strobeDisc];
    return strobeView;
}

- (UIImageView *)_strobeViewRecord
{
    UIImage *strobeDisc = [UIImage imageNamed:@"capture_rec_blink"];
    UIImageView *strobeView = [[UIImageView alloc] initWithImage:strobeDisc];
    return strobeView;
}

- (UIImageView *)_strobeViewRecordIdle
{
    UIImage *strobeDisc = [UIImage imageNamed:@"capture_rec_off"];
    UIImageView *strobeView = [[UIImageView alloc] initWithImage:strobeDisc];
    return strobeView;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {

        CGFloat padding = 4.0f;
    
        self.backgroundColor = [UIColor blackColor];
        CGRect viewFrame = CGRectZero;
        viewFrame.size = CGSizeMake(100.0f, 30.0f);
        self.frame = viewFrame;
                
        _strobeView = [self _strobeView];
        CGRect strobeFrame = _strobeView.frame;
        strobeFrame.origin = CGPointMake(padding, self.frame.size.height - _strobeView.frame.size.height - padding);
        _strobeView.frame = strobeFrame;
        [self addSubview:_strobeView];
        
        _strobeViewRecord = [self _strobeViewRecord];
        _strobeViewRecord.frame = strobeFrame;
        _strobeViewRecord.transform = CGAffineTransformMakeScale(0.7f, 0.7f);
        _strobeViewRecord.alpha = 0;
        [self addSubview:_strobeViewRecord];

        _strobeViewRecordIdle = [self _strobeViewRecordIdle];
        _strobeViewRecordIdle.frame = strobeFrame;
        _strobeViewRecordIdle.transform = CGAffineTransformMakeScale(0.7f, 0.7f);
        [self addSubview:_strobeViewRecordIdle];

    }
    return self;
}

- (void)start
{
    _strobeViewRecord.alpha = 1;
    [UIView animateWithDuration:0.1f delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _strobeViewRecordIdle.transform = CGAffineTransformMakeScale(0, 0);
    } completion:^(BOOL finished) {
    }];
}

- (void)stop
{
    [_strobeViewRecord.layer removeAllAnimations];

    _strobeViewRecord.alpha = 0;
    [UIView animateWithDuration:0.2f delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _strobeViewRecordIdle.transform = CGAffineTransformMakeScale(0.7f, 0.7f);
    } completion:^(BOOL finished) {
    }];
}

@end

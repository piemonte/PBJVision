//
//  PBJStrobeView.m
//  PBJVision
//
//  Created by Patrick Piemonte on 7/23/13.
//  Copyright (c) 2013-present, Patrick Piemonte, http://patrickpiemonte.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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

//
//  PBJFocusView.m
//  PBJVision
//
//  Created by Patrick Piemonte on 5/19/13.
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

#import "PBJFocusView.h"

@interface PBJFocusView ()
{
    UIImageView *_focusRingView;
}

@end

@implementation PBJFocusView

#pragma mark - init

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeScaleToFill;
        _focusRingView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"capture_focus"]];
        [self addSubview:_focusRingView];
        
        self.frame = _focusRingView.frame;
    }
    return self;
}

- (void)dealloc
{
    [self.layer removeAllAnimations];
}

#pragma mark -

- (void)startAnimation
{
    [self.layer removeAllAnimations];
    
    self.transform = CGAffineTransformMakeScale(1.4f, 1.4f);
    self.alpha = 0;
    
    [UIView animateWithDuration:0.4f delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
    
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
        
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.4f delay:0 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
    
            self.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
            self.alpha = 1;
            
        } completion:^(BOOL finished1) {
        }];
    }];
}

- (void)stopAnimation
{
    [self.layer removeAllAnimations];

    [UIView animateWithDuration:0.2f delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    
        self.transform = CGAffineTransformMakeScale(0.001f, 0.001f);
        self.alpha = 0;
    
    } completion:^(BOOL finished) {
        
        [self removeFromSuperview];
        
    }];
}

@end

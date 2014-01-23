//
//  PBJViewController.m
//  Vision
//
//  Created by Patrick Piemonte on 7/23/13.
//  Copyright (c) 2013 Patrick Piemonte. All rights reserved.
//

#import "PBJViewController.h"
#import "PBJStrobeView.h"
#import "PBJFocusView.h"

#import "PBJVision.h"
#import "PBJVisionUtilities.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <GLKit/GLKit.h>

@interface ExtendedHitButton: UIButton

+ (instancetype) extendedHitButton;

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;

@end

@implementation ExtendedHitButton

+ (instancetype) extendedHitButton
{
    return (ExtendedHitButton *) [ExtendedHitButton buttonWithType:UIButtonTypeCustom];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    CGRect relativeFrame = self.bounds;
    UIEdgeInsets hitTestEdgeInsets = UIEdgeInsetsMake(-35, -35, -35, -35);
    CGRect hitFrame = UIEdgeInsetsInsetRect(relativeFrame, hitTestEdgeInsets);
    return CGRectContainsPoint(hitFrame, point);
}

@end

@interface PBJViewController () <
    UIGestureRecognizerDelegate,
    PBJVisionDelegate,
    UIAlertViewDelegate>
{
    PBJStrobeView *_strobeView;
    UIButton *_doneButton;
    
    UIButton *_flipButton;
    UIButton *_focusButton;
    UIButton *_onionButton;

    UIView *_previewView;
    AVCaptureVideoPreviewLayer *_previewLayer;
    PBJFocusView *_focusView;
    UIView *_gestureView;
    GLKViewController *_effectsViewController;
    
    UILabel *_instructionLabel;
    
    UILongPressGestureRecognizer *_longPressGestureRecognizer;
    UITapGestureRecognizer *_tapGestureRecognizer;
    
    BOOL _recording;

    ALAssetsLibrary *_assetLibrary;
    __block NSDictionary *_currentVideo;
}

@end

@implementation PBJViewController

#pragma mark - UIViewController

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - init

- (void)dealloc
{
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    _longPressGestureRecognizer.delegate = nil;
}

#pragma mark - view lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    _assetLibrary = [[ALAssetsLibrary alloc] init];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.view.backgroundColor = [UIColor blackColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
    CGFloat viewWidth = CGRectGetWidth(self.view.frame);
    
    // done button
    _doneButton = [ExtendedHitButton extendedHitButton];
    _doneButton.frame = CGRectMake(viewWidth - 20.0f - 20.0f, 20.0f, 20.0f, 20.0f);
    
    UIImage *buttonImage = [UIImage imageNamed:@"capture_yep"];
    [_doneButton setImage:buttonImage forState:UIControlStateNormal];
    
    [_doneButton addTarget:self action:@selector(_handleDoneButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_doneButton];
    
    // elapsed time and red dot
    _strobeView = [[PBJStrobeView alloc] initWithFrame:CGRectZero];
    CGRect strobeFrame = _strobeView.frame;
    strobeFrame.origin = CGPointMake(15.0f, 15.0f);
    _strobeView.frame = strobeFrame;
    [self.view addSubview:_strobeView];

    // preview
    _previewView = [[UIView alloc] initWithFrame:CGRectZero];
    _previewView.backgroundColor = [UIColor blackColor];
    CGRect previewFrame = CGRectMake(0, 60.0f, CGRectGetWidth(self.view.frame), CGRectGetWidth(self.view.frame));
    _previewView.frame = previewFrame;
    _previewLayer = [[PBJVision sharedInstance] previewLayer];
    _previewLayer.frame = _previewView.bounds;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_previewView.layer addSublayer:_previewLayer];
    
    // focus view
    _focusView = [[PBJFocusView alloc] initWithFrame:CGRectZero];
    
    // onion skin
    _effectsViewController = [[GLKViewController alloc] init];
    _effectsViewController.preferredFramesPerSecond = 60;
    
    GLKView *view = (GLKView *)_effectsViewController.view;
    CGRect viewFrame = _previewView.bounds;
    view.frame = viewFrame;
    view.context = [[PBJVision sharedInstance] context];
    view.contentScaleFactor = [[UIScreen mainScreen] scale];
    view.alpha = 0.5f;
    view.hidden = YES;
    [[PBJVision sharedInstance] setPresentationFrame:_previewView.frame];
    [_previewView addSubview:_effectsViewController.view];

    // instruction label
    _instructionLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    _instructionLabel.textAlignment = NSTextAlignmentCenter;
    _instructionLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0f];
    _instructionLabel.textColor = [UIColor whiteColor];
    _instructionLabel.backgroundColor = [UIColor blackColor];
    _instructionLabel.text = NSLocalizedString(@"Touch and hold to record", @"Instruction message for capturing video.");
    [_instructionLabel sizeToFit];
    CGPoint labelCenter = _previewView.center;
    labelCenter.y += ((CGRectGetHeight(_previewView.frame) * 0.5f) + 35.0f);
    _instructionLabel.center = labelCenter;
    [self.view addSubview:_instructionLabel];
    
    // press to record gesture
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleLongPressGestureRecognizer:)];
    _longPressGestureRecognizer.delegate = self;
    _longPressGestureRecognizer.minimumPressDuration = 0.05f;
    _longPressGestureRecognizer.allowableMovement = 10.0f;
    
    // tap to focus
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleFocusTapGesterRecognizer:)];
    _tapGestureRecognizer.delegate = self;
    _tapGestureRecognizer.numberOfTapsRequired = 1;
    _tapGestureRecognizer.enabled = NO;
    [_previewView addGestureRecognizer:_tapGestureRecognizer];
    
    // gesture view to record
    _gestureView = [[UIView alloc] initWithFrame:CGRectZero];
    CGRect gestureFrame = self.view.bounds;
    gestureFrame.origin = CGPointMake(0, 60.0f);
    gestureFrame.size.height -= (40.0f + 85.0f);
    _gestureView.frame = gestureFrame;
    
    [self.view addSubview:_gestureView];
    [_gestureView addGestureRecognizer:_longPressGestureRecognizer];

    // flip button
    _flipButton = [ExtendedHitButton extendedHitButton];
    [_flipButton setImage:[UIImage imageNamed:@"capture_flip"] forState:UIControlStateNormal];
    _flipButton.frame = CGRectMake(15.0f, CGRectGetHeight(self.view.bounds) - 25.0f - 15.0f, 30.0f, 25.0f);
    [_flipButton addTarget:self action:@selector(_handleFlipButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_flipButton];
    
    // focus mode button
    _focusButton = [ExtendedHitButton extendedHitButton];
    [_focusButton setImage:[UIImage imageNamed:@"capture_focus_button"] forState:UIControlStateNormal];
    [_focusButton setImage:[UIImage imageNamed:@"capture_focus_button_active"] forState:UIControlStateSelected];
    _focusButton.frame = CGRectMake( (CGRectGetWidth(self.view.bounds) * 0.5f) - 10.0f, CGRectGetHeight(self.view.bounds) - 25.0f - 15.0f, 25.0f, 25.0f);
    _focusButton.imageView.frame = _focusButton.bounds;
    [_focusButton addTarget:self action:@selector(_handleFocusButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_focusButton];
    
    // onion button
    _onionButton = [ExtendedHitButton extendedHitButton];
    [_onionButton setImage:[UIImage imageNamed:@"capture_onion"] forState:UIControlStateNormal];
    [_onionButton setImage:[UIImage imageNamed:@"capture_onion_selected"] forState:UIControlStateSelected];
    _onionButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 25.0f - 15.0f, CGRectGetHeight(self.view.bounds) - 25.0f - 15.0f, 25.0f, 25.0f);
    [_onionButton addTarget:self action:@selector(_handleOnionSkinningButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_onionButton];
    
    [self _resetCapture];
    [[PBJVision sharedInstance] startPreview];
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[PBJVision sharedInstance] stopPreview];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationSlide];
}

#pragma mark - private start/stop helper methods

- (void)_startCapture
{
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    [UIView animateWithDuration:0.2f delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _instructionLabel.alpha = 0;
    } completion:^(BOOL finished) {
    }];
    [[PBJVision sharedInstance] startVideoCapture];
}

- (void)_pauseCapture
{
    [UIView animateWithDuration:0.2f delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _instructionLabel.alpha = 1;
    } completion:^(BOOL finished) {
    }];

    [[PBJVision sharedInstance] pauseVideoCapture];
    _effectsViewController.view.hidden = !_onionButton.selected;
}

- (void)_resumeCapture
{
    [UIView animateWithDuration:0.2f delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _instructionLabel.alpha = 0;
    } completion:^(BOOL finished) {
    }];
    
    [[PBJVision sharedInstance] resumeVideoCapture];
    _effectsViewController.view.hidden = YES;
}

- (void)_endCapture
{
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [[PBJVision sharedInstance] endVideoCapture];
    _effectsViewController.view.hidden = YES;
}

- (void)_resetCapture
{
    [_strobeView stop];
    _longPressGestureRecognizer.enabled = YES;

    PBJVision *vision = [PBJVision sharedInstance];
    vision.delegate = self;

    if ([vision isCameraDeviceAvailable:PBJCameraDeviceBack]) {
        [vision setCameraDevice:PBJCameraDeviceBack];
    } else {
        [vision setCameraDevice:PBJCameraDeviceFront];
        _flipButton.hidden = YES;
        _focusButton.hidden = YES;
    }
    
    [vision setCameraMode:PBJCameraModeVideo];
    [vision setCameraOrientation:PBJCameraOrientationPortrait];
    [vision setFocusMode:PBJFocusModeContinuousAutoFocus];
    [vision setOutputFormat:PBJOutputFormatSquare];
    [vision setVideoRenderingEnabled:YES];
}

#pragma mark - UIButton

- (void)_handleFlipButton:(UIButton *)button
{
    PBJVision *vision = [PBJVision sharedInstance];
    if (vision.cameraDevice == PBJCameraDeviceBack) {
        _focusButton.hidden = YES;
        [vision setCameraDevice:PBJCameraDeviceFront];
    } else {
        _focusButton.hidden = NO;
        [vision setCameraDevice:PBJCameraDeviceBack];
    }
}

- (void)_handleFocusButton:(UIButton *)button
{
    _focusButton.selected = !_focusButton.selected;
    
    if (_focusButton.selected) {
        _tapGestureRecognizer.enabled = YES;
        _gestureView.hidden = YES;

    } else {
        if (_focusView && [_focusView superview]) {
            [_focusView stopAnimation];
        }
        _tapGestureRecognizer.enabled = NO;
        _gestureView.hidden = NO;
    }
    
    [UIView animateWithDuration:0.15f delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _instructionLabel.alpha = 0;
    } completion:^(BOOL finished) {
        _instructionLabel.text = _focusButton.selected ? NSLocalizedString(@"Touch to focus", @"Touch to focus") :
                                                         NSLocalizedString(@"Touch and hold to record", @"Touch and hold to record");
        [UIView animateWithDuration:0.15f delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            _instructionLabel.alpha = 1;
        } completion:^(BOOL finished1) {
        }];
    }];
}

- (void)_handleOnionSkinningButton:(UIButton *)button
{
//    [_onionButton setSelected:!_onionButton.selected];
//    if (_recording)
//        _effectsViewController.view.hidden = !_onionButton.selected;
    [[PBJVision sharedInstance] capturePreviewPhoto];
}

- (void)_handleDoneButton:(UIButton *)button
{
    // resets long press
    _longPressGestureRecognizer.enabled = NO;
    _longPressGestureRecognizer.enabled = YES;
    
    [self _endCapture];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self _resetCapture];
}

#pragma mark - UIGestureRecognizer

- (void)_handleLongPressGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state) {
      case UIGestureRecognizerStateBegan:
        {
            if (!_recording)
                [self _startCapture];
            else
                [self _resumeCapture];
            break;
        }
      case UIGestureRecognizerStateEnded:
      case UIGestureRecognizerStateCancelled:
      case UIGestureRecognizerStateFailed:
        {
            [self _pauseCapture];
            break;
        }
      default:
        break;
    }
}

- (void)_handleFocusTapGesterRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint tapPoint = [gestureRecognizer locationInView:_previewView];

    // auto focus is occuring, display focus view
    CGPoint point = tapPoint;
    
    CGRect focusFrame = _focusView.frame;
#if defined(__LP64__) && __LP64__
    focusFrame.origin.x = rint(point.x - (focusFrame.size.width * 0.5));
    focusFrame.origin.y = rint(point.y - (focusFrame.size.height * 0.5));
#else
    focusFrame.origin.x = rintf(point.x - (focusFrame.size.width * 0.5f));
    focusFrame.origin.y = rintf(point.y - (focusFrame.size.height * 0.5f));
#endif
    [_focusView setFrame:focusFrame];
    
    [_previewView addSubview:_focusView];
    [_focusView startAnimation];

    CGPoint adjustPoint = [PBJVisionUtilities convertToPointOfInterestFromViewCoordinates:tapPoint inFrame:_previewView.frame];
    [[PBJVision sharedInstance] focusAtAdjustedPoint:adjustPoint];
}

#pragma mark - PBJVisionDelegate

-(void)vision:(PBJVision *)vision capturedLivePhotoFromBuffer:(CGImageRef)imageRef {
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    NSLog(@"image is %@", image);
}

- (void)visionSessionWillStart:(PBJVision *)vision
{
}

- (void)visionSessionDidStart:(PBJVision *)vision
{
    if (![_previewView superview]) {
        [self.view addSubview:_previewView];
        [self.view bringSubviewToFront:_gestureView];
    }
}

- (void)visionSessionDidStop:(PBJVision *)vision
{
    [_previewView removeFromSuperview];
}

- (void)visionModeWillChange:(PBJVision *)vision
{
}

- (void)visionModeDidChange:(PBJVision *)vision
{
}

- (void)vision:(PBJVision *)vision didChangeCleanAperture:(CGRect)cleanAperture
{
}

- (void)visionWillStartFocus:(PBJVision *)vision
{
}

- (void)visionDidStopFocus:(PBJVision *)vision
{
    if (_focusView && [_focusView superview]) {
        [_focusView stopAnimation];
    }
}

// photo

- (void)visionWillCapturePhoto:(PBJVision *)vision
{
}

- (void)visionDidCapturePhoto:(PBJVision *)vision
{
}

- (void)vision:(PBJVision *)vision capturedPhoto:(NSDictionary *)photoDict error:(NSError *)error
{
}

// video capture

- (void)visionDidStartVideoCapture:(PBJVision *)vision
{
    [_strobeView start];
    _recording = YES;
}

- (void)visionDidPauseVideoCapture:(PBJVision *)vision
{
    [_strobeView stop];
}

- (void)visionDidResumeVideoCapture:(PBJVision *)vision
{
    [_strobeView start];
}

- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error
{
    _recording = NO;

    if (error) {
        NSLog(@"encounted an error in video capture (%@)", error);
        return;
    }

    _currentVideo = videoDict;
    
    NSString *videoPath = [_currentVideo  objectForKey:PBJVisionVideoPathKey];
    [_assetLibrary writeVideoAtPathToSavedPhotosAlbum:[NSURL URLWithString:videoPath] completionBlock:^(NSURL *assetURL, NSError *error1) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Saved!" message: @"Saved to the camera roll."
                                                       delegate:self
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"OK", nil];
        [alert show];
    }];
}

// progress

- (void)visionDidCaptureAudioSample:(PBJVision *)vision
{
//    NSLog(@"captured audio (%f) seconds", vision.capturedAudioSeconds);
}

- (void)visionDidCaptureVideoSample:(PBJVision *)vision
{
//    NSLog(@"captured video (%f) seconds", vision.capturedVideoSeconds);
}

@end

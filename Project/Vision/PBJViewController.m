//
//  PBJViewController.m
//  Vision
//
//  Created by Patrick Piemonte on 7/23/13.
//  Copyright (c) 2013 Patrick Piemonte. All rights reserved.
//

#import "PBJViewController.h"
#import "PBJVision.h"
#import "PBJStrobeView.h"
#import "PBJVisionUtilities.h"
#import "ZXHVisionCameraTargetView.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <GLKit/GLKit.h>

@interface UIButton (ExtendedHit)

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;

@end

@implementation UIButton (ExtendedHit)

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
    UIButton *_onionButton;

    UIView *_previewView;
    AVCaptureVideoPreviewLayer *_previewLayer;
    GLKViewController *_effectsViewController;
    
    UILabel *_instructionLabel;
    
    UILongPressGestureRecognizer *_longPressGestureRecognizer;
    BOOL _recording;


    UITapGestureRecognizer *_tapGestureRecognizer;
    ZXHVisionCameraTargetView *_cameraTargetView;
    
    
    ALAssetsLibrary *_assetLibrary;
    __block NSDictionary *_currentVideo;
}

@end

@implementation PBJViewController

#pragma mark - init

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _assetLibrary = [[ALAssetsLibrary alloc] init];
        [self _setup];
    }
    return self;
}

- (void)dealloc
{
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    _longPressGestureRecognizer.delegate = nil;
}

- (void)_setup
{
    self.view.backgroundColor = [UIColor blackColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    CGFloat viewWidth = CGRectGetWidth(self.view.frame);
    
    // done button
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
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
    [self.view addSubview:_previewView];

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
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] init];
    _longPressGestureRecognizer.delegate = self;
    _longPressGestureRecognizer.minimumPressDuration = 0.15f;
    _longPressGestureRecognizer.allowableMovement = 10.0f;
    [_longPressGestureRecognizer addTarget:self action:@selector(_handleLongPressGestureRecognizer:)];
    
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTapGestureRecognizer:)];
    
    // gesture view to record
    UIView *gestureView = [[UIView alloc] initWithFrame:CGRectZero];
    CGRect gestureFrame = self.view.bounds;
    gestureFrame.origin = CGPointMake(0, 60.0f);
    gestureFrame.size.height -= 10.0f;
    gestureView.frame = gestureFrame;
    [self.view addSubview:gestureView];
    [gestureView addGestureRecognizer:_longPressGestureRecognizer];
    [gestureView addGestureRecognizer:_tapGestureRecognizer];
    
    // CameraTargetView
    _cameraTargetView = [[ZXHVisionCameraTargetView alloc]initWithFrame:CGRectMake(80, 165, 65, 65)];
    _cameraTargetView.backgroundColor = [UIColor clearColor];
    [gestureView addSubview:_cameraTargetView];
    [_cameraTargetView hideAnimated:NO];
    
    
    // flip button
    _flipButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_flipButton setImage:[UIImage imageNamed:@"capture_flip"] forState:UIControlStateNormal];
    _flipButton.frame = CGRectMake(15.0f, CGRectGetHeight(self.view.bounds) - 15.0f, 30.0f, 25.0f);
    [_flipButton addTarget:self action:@selector(_handleFlipButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_flipButton];
    
    // onion button
    _onionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_onionButton setImage:[UIImage imageNamed:@"capture_onion"] forState:UIControlStateNormal];
    [_onionButton setImage:[UIImage imageNamed:@"capture_onion_selected"] forState:UIControlStateSelected];
    _onionButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 25.0f - 15.0f, CGRectGetHeight(self.view.bounds) - 15.0f, 25.0f, 25.0f);
    [_onionButton addTarget:self action:@selector(_handleOnionSkinningButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_onionButton];
}

#pragma mark - view lifecycle

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    
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
        [_instructionLabel removeFromSuperview];
    }];
    [[PBJVision sharedInstance] startVideoCapture];
}

- (void)_pauseCapture
{
    [[PBJVision sharedInstance] pauseVideoCapture];
    _effectsViewController.view.hidden = !_onionButton.selected;
}

- (void)_resumeCapture
{
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
    [vision setCameraMode:PBJCameraModeVideo];
    [vision setCameraDevice:PBJCameraDeviceBack];
    [vision setCameraOrientation:PBJCameraOrientationPortrait];
    [vision setFocusMode:PBJFocusModeAutoFocus];
    [vision setVideoRenderingEnabled:YES];
}

#pragma mark - UIButton

- (void)_handleFlipButton:(UIButton *)button
{
    PBJVision *vision = [PBJVision sharedInstance];
    if (vision.cameraDevice == PBJCameraDeviceBack) {
        [vision setCameraDevice:PBJCameraDeviceFront];
    } else {
        [vision setCameraDevice:PBJCameraDeviceBack];
    }
}

- (void)_handleOnionSkinningButton:(UIButton *)button
{
    [_onionButton setSelected:!_onionButton.selected];
    if (_recording)
        _effectsViewController.view.hidden = !_onionButton.selected;
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

- (void)_handleTapGestureRecognizer:(UITapGestureRecognizer *)gestureRecognizer {
    PBJVision *vision = [PBJVision sharedInstance];
    
    CGPoint tapPoint = [gestureRecognizer locationInView:_previewView];
    _cameraTargetView.center = tapPoint;
    [_cameraTargetView showAnimated:YES];
    
    CGPoint adjustPoint = [PBJVisionUtilities convertToPointOfInterestFromViewCoordinates:tapPoint inFrame:_previewView.frame];
    
    
    
    [vision focusAtAdjustedPoint:adjustPoint];
}

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

#pragma mark - PBJVisionDelegate

- (void)visionSessionWillStart:(PBJVision *)vision
{
}

- (void)visionSessionDidStart:(PBJVision *)vision
{
}

- (void)visionSessionDidStop:(PBJVision *)vision
{
}

- (void)visionModeWillChange:(PBJVision *)vision
{
}

- (void)visionModeDidChange:(PBJVision *)vision
{
}

- (void)vision:(PBJVision *)vision cleanApertureDidChange:(CGRect)cleanAperture
{
}

- (void)visionWillStartFocus:(PBJVision *)vision
{
}

- (void)visionDidStopFocus:(PBJVision *)vision
{
    [_cameraTargetView hideAnimated:YES];
}

- (void)visionCameraViewDidBeginAdjustingExposure:(PBJVision *)vision {
    
}

- (void)visionCameraViewDidFinishAdjustingExposure:(PBJVision *)vision {
    [_cameraTargetView hideAnimated:YES];
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

@end

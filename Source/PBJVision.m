//
//  PBJVision.m
//
//  Created by Patrick Piemonte on 4/30/13.
//  Copyright (c) 2013. All rights reserved.
//

#import "PBJVision.h"
#import "PBJVisionUtilities.h"

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/UTCoreTypes.h>

#define LOG_VISION 0
#if !defined(NDEBUG) && LOG_VISION
#   define DLog(fmt, ...) NSLog((@"VISION: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

static uint64_t const PBJVisionRequiredMinimumDiskSpaceInBytes = 49999872; // ~ 47 MB
static CGFloat const PBJVisionThumbnailWidth = 160.0f;

// KVO contexts

static NSString * const PBJVisionFocusObserverContext = @"PBJVisionFocusObserverContext";
static NSString * const PBJVisionCaptureStillImageIsCapturingStillImageObserverContext = @"PBJVisionCaptureStillImageIsCapturingStillImageObserverContext";

// photo dictionary key definitions

NSString * const PBJVisionPhotoMetadataKey = @"PBJVisionPhotoMetadataKey";
NSString * const PBJVisionPhotoJPEGKey = @"PBJVisionPhotoJPEGKey";
NSString * const PBJVisionPhotoImageKey = @"PBJVisionPhotoImageKey";
NSString * const PBJVisionPhotoThumbnailKey = @"PBJVisionPhotoThumbnailKey";

// video dictionary key definitions

NSString * const PBJVisionVideoPathKey = @"PBJVisionVideoPathKey";
NSString * const PBJVisionVideoThumbnailKey = @"PBJVisionVideoThumbnailKey";

@interface PBJVision () <
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate>
{
    // AV

    AVCaptureSession *_captureSession;
    
    AVCaptureDevice *_captureDeviceFront;
    AVCaptureDevice *_captureDeviceBack;
    AVCaptureDevice *_captureDeviceAudio;
    
    AVCaptureDeviceInput *_captureDeviceInputFront;
    AVCaptureDeviceInput *_captureDeviceInputBack;
    AVCaptureDeviceInput *_captureDeviceInputAudio;

    AVCaptureStillImageOutput *_captureOutputPhoto;
    AVCaptureAudioDataOutput *_captureOutputAudio;
    AVCaptureVideoDataOutput *_captureOutputVideo;

	__block AVAssetWriter *_assetWriter;
	__block AVAssetWriterInput *_assetWriterAudioIn;
	__block AVAssetWriterInput *_assetWriterVideoIn;

    // vision core

    dispatch_queue_t _captureSessionDispatchQueue;
    dispatch_queue_t _captureVideoDispatchQueue;

    PBJCameraDevice _cameraDevice;
    PBJCameraMode _cameraMode;
    PBJCameraOrientation _cameraOrientation;

    AVCaptureDevice *_currentDevice;
    AVCaptureDeviceInput *_currentInput;
    AVCaptureOutput *_currentOutput;
    
    AVCaptureVideoPreviewLayer *_previewLayer;
    CGRect _cleanAperture;

    NSURL *_outputURL;
    
    CMTime _timeOffset;
    CMTime _audioTimestamp;
	CMTime _videoTimestamp;
    
    // flags
    struct {
        unsigned int previewRunning:1;
        unsigned int changingModes:1;
        unsigned int readyForAudio:1;
        unsigned int readyForVideo:1;
        unsigned int recording:1;
        unsigned int isPaused:1;
        unsigned int interrupted:1;
        unsigned int videoWritten:1;
    } __block _flags;
}

@end

@implementation PBJVision

@synthesize delegate = _delegate;
@synthesize previewLayer = _previewLayer;
@synthesize cleanAperture = _cleanAperture;
@synthesize cameraDevice = _cameraDevice;
@synthesize cameraMode = _cameraMode;
@synthesize cameraOrientation = _cameraOrientation;
@synthesize focusMode = _focusMode;

#pragma mark - singleton

+ (PBJVision *)sharedInstance
{
    static PBJVision *singleton = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{
        singleton = [[PBJVision alloc] init];
    });
    return singleton;
}

#pragma mark - getters/setters

- (BOOL)isActive
{
    return ([_captureSession isRunning]);
}

- (void)_setOrientationForConnection:(AVCaptureConnection *)connection
{
    if (!connection)
        return;

    AVCaptureVideoOrientation orientation = AVCaptureVideoOrientationPortrait;
    switch (_cameraOrientation) {
        case PBJCameraOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case PBJCameraOrientationLandscapeRight:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case PBJCameraOrientationLandscapeLeft:
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        default:
        case PBJCameraOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
    }

    [connection setVideoOrientation:orientation];
}

- (void)_setCameraMode:(PBJCameraMode)cameraMode cameraDevice:(PBJCameraDevice)cameraDevice
{
    BOOL changeDevice = (_cameraDevice != cameraDevice);
    BOOL changeMode = (_cameraMode != cameraMode);
    
    DLog(@"change device %d mode %d", changeDevice, changeMode);
    
    if (!changeMode && !changeDevice)
        return;
    
    if ([_delegate respondsToSelector:@selector(visionModeWillChange:)])
        [_delegate visionModeWillChange:self];
    
    _flags.changingModes = YES;
    
    _cameraDevice = cameraDevice;
    _cameraMode = cameraMode;
    
    // since there is no session in progress, set and bail
    if (!_captureSession) {
        _flags.changingModes = NO;
            
        if ([_delegate respondsToSelector:@selector(visionModeDidChange:)])
            [_delegate visionModeDidChange:self];
        
        return;
    }
    
    [self _enqueueBlockInCaptureSessionQueue:^{
        [self _setupSession];
        [self _enqueueBlockOnMainQueue:^{
            _flags.changingModes = NO;
            
            if ([_delegate respondsToSelector:@selector(visionModeDidChange:)])
                [_delegate visionModeDidChange:self];
        }];
    }];
}

- (void)setCameraDevice:(PBJCameraDevice)cameraDevice
{
    [self _setCameraMode:_cameraMode cameraDevice:cameraDevice];
}

- (void)setCameraMode:(PBJCameraMode)cameraMode
{
    [self _setCameraMode:cameraMode cameraDevice:_cameraDevice];
}

- (BOOL)isRecording
{
    __block BOOL isRecording = NO;
    [self _enqueueBlockInCaptureVideoQueue:^{
        isRecording = (BOOL)_flags.recording;
    }];
    return isRecording;
}

#pragma mark - init

- (id)init
{
    self = [super init];
    if (self) {
        _captureSessionDispatchQueue = dispatch_queue_create("PBJVisionSession", DISPATCH_QUEUE_SERIAL); // protects session
        _captureVideoDispatchQueue = dispatch_queue_create("PBJVisionVideo", DISPATCH_QUEUE_SERIAL); // protects capture
        _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForeground:) name:@"UIApplicationWillEnterForegroundNotification" object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackground:) name:@"UIApplicationDidEnterBackgroundNotification" object:[UIApplication sharedApplication]];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _delegate = nil;
}

#pragma mark - queue helper methods

typedef void (^PBJVisionBlock)();

- (void)_enqueueBlockInCaptureSessionQueue:(PBJVisionBlock)block {
    dispatch_async(_captureSessionDispatchQueue, ^{
        block();
    });
}

- (void)_enqueueBlockInCaptureVideoQueue:(PBJVisionBlock)block {
    dispatch_async(_captureVideoDispatchQueue, ^{
        block();
    });
}

- (void)_enqueueBlockOnMainQueue:(PBJVisionBlock)block {
    dispatch_async(dispatch_get_main_queue(), ^{
        block();
    });
}

- (void)_executeBlockOnMainQueue:(PBJVisionBlock)block {
    dispatch_sync(dispatch_get_main_queue(), ^{
        block();
    });
}

#pragma mark - camera

- (void)_setupCamera
{
    if (_captureSession)
        return;

    _captureSession = [[AVCaptureSession alloc] init];
    
    _captureDeviceFront = [PBJVisionUtilities captureDeviceForPosition:AVCaptureDevicePositionFront];
    _captureDeviceBack = [PBJVisionUtilities captureDeviceForPosition:AVCaptureDevicePositionBack];

    NSError *error = nil;
    _captureDeviceInputFront = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceFront error:&error];
    if (error) {
        DLog(@"error setting up front camera input (%@)", error);
        error = nil;
    }
    
    _captureDeviceInputBack = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceBack error:&error];
    if (error) {
        DLog(@"error setting up back camera input (%@)", error);
        error = nil;
    }
    
    _captureDeviceAudio = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    _captureDeviceInputAudio = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceAudio error:&error];
    if (error) {
        DLog(@"error setting up audio input (%@)", error);
    }
    
    _captureOutputPhoto = [[AVCaptureStillImageOutput alloc] init];
    _captureOutputAudio = [[AVCaptureAudioDataOutput alloc] init];
    _captureOutputVideo = [[AVCaptureVideoDataOutput alloc] init];
    
    [_captureOutputAudio setSampleBufferDelegate:self queue:_captureVideoDispatchQueue];
    [_captureOutputVideo setSampleBufferDelegate:self queue:_captureVideoDispatchQueue];
    
    // add notification observers
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    // session notifications
    [notificationCenter addObserver:self selector:@selector(_sessionRuntimeErrored:) name:AVCaptureSessionRuntimeErrorNotification object:_captureSession];
    [notificationCenter addObserver:self selector:@selector(_sessionStarted:) name:AVCaptureSessionDidStartRunningNotification object:_captureSession];
    [notificationCenter addObserver:self selector:@selector(_sessionStopped:) name:AVCaptureSessionDidStopRunningNotification object:_captureSession];
    [notificationCenter addObserver:self selector:@selector(_sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:_captureSession];
    [notificationCenter addObserver:self selector:@selector(_sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:_captureSession];
    
    // capture input notifications
    [notificationCenter addObserver:self selector:@selector(_inputPortFormatDescriptionDidChange:) name:AVCaptureInputPortFormatDescriptionDidChangeNotification object:nil];
    
    // capture device notifications
    [notificationCenter addObserver:self selector:@selector(_deviceSubjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
    
    // KVO is only used to monitor focus and capture events
    [_captureOutputPhoto addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:(__bridge void *)(PBJVisionCaptureStillImageIsCapturingStillImageObserverContext)];
    
    DLog(@"camera setup");
}

- (void)_destroyCamera
{
    if (!_captureSession)
        return;
    
    // remove notification observers (we don't want to just 'remove all' because we're also observing background notifications
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        
    // session notifications
    [notificationCenter removeObserver:self name:AVCaptureSessionRuntimeErrorNotification object:_captureSession];
    [notificationCenter removeObserver:self name:AVCaptureSessionDidStartRunningNotification object:_captureSession];
    [notificationCenter removeObserver:self name:AVCaptureSessionDidStopRunningNotification object:_captureSession];
    [notificationCenter removeObserver:self name:AVCaptureSessionWasInterruptedNotification object:_captureSession];
    [notificationCenter removeObserver:self name:AVCaptureSessionInterruptionEndedNotification object:_captureSession];
    
    // capture input notifications
    [notificationCenter removeObserver:self name:AVCaptureInputPortFormatDescriptionDidChangeNotification object:nil];
    
    // capture device notifications
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];

    // only KVO use
    [_captureOutputPhoto removeObserver:self forKeyPath:@"capturingStillImage"];
    [_currentDevice removeObserver:self forKeyPath:@"adjustingFocus"];

    _captureOutputPhoto = nil;
    _captureOutputAudio = nil;
    _captureOutputVideo = nil;
    
    _captureDeviceAudio = nil;
    _captureDeviceInputAudio = nil;
    
    _captureDeviceInputFront = nil;
    _captureDeviceInputBack = nil;

    _captureDeviceFront = nil;
    _captureDeviceBack = nil;

    _captureSession = nil;
    
    _currentDevice = nil;
    _currentInput = nil;
    _currentOutput = nil;
    
    _previewLayer.session = nil;
    
    DLog(@"camera destroyed");
}

#pragma mark - AVCaptureSession

- (BOOL)_canSessionCaptureWithOutput:(AVCaptureOutput *)captureOutput
{
    BOOL sessionContainsOutput = [[_captureSession outputs] containsObject:captureOutput];
    BOOL outputHasConnection = ([captureOutput connectionWithMediaType:AVMediaTypeVideo] != nil);
    return (sessionContainsOutput && outputHasConnection);
}

- (void)_setupSession
{
    if (!_captureSession) {
        DLog(@"error, no session running to setup");
        return;
    }
    
    BOOL shouldSwitchDevice = (_currentDevice == nil) ||
                              ((_currentDevice == _captureDeviceFront) && (_cameraDevice != PBJCameraDeviceFront)) ||
                              ((_currentDevice == _captureDeviceBack) && (_cameraDevice != PBJCameraDeviceBack));
    
    BOOL shouldSwitchMode = (_currentOutput == nil) ||
                            ((_currentOutput == _captureOutputPhoto) && (_cameraMode != PBJCameraModePhoto)) ||
                            ((_currentOutput == _captureOutputVideo) && (_cameraMode != PBJCameraModeVideo));

    DLog(@"switchDevice %d switchMode %d", shouldSwitchDevice, shouldSwitchMode);

    if (!shouldSwitchDevice && !shouldSwitchMode)
        return;
    
    AVCaptureDeviceInput *newDeviceInput = nil;
    AVCaptureOutput *newCaptureOutput = nil;
    AVCaptureDevice *newCaptureDevice = nil;
    
    [_captureSession beginConfiguration];
    [_captureSession setSessionPreset:AVCaptureSessionPresetMedium];
    
    if (shouldSwitchDevice) {
        switch (_cameraDevice) {
          case PBJCameraDeviceFront:
          {
            [_captureSession removeInput:_captureDeviceInputBack];
            if ([_captureSession canAddInput:_captureDeviceInputFront]) {
                [_captureSession addInput:_captureDeviceInputFront];
                newDeviceInput = _captureDeviceInputFront;
                newCaptureDevice = _captureDeviceFront;
            }
            break;
          }
          case PBJCameraDeviceBack:
          {
            [_captureSession removeInput:_captureDeviceInputFront];
            if ([_captureSession canAddInput:_captureDeviceInputBack]) {
                [_captureSession addInput:_captureDeviceInputBack];
                newDeviceInput = _captureDeviceInputBack;
                newCaptureDevice = _captureDeviceBack;
            }
            break;
          }
          default:
            break;
        }
    
    } // shouldSwitchDevice
    
    if (shouldSwitchMode) {
        [_captureSession removeInput:_captureDeviceInputAudio];
        [_captureSession removeOutput:_captureOutputAudio];
        [_captureSession removeOutput:_captureOutputVideo];
        [_captureSession removeOutput:_captureOutputPhoto];
        
        switch (_cameraMode) {
            case PBJCameraModeVideo:
            {
                // audio input
                if ([_captureSession canAddInput:_captureDeviceInputAudio]) {
                    [_captureSession addInput:_captureDeviceInputAudio];
                }
                // audio output
                if ([_captureSession canAddOutput:_captureOutputAudio]) {
                    [_captureSession addOutput:_captureOutputAudio];
                }
                // vidja output
                if ([_captureSession canAddOutput:_captureOutputVideo]) {
                    [_captureSession addOutput:_captureOutputVideo];
                    newCaptureOutput = _captureOutputVideo;
                }
                break;
            }
            case PBJCameraModePhoto:
            {
                // photo output
                if ([_captureSession canAddOutput:_captureOutputPhoto]) {
                    [_captureSession addOutput:_captureOutputPhoto];
                    newCaptureOutput = _captureOutputPhoto;
                }
                break;
            }
            default:
                break;
        }
        
    } // shouldSwitchMode
    
    if (!newCaptureDevice)
        newCaptureDevice = _currentDevice;

    if (!newCaptureOutput)
        newCaptureOutput = _currentOutput;

    NSString *sessionPreset = [_captureSession sessionPreset];
    if (newCaptureOutput == _captureOutputVideo) {
        
        AVCaptureConnection *videoConnection = [_captureOutputVideo connectionWithMediaType:AVMediaTypeVideo];
        
        [self _setOrientationForConnection:videoConnection];
        
        // setup stabilization, if available
        if ([videoConnection isVideoStabilizationSupported])
            [videoConnection setEnablesVideoStabilizationWhenAvailable:YES];
                
        // setup pixel format
        NSDictionary *videoSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                       [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange], (id)kCVPixelBufferPixelFormatTypeKey,
                                        nil];
        [_captureOutputVideo setVideoSettings:videoSettings];
        
        // discard late frames
        [_captureOutputVideo setAlwaysDiscardsLateVideoFrames:NO];
        
        // setup video to use 640 x 480 for the hightest quality touch-to-record
        if ( [_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480] )
            sessionPreset = AVCaptureSessionPreset640x480;
        
        // set the framerate and preset
        CMTime frameDuration = CMTimeMake( 1, 30 );
        if ( videoConnection.supportsVideoMinFrameDuration )
            videoConnection.videoMinFrameDuration = frameDuration; // needs to be applied to session in iOS 7
        if ( videoConnection.supportsVideoMaxFrameDuration )
            videoConnection.videoMaxFrameDuration = frameDuration; // needs to be applied to session in iOS 7
        
    } else if (newCaptureOutput == _captureOutputPhoto) {
    
        // specify photo presets
        sessionPreset = AVCaptureSessionPresetPhoto;
    
        NSDictionary *photoSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        AVVideoCodecJPEG, AVVideoCodecKey,
                                        nil];
        [_captureOutputPhoto setOutputSettings:photoSettings];
        
    }

    // apply presets
    if ([_captureSession canSetSessionPreset:sessionPreset]) {
        [_captureSession setSessionPreset:sessionPreset];
    }
    
    // enable low light boost
    if ([newCaptureDevice isLowLightBoostSupported]) {
        NSError *error = nil;
        if ([newCaptureDevice lockForConfiguration:&error]) {
            BOOL enableLowLightBoost = (newCaptureOutput == _captureOutputPhoto);
            [newCaptureDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:enableLowLightBoost];
            [newCaptureDevice unlockForConfiguration];
        } else {
            DLog(@"error locking device for low light boost (%@)", error);
        }
    }

    // KVO
    if (newCaptureDevice) {
        [_currentDevice removeObserver:self forKeyPath:@"adjustingFocus"];
        _currentDevice = newCaptureDevice;
        [_currentDevice addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFocusObserverContext];
    }
    
    if (newDeviceInput)
        _currentInput = newDeviceInput;
    
    if (newCaptureOutput)
        _currentOutput = newCaptureOutput;

    [_captureSession commitConfiguration];
    
    DLog(@"capture session setup");
}

#pragma mark - preview

- (void)startPreview
{
    [self _enqueueBlockInCaptureSessionQueue:^{
        if (!_captureSession) {
            [self _setupCamera];
            [self _setupSession];
        }
    
        if (_previewLayer && _previewLayer.session != _captureSession) {
            _previewLayer.session = _captureSession;
        }
        
        if (![_captureSession isRunning]) {
            [_captureSession startRunning];
            
            [self _enqueueBlockOnMainQueue:^{
                if ([_delegate respondsToSelector:@selector(visionSessionDidStart:)]) {
                    [_delegate visionSessionDidStart:self];
                }
            }];
            DLog(@"capture session running");
        }
        _flags.previewRunning = YES;
    }];
}

- (void)stopPreview
{    
    [self _enqueueBlockInCaptureSessionQueue:^{
        if (!_flags.previewRunning)
            return;

        if (_previewLayer)
            _previewLayer.connection.enabled = YES;

        [_captureSession stopRunning];

        [self _executeBlockOnMainQueue:^{
            if ([_delegate respondsToSelector:@selector(visionSessionDidStop:)]) {
                [_delegate visionSessionDidStop:self];
            }
        }];
        DLog(@"capture session stopped");
        _flags.previewRunning = NO;
    }];
}

- (void)unfreezePreview
{
    if (_previewLayer)
        _previewLayer.connection.enabled = YES;
}

#pragma mark - focus, exposure, white balance

- (void)_focusStarted
{
//    DLog(@"focus started");
    if ([_delegate respondsToSelector:@selector(visionWillStartFocus:)])
        [_delegate visionWillStartFocus:self];
}

- (void)_focusEnded
{
    if ([_delegate respondsToSelector:@selector(visionDidStopFocus:)])
        [_delegate visionDidStopFocus:self];
//    DLog(@"focus ended");
}

- (void)_focus
{
    if ([_currentDevice isAdjustingFocus] || [_currentDevice isAdjustingExposure])
        return;

    // only notify clients when focus is triggered from an event
    if ([_delegate respondsToSelector:@selector(visionWillStartFocus:)])
        [_delegate visionWillStartFocus:self];

    CGPoint focusPoint = CGPointMake(0.5f, 0.5f);
    [self focusAtAdjustedPoint:focusPoint];
}

// TODO: should add in  exposure and white balance locks for completeness one day
- (void)_setFocusLocked:(BOOL)focusLocked
{
    NSError *error = nil;
    if (_currentDevice && [_currentDevice lockForConfiguration:&error]) {
    
        if (focusLocked && [_currentDevice isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [_currentDevice setFocusMode:AVCaptureFocusModeLocked];
        } else if ([_currentDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [_currentDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        
        [_currentDevice setSubjectAreaChangeMonitoringEnabled:focusLocked];
            
        [_currentDevice unlockForConfiguration];
        
    } else if (error) {
        DLog(@"error locking device for focus adjustment (%@)", error);
    }
}

- (void)focusAtAdjustedPoint:(CGPoint)adjustedPoint
{
    if ([_currentDevice isAdjustingFocus] || [_currentDevice isAdjustingExposure])
        return;

    NSError *error = nil;
    if ([_currentDevice lockForConfiguration:&error]) {
    
        BOOL isFocusAtPointSupported = [_currentDevice isFocusPointOfInterestSupported];
        BOOL isExposureAtPointSupported = [_currentDevice isExposurePointOfInterestSupported];
        BOOL isWhiteBalanceModeSupported = [_currentDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    
        if (isFocusAtPointSupported && [_currentDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [_currentDevice setFocusPointOfInterest:adjustedPoint];
            [_currentDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        
        if (isExposureAtPointSupported && [_currentDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [_currentDevice setExposurePointOfInterest:adjustedPoint];
            [_currentDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        
        if (isWhiteBalanceModeSupported) {
            [_currentDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        }
        
        [_currentDevice unlockForConfiguration];
        
    } else if (error) {
        DLog(@"error locking device for focus adjustment (%@)", error);
    }
}

#pragma mark - photo

- (BOOL)canCapturePhoto
{
    BOOL isDiskSpaceAvailable = [PBJVisionUtilities availableDiskSpaceInBytes] > PBJVisionRequiredMinimumDiskSpaceInBytes;
    return [self isActive] && !_flags.changingModes && isDiskSpaceAvailable;
}

- (UIImage *)_imageFromJPEGData:(NSData *)jpegData
{
    CGImageRef jpegCGImage = NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)jpegData);
    
    if (provider) {
        CGImageSourceRef imageSource = CGImageSourceCreateWithDataProvider(provider, NULL);
        if (imageSource) {
            if (CGImageSourceGetCount(imageSource) > 0) {
                jpegCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
            }
            CFRelease(imageSource);
        }
        CGDataProviderRelease(provider);
    }
    
    UIImage *image = nil;
    if (jpegCGImage) {
        image = [[UIImage alloc] initWithCGImage:jpegCGImage];
        CGImageRelease(jpegCGImage);
    }
    return image;
}

- (UIImage *)_thumbnailJPEGData:(NSData *)jpegData
{
    CGImageRef thumbnailCGImage = NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)jpegData);
    
    if (provider) {
        CGImageSourceRef imageSource = CGImageSourceCreateWithDataProvider(provider, NULL);
        if (imageSource) {
            if (CGImageSourceGetCount(imageSource) > 0) {
                NSMutableDictionary *options = [[NSMutableDictionary alloc] initWithCapacity:3];
                [options setObject:[NSNumber numberWithBool:YES] forKey:(id)kCGImageSourceCreateThumbnailFromImageAlways];
                [options setObject:[NSNumber numberWithFloat:PBJVisionThumbnailWidth] forKey:(id)kCGImageSourceThumbnailMaxPixelSize];
                [options setObject:[NSNumber numberWithBool:NO] forKey:(id)kCGImageSourceCreateThumbnailWithTransform];
                thumbnailCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
            }
            CFRelease(imageSource);
        }
        CGDataProviderRelease(provider);
    }
    
    UIImage *thumbnail = nil;
    if (thumbnailCGImage) {
        thumbnail = [[UIImage alloc] initWithCGImage:thumbnailCGImage];
        CGImageRelease(thumbnailCGImage);
    }
    return thumbnail;
}

- (void)_willCapturePhoto
{
    DLog(@"will capture photo");
    if ([_delegate respondsToSelector:@selector(visionWillCapturePhoto:)])
        [_delegate visionWillCapturePhoto:self];
    
    // freeze preview
    _previewLayer.connection.enabled = NO;
}

- (void)_didCapturePhoto
{
    if ([_delegate respondsToSelector:@selector(visionDidCapturePhoto:)])
        [_delegate visionDidCapturePhoto:self];
    DLog(@"did capture photo");
}

- (void)capturePhoto
{
    if (![self _canSessionCaptureWithOutput:_currentOutput]) {
        DLog(@"session is not setup properly for capture");
        return;
    }

    AVCaptureConnection *connection = [_currentOutput connectionWithMediaType:AVMediaTypeVideo];
    
    [self _setOrientationForConnection:connection];
    
    [_captureOutputPhoto captureStillImageAsynchronouslyFromConnection:connection completionHandler:
    ^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        
        if (!imageDataSampleBuffer) {
            DLog(@"failed to obtain image data sample buffer");
            // TODO: return delegate error
            return;
        }
    
        if (error) {
            if ([_delegate respondsToSelector:@selector(vision:capturedPhoto:error:)]) {
                [_delegate vision:self capturedPhoto:nil error:error];
            }
            return;
        }
    
        // TODO: return delegate on error
        NSMutableDictionary *photoDict = [[NSMutableDictionary alloc] init];
        NSDictionary *metadata = nil;

        // add photo metadata (ie EXIF: Aperture, Brightness, Exposure, FocalLength, etc)
        metadata = (__bridge NSDictionary *)CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
        if (metadata) {
            [photoDict setObject:metadata forKey:PBJVisionPhotoMetadataKey];
            CFRelease((__bridge CFTypeRef)(metadata));
        } else {
            DLog(@"failed to generate metadata for photo");
        }
        
        // add JPEG and image data
        NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        if (jpegData) {
            // add JPEG
            [photoDict setObject:jpegData forKey:PBJVisionPhotoJPEGKey];
            
            // add image
            UIImage *image = [self _imageFromJPEGData:jpegData];
            if (image) {
                [photoDict setObject:image forKey:PBJVisionPhotoImageKey];
            } else {
                DLog(@"failed to create image from JPEG");
            }
            
            // add thumbnail
            UIImage *thumbnail = [self _thumbnailJPEGData:jpegData];
            if (thumbnail) {
                [photoDict setObject:thumbnail forKey:PBJVisionPhotoThumbnailKey];
            } else {
                DLog(@"failed to create a thumnbail");
            }
            
        } else {
            DLog(@"failed to create jpeg still image data");
        }
        
        if ([_delegate respondsToSelector:@selector(vision:capturedPhoto:error:)]) {
            [_delegate vision:self capturedPhoto:photoDict error:error];
        }
        
        // run a post shot focus
        [self performSelector:@selector(_focus) withObject:nil afterDelay:0.5f];
    }];
}

#pragma mark - video

- (BOOL)supportsVideoCapture
{
    return ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0);
}

- (BOOL)canCaptureVideo
{
    BOOL isDiskSpaceAvailable = [PBJVisionUtilities availableDiskSpaceInBytes] > PBJVisionRequiredMinimumDiskSpaceInBytes;
    return [self supportsVideoCapture] && [self isActive] && !_flags.changingModes && isDiskSpaceAvailable;
}

- (void)startVideoCapture
{
    if (![self _canSessionCaptureWithOutput:_currentOutput]) {
        DLog(@"session is not setup properly for capture");
        return;
    }
    
    DLog(@"starting video capture");
        
    [self _enqueueBlockInCaptureVideoQueue:^{

        if (_flags.recording || _flags.isPaused)
            return;

        NSString *outputPath = [NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"video.mp4"];
        _outputURL = [NSURL fileURLWithPath:outputPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:outputPath error:&error]) {
                DLog(@"could not setup an output file");
                _outputURL = nil;
                return;
            }
        }

        if (!outputPath || [outputPath length] == 0)
            return;

        AVCaptureConnection *videoConnection = [_captureOutputVideo connectionWithMediaType:AVMediaTypeVideo];
        [self _setOrientationForConnection:videoConnection];

        _timeOffset = kCMTimeZero;
        _audioTimestamp = kCMTimeZero;
        _videoTimestamp = kCMTimeZero;
        
        _flags.recording = YES;
        _flags.isPaused = NO;
        _flags.interrupted = NO;
        _flags.readyForAudio = NO;
        _flags.readyForVideo = NO;
        _flags.videoWritten = NO;

        NSError *error = nil;
        _assetWriter = [[AVAssetWriter alloc] initWithURL:_outputURL fileType:(NSString *)kUTTypeQuickTimeMovie error:&error];
        if (error) {
            DLog(@"error setting up the asset writer (%@)", error);
            _assetWriter = nil;
            return;
        }
        
        // TODO: create metadata and add to _assetWriter.metadata
        
        [self _enqueueBlockOnMainQueue:^{                
            if ([_delegate respondsToSelector:@selector(visionDidStartVideoCapture:)])
                [_delegate visionDidStartVideoCapture:self];
        }];
    }];
}

- (void)pauseVideoCapture
{
    [self _enqueueBlockInCaptureVideoQueue:^{
        if (!_flags.recording)
            return;

        if (!_assetWriter) {
            DLog(@"assetWriter unavailable to stop");
            return;
        }

        DLog(@"pausing video capture");

        _flags.isPaused = YES;
        _flags.interrupted = YES;
        
        [self _enqueueBlockOnMainQueue:^{
            if ([_delegate respondsToSelector:@selector(visionDidPauseVideoCapture:)])
                [_delegate visionDidPauseVideoCapture:self];
        }];
    }];    
}

- (void)resumeVideoCapture
{
    [self _enqueueBlockInCaptureVideoQueue:^{
        if (!_flags.recording || !_flags.isPaused)
            return;
 
        if (!_assetWriter) {
            DLog(@"assetWriter unavailable to resume");
            return;
        }
 
        DLog(@"resuming video capture");
       
        _flags.isPaused = NO;

        [self _enqueueBlockOnMainQueue:^{
            if ([_delegate respondsToSelector:@selector(visionDidResumeVideoCapture:)])
                [_delegate visionDidResumeVideoCapture:self];
        }];
    }];    
}

- (void)endVideoCapture
{    
    DLog(@"ending video capture");
    
    [self _enqueueBlockInCaptureVideoQueue:^{
        if (!_flags.recording)
            return;
        
        if (!_assetWriter) {
            DLog(@"assetWriter unavailable to end");
            return;
        }

        if (_assetWriter.status == AVAssetWriterStatusUnknown) {
            DLog(@"asset writer is in an unknown state, wasn't recording");
            return;
        }
        
        _flags.recording = NO;
        _flags.isPaused = NO;
        
        void (^finishWritingCompletionHandler)(void) = ^{
            _timeOffset = kCMTimeZero;
            _audioTimestamp = kCMTimeZero;
            _videoTimestamp = kCMTimeZero;
            _flags.interrupted = NO;
            _flags.readyForAudio = NO;
            _flags.readyForVideo = NO;

            [self _enqueueBlockOnMainQueue:^{
                NSMutableDictionary *videoDict = [[NSMutableDictionary alloc] init];
                [videoDict setObject:[_outputURL path] forKey:PBJVisionVideoPathKey];

                NSError *error = [_assetWriter error];
                if ([_delegate respondsToSelector:@selector(vision:capturedVideo:error:)]) {
                    [_delegate vision:self capturedVideo:videoDict error:error];
                }
            }];
            
            _assetWriterAudioIn = nil;
            _assetWriterVideoIn = nil;
        };
        [_assetWriter finishWritingWithCompletionHandler:finishWritingCompletionHandler];
    }];
}

- (BOOL)_setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription
{
	const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormatDescription);
    if (!asbd) {
        DLog(@"audio stream description used with non-audio format description");
        return NO;
    }
    
	unsigned int channels = asbd->mChannelsPerFrame;
    double sampleRate = asbd->mSampleRate;
    int bitRate = 64000;

    DLog(@"audio stream setup, channels (%d) sampleRate (%f)", channels, sampleRate);
    
    size_t aclSize = 0;
	const AudioChannelLayout *currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(currentFormatDescription, &aclSize);
	NSData *currentChannelLayoutData = ( currentChannelLayout && aclSize > 0 ) ? [NSData dataWithBytes:currentChannelLayout length:aclSize] : [NSData data];
    
    NSDictionary *audioCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
                                              [NSNumber numberWithUnsignedInt:channels], AVNumberOfChannelsKey,
                                              [NSNumber numberWithDouble:sampleRate], AVSampleRateKey,
                                              [NSNumber numberWithInt:bitRate], AVEncoderBitRateKey,
                                              currentChannelLayoutData, AVChannelLayoutKey, nil];

	if ([_assetWriter canApplyOutputSettings:audioCompressionSettings forMediaType:AVMediaTypeAudio]) {
		_assetWriterAudioIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioCompressionSettings];
		_assetWriterAudioIn.expectsMediaDataInRealTime = YES;
        DLog(@"prepared audio-in with compression settings sampleRate (%f) channels (%d) bitRate (%d)", sampleRate, channels, bitRate);
		if ([_assetWriter canAddInput:_assetWriterAudioIn]) {
			[_assetWriter addInput:_assetWriterAudioIn];
		} else {
			DLog(@"couldn't add asset writer audio input");
            return NO;
		}
	} else {
		DLog(@"couldn't apply audio output settings");
        return NO;
	}
    
    return YES;

}

- (BOOL)_setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription
{
	CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
    
    // lower the bitRate, higher the compression, lets compress for 480 x 360 even though we record at 640 x 480
    // 87500, good for 480 x 360
    // 437500, good for 640 x 480
	float bitRate = 87500.0f * 8.0f;
	NSInteger frameInterval = 30;
    
    NSDictionary *compressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithFloat:bitRate], AVVideoAverageBitRateKey,
                                        [NSNumber numberWithInteger:frameInterval], AVVideoMaxKeyFrameIntervalKey,
                                        nil];
    
	NSDictionary *videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											  AVVideoCodecH264, AVVideoCodecKey,
                                              AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
											  [NSNumber numberWithInteger:dimensions.width], AVVideoWidthKey,
											  [NSNumber numberWithInteger:dimensions.width], AVVideoHeightKey, // square format
											  compressionSettings, AVVideoCompressionPropertiesKey,
											  nil];
    
	if ([_assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) {
    
		_assetWriterVideoIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
		_assetWriterVideoIn.expectsMediaDataInRealTime = YES;
		_assetWriterVideoIn.transform = CGAffineTransformIdentity;
        DLog(@"prepared video-in with compression settings bps (%f) frameInterval (%d)", bitRate, frameInterval);
		if ([_assetWriter canAddInput:_assetWriterVideoIn]) {
			[_assetWriter addInput:_assetWriterVideoIn];
		} else {
			DLog(@"couldn't add asset writer video input");
            return NO;
		}
        
	} else {
    
		DLog(@"couldn't apply video output settings");
        return NO;
        
	}
    
    return YES;
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate

- (void)_writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
	if ( _assetWriter.status == AVAssetWriterStatusUnknown ) {
    
        if ([_assetWriter startWriting]) {
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
			[_assetWriter startSessionAtSourceTime:startTime];
            DLog(@"asset writer started writing with status (%d)", _assetWriter.status);
		} else {
			DLog(@"asset writer error when starting to write (%@)", [_assetWriter error]);
		}
        
	}
    
    if ( _assetWriter.status == AVAssetWriterStatusFailed ) {
        DLog(@"asset writer failure, (%@)", _assetWriter.error.localizedDescription);
        return;
    }
	
	if ( _assetWriter.status == AVAssetWriterStatusWriting ) {
		
		if (mediaType == AVMediaTypeVideo) {
			if (_assetWriterVideoIn.readyForMoreMediaData) {
				if (![_assetWriterVideoIn appendSampleBuffer:sampleBuffer]) {
					DLog(@"asset writer error appending video (%@)", [_assetWriter error]);
				}
			}
		} else if (mediaType == AVMediaTypeAudio) {
			if (_assetWriterAudioIn.readyForMoreMediaData) {
				if (![_assetWriterAudioIn appendSampleBuffer:sampleBuffer]) {
					DLog(@"asset writer error appending audio (%@)", [_assetWriter error]);
				}
			}
		}
        
	}
    
}

- (CMSampleBufferRef)_createOffsetSampleBuffer:(CMSampleBufferRef)sampleBuffer withTimeOffset:(CMTime)timeOffset
{
    CMItemCount itemCount;
    
    OSStatus status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, NULL, &itemCount);
    if (status) {
        DLog(@"couldn't determine the timing info count");
        return NULL;
    }
    
    CMSampleTimingInfo *timingInfo = (CMSampleTimingInfo *)malloc(sizeof(CMSampleTimingInfo) * (unsigned long)itemCount);
    if (!timingInfo) {
        DLog(@"couldn't allocate timing info");
        return NULL;
    }
    
    status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, itemCount, timingInfo, &itemCount);
    if (status) {
        free(timingInfo);
        timingInfo = NULL;
        DLog(@"failure getting sample timing info array");
        return NULL;
    }
    
    for (CMItemCount i = 0; i < itemCount; i++) {
        timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, timeOffset);
        timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, timeOffset);
    }
    
    CMSampleBufferRef outputSampleBuffer;
    CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, itemCount, timingInfo, &outputSampleBuffer);
    
    if (timingInfo) {
        free(timingInfo);
        timingInfo = NULL;
    }
    
    return outputSampleBuffer;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // TODO: save the last frame for onion skinning

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
	CFRetain(sampleBuffer);
	CFRetain(formatDescription);
    
    [self _enqueueBlockInCaptureVideoQueue:^{
        if (!CMSampleBufferDataIsReady(sampleBuffer)) {
            DLog(@"sample buffer data is not ready");
            CFRelease(sampleBuffer);
            CFRelease(formatDescription);
            return;
        }
    
        if (!_flags.recording || _flags.isPaused) {
            CFRelease(sampleBuffer);
            CFRelease(formatDescription);
            return;
        }

        if (!_assetWriter) {
            CFRelease(sampleBuffer);
            CFRelease(formatDescription);
            return;
        }
     
        BOOL isAudio = (connection == [_captureOutputAudio connectionWithMediaType:AVMediaTypeAudio]);
        BOOL isVideo = (connection == [_captureOutputVideo connectionWithMediaType:AVMediaTypeVideo]);
        BOOL wasReadyToRecord = (_flags.readyForAudio && _flags.readyForVideo);

        if (isAudio && !_flags.readyForAudio) {
            _flags.readyForAudio = (unsigned int)[self _setupAssetWriterAudioInput:formatDescription];
            DLog(@"ready for audio (%d)", _flags.readyForAudio);
        }

        if (isVideo && !_flags.readyForVideo) {
            _flags.readyForVideo = (unsigned int)[self _setupAssetWriterVideoInput:formatDescription];
            DLog(@"ready for video (%d)", _flags.readyForVideo);
        }

        BOOL isReadyToRecord = (_flags.readyForAudio && _flags.readyForVideo);

        // calculate the length of the interruption
        if (_flags.interrupted && isAudio) {
            _flags.interrupted = NO;

            CMTime time = isVideo ? _videoTimestamp : _audioTimestamp;
            // calculate the appropriate time offset
            if (CMTIME_IS_VALID(time)) {
                CMTime pTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                if (CMTIME_IS_VALID(_timeOffset)) {
                    pTimestamp = CMTimeSubtract(pTimestamp, _timeOffset);
                }
                
                CMTime offset = CMTimeSubtract(pTimestamp, _audioTimestamp);
                _timeOffset = (_timeOffset.value == 0) ? offset : CMTimeAdd(_timeOffset, offset);
                DLog(@"new calculated offset %f valid (%d)", CMTimeGetSeconds(_timeOffset), CMTIME_IS_VALID(_timeOffset));
            } else {
                DLog(@"invalid audio timestamp, no offset update");
            }
            
            _audioTimestamp.flags = 0;
            _videoTimestamp.flags = 0;
            
        }

        if (isVideo && isReadyToRecord && !_flags.interrupted) {
            
            CMSampleBufferRef bufferToWrite = NULL;

            if (_timeOffset.value > 0) {
                bufferToWrite = [self _createOffsetSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
                if (!bufferToWrite) {
                    DLog(@"error subtracting the timeoffset from the sampleBuffer");
                }
            } else {
                bufferToWrite = sampleBuffer;
                CFRetain(bufferToWrite);
            }

            if (bufferToWrite) {
                // update the last video timestamp
                CMTime time = CMSampleBufferGetPresentationTimeStamp(bufferToWrite);
                CMTime duration = CMSampleBufferGetDuration(bufferToWrite);
                if (duration.value > 0)
                    time = CMTimeAdd(time, duration);
                
                if (time.value > _videoTimestamp.value) {
                    [self _writeSampleBuffer:bufferToWrite ofType:AVMediaTypeVideo];
                    _videoTimestamp = time;
                    _flags.videoWritten = YES;
                }
                CFRelease(bufferToWrite);
            }
            
        } else if (isAudio && isReadyToRecord && !_flags.interrupted) {
            
            CMSampleBufferRef bufferToWrite = NULL;

            if (_timeOffset.value > 0) {
                bufferToWrite = [self _createOffsetSampleBuffer:sampleBuffer withTimeOffset:_timeOffset];
                if (!bufferToWrite) {
                    DLog(@"error subtracting the timeoffset from the sampleBuffer");
                }
            } else {
                bufferToWrite = sampleBuffer;
                CFRetain(bufferToWrite);
            }

            if (bufferToWrite && _flags.videoWritten) {
                // update the last audio timestamp
                CMTime time = CMSampleBufferGetPresentationTimeStamp(bufferToWrite);
                CMTime duration = CMSampleBufferGetDuration(bufferToWrite);
                if (duration.value > 0)
                    time = CMTimeAdd(time, duration);

                if (time.value > _audioTimestamp.value) {
                    [self _writeSampleBuffer:bufferToWrite ofType:AVMediaTypeAudio];
                    _audioTimestamp = time;
                }
                CFRelease(bufferToWrite);
            }
        }
        
        if ( !wasReadyToRecord && isReadyToRecord ) {
            [self _enqueueBlockOnMainQueue:^{
                if ([_delegate respondsToSelector:@selector(visionDidStartVideoCapture:)])
                    [_delegate visionDidStartVideoCapture:self];
            }];
        }
        
        CFRelease(sampleBuffer);
        CFRelease(formatDescription);
    }];

}

#pragma mark - App NSNotifications

// TODO: support suspend/resume video recording

- (void)_applicationWillEnterForeground:(NSNotification *)notification
{
    DLog(@"applicationWillEnterForeground");
    [self _enqueueBlockInCaptureSessionQueue:^{
        if (!_flags.previewRunning)
            return;
        
        [self _enqueueBlockOnMainQueue:^{
            [self startPreview];
        }];
    }];
}

- (void)_applicationDidEnterBackground:(NSNotification *)notification
{
    DLog(@"applicationDidEnterBackground");
    if (_flags.recording)
        [self pauseVideoCapture];

    if (_flags.previewRunning) {
        [self stopPreview];
        [self _enqueueBlockInCaptureSessionQueue:^{
            _flags.previewRunning = YES;
        }];
    }
}

#pragma mark - AV NSNotifications

// capture session

// TODO: add in a better error recovery

- (void)_sessionRuntimeErrored:(NSNotification *)notification
{
    [self _enqueueBlockOnMainQueue:^{
        if ([notification object] == _captureSession) {
            NSError *error = [[notification userInfo] objectForKey:AVCaptureSessionErrorKey];
            if (error) {
                NSInteger errorCode = [error code];
                switch (errorCode) {
                    case AVErrorMediaServicesWereReset:
                    {
                        DLog(@"error media services were reset");
                        [self _destroyCamera];
                        if (_flags.previewRunning)
                            [self startPreview];
                        break;
                    }
                    case AVErrorDeviceIsNotAvailableInBackground:
                    {
                        DLog(@"error media services not available in background");
                        break;
                    }
                    default:
                    {
                        DLog(@"error media services failed, error (%@)", error);
                        [self _destroyCamera];
                        if (_flags.previewRunning)
                            [self startPreview];
                        break;
                    }
                }
            }
        }
    }];
}

- (void)_sessionStarted:(NSNotification *)notification
{
    [self _enqueueBlockOnMainQueue:^{        
        if ([notification object] == _captureSession) {
            DLog(@"session was started");
            
            // ensure there is a capture device setup
            if (_currentInput) {
                AVCaptureDevice *device = [_currentInput device];
                if (device) {
                    [_currentDevice removeObserver:self forKeyPath:@"adjustingFocus"];
                    _currentDevice = device;
                    [_currentDevice addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFocusObserverContext];
                }
            }
        
            if ([_delegate respondsToSelector:@selector(visionSessionDidStart:)]) {
                [_delegate visionSessionDidStart:self];
            }
        }
    }];
}

- (void)_sessionStopped:(NSNotification *)notification
{
    [self _enqueueBlockInCaptureVideoQueue:^{
        DLog(@"session was stopped");
        if (_flags.recording)
            [self endVideoCapture];
    
        [self _enqueueBlockOnMainQueue:^{
            if ([notification object] == _captureSession) {
                if ([_delegate respondsToSelector:@selector(visionSessionDidStop:)]) {
                    [_delegate visionSessionDidStop:self];
                }
            }
        }];
    }];
}

- (void)_sessionWasInterrupted:(NSNotification *)notification
{
    [self _enqueueBlockOnMainQueue:^{
        if ([notification object] == _captureSession) {
            DLog(@"session was interrupted");
            // notify stop?
        }
    }];
}

- (void)_sessionInterruptionEnded:(NSNotification *)notification
{
    [self _enqueueBlockOnMainQueue:^{
        if ([notification object] == _captureSession) {
            DLog(@"session interruption ended");
            // notify ended?
        }
    }];
}

// capture input

- (void)_inputPortFormatDescriptionDidChange:(NSNotification *)notification
{
    // when the input format changes, store the clean aperture
    // (clean aperture is the rect that represents the valid image data for this display)
    AVCaptureInputPort *inputPort = (AVCaptureInputPort *)[notification object];
    if (inputPort) {
        CMFormatDescriptionRef formatDescription = [inputPort formatDescription];
        if (formatDescription) {
            _cleanAperture = CMVideoFormatDescriptionGetCleanAperture(formatDescription, YES);
            if ([_delegate respondsToSelector:@selector(vision:cleanApertureDidChange:)]) {
                [_delegate vision:self cleanApertureDidChange:_cleanAperture];
            }
        }
    }
}

// capture device

- (void)_deviceSubjectAreaDidChange:(NSNotification *)notification
{
    [self _focus];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == (__bridge void *)PBJVisionFocusObserverContext ) {
    
        BOOL isFocusing = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
        if (isFocusing) {
            [self _focusStarted];
        } else {
            [self _focusEnded];
        }
        
	} else if ( context == (__bridge void *)(PBJVisionCaptureStillImageIsCapturingStillImageObserverContext) ) {
    
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		if ( isCapturingStillImage ) {
            [self _willCapturePhoto];
		} else {
            [self _didCapturePhoto];
        }
        
	}
}


@end

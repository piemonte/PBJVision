//
//  PBJVision.m
//
//  Created by Patrick Piemonte on 4/30/13.
//  Copyright (c) 2013. All rights reserved.
//

#import "PBJVision.h"
#import "PBJVisionUtilities.h"

#import <UIKit/UIDevice.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <OpenGLES/EAGL.h>

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
static NSString * const PBJVisionFlashAvailabilityObserverContext = @"PBJVisionFlashAvailabilityObserverContext";
static NSString * const PBJVisionTorchAvailabilityObserverContext = @"PBJVisionTorchAvailabilityObserverContext";
static NSString * const PBJVisionCaptureStillImageIsCapturingStillImageObserverContext = @"PBJVisionCaptureStillImageIsCapturingStillImageObserverContext";

// photo dictionary key definitions

NSString * const PBJVisionPhotoMetadataKey = @"PBJVisionPhotoMetadataKey";
NSString * const PBJVisionPhotoJPEGKey = @"PBJVisionPhotoJPEGKey";
NSString * const PBJVisionPhotoImageKey = @"PBJVisionPhotoImageKey";
NSString * const PBJVisionPhotoThumbnailKey = @"PBJVisionPhotoThumbnailKey";

// video dictionary key definitions

NSString * const PBJVisionVideoPathKey = @"PBJVisionVideoPathKey";
NSString * const PBJVisionVideoThumbnailKey = @"PBJVisionVideoThumbnailKey";

// buffer rendering shader uniforms and attributes
// TODO: create an abstraction for shaders

enum
{
    PBJVisionUniformY,
    PBJVisionUniformUV,
    PBJVisionUniformCount
};
GLint _uniforms[PBJVisionUniformCount];

enum
{
    PBJVisionAttributeVertex,
    PBJVisionAttributeTextureCoord,
    PBJVisionAttributeCount
};

///

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
    
    PBJFocusMode _focusMode;
    PBJFlashMode _flashMode;

    PBJOutputFormat _outputFormat;
    
    NSInteger _audioAssetBitRate;
    CGFloat _videoAssetBitRate;
    NSInteger _videoAssetFrameInterval;
    NSString *_captureSessionPreset;

    AVCaptureDevice *_currentDevice;
    AVCaptureDeviceInput *_currentInput;
    AVCaptureOutput *_currentOutput;
    
    AVCaptureVideoPreviewLayer *_previewLayer;
    CGRect _cleanAperture;

    NSURL *_outputURL;
    
    CMTime _timeOffset;
    CMTime _startTimestamp;
    CMTime _audioTimestamp;
    CMTime _videoTimestamp;

    // sample buffer rendering

    PBJCameraDevice _bufferDevice;
    PBJCameraOrientation _bufferOrientation;
    size_t _bufferWidth;
    size_t _bufferHeight;
    CGRect _presentationFrame;

    EAGLContext *_context;
    GLuint _program;
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;

    // flags
    
    struct {
        unsigned int previewRunning:1;
        unsigned int changingModes:1;
        unsigned int readyForAudio:1;
        unsigned int readyForVideo:1;
        unsigned int recording:1;
        unsigned int paused:1;
        unsigned int interrupted:1;
        unsigned int videoWritten:1;
        unsigned int videoRenderingEnabled:1;
        unsigned int thumbnailEnabled:1;
        unsigned int previewPhotoRequested:1;
    } __block _flags;
}

@end

@implementation PBJVision

@synthesize delegate = _delegate;
@synthesize previewLayer = _previewLayer;
@synthesize cleanAperture = _cleanAperture;
@synthesize cameraOrientation = _cameraOrientation;
@synthesize cameraDevice = _cameraDevice;
@synthesize cameraMode = _cameraMode;
@synthesize focusMode = _focusMode;
@synthesize flashMode = _flashMode;
@synthesize outputFormat = _outputFormat;
@synthesize context = _context;
@synthesize presentationFrame = _presentationFrame;
@synthesize audioAssetBitRate = _audioAssetBitRate;
@synthesize videoAssetBitRate = _videoAssetBitRate;
@synthesize videoAssetFrameInterval = _videoAssetFrameInterval;
@synthesize captureSessionPreset = _captureSessionPreset;

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

- (BOOL)isCaptureSessionActive
{
    return ([_captureSession isRunning]);
}

- (BOOL)isRecording
{
    return _flags.recording;
}

- (void)setVideoRenderingEnabled:(BOOL)videoRenderingEnabled
{
    _flags.videoRenderingEnabled = (unsigned int)videoRenderingEnabled;
}

- (BOOL)isVideoRenderingEnabled
{
    return _flags.videoRenderingEnabled;
}

- (void)setThumbnailEnabled:(BOOL)thumbnailEnabled
{
    _flags.thumbnailEnabled = (unsigned int)thumbnailEnabled;
}

- (BOOL)thumbnailEnabled
{
    return _flags.thumbnailEnabled;
}

- (Float64)capturedAudioSeconds
{
    if (_audioTimestamp.value > 0) {
        return CMTimeGetSeconds(CMTimeSubtract(_audioTimestamp, _startTimestamp));
    } else {
        return 0.0;
    }
}

- (Float64)capturedVideoSeconds
{
    if (_videoTimestamp.value > 0) {
        return CMTimeGetSeconds(CMTimeSubtract(_videoTimestamp, _startTimestamp));
    } else {
        return 0.0;
    }
}

- (void)setCameraOrientation:(PBJCameraOrientation)cameraOrientation
{
     if (cameraOrientation == _cameraOrientation)
        return;
     _cameraOrientation = cameraOrientation;
    
    if ([_previewLayer.connection isVideoOrientationSupported])
        [self _setOrientationForConnection:_previewLayer.connection];
}

- (void)_setOrientationForConnection:(AVCaptureConnection *)connection
{
    if (!connection || ![connection isVideoOrientationSupported])
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

- (void)_setCameraMode:(PBJCameraMode)cameraMode cameraDevice:(PBJCameraDevice)cameraDevice outputFormat:(PBJOutputFormat)outputFormat
{
    BOOL changeDevice = (_cameraDevice != cameraDevice);
    BOOL changeMode = (_cameraMode != cameraMode);
    BOOL changeOutputFormat = (_outputFormat != outputFormat);
    
    DLog(@"change device (%d) mode (%d) format (%d)", changeDevice, changeMode, changeOutputFormat);
    
    if (!changeMode && !changeDevice && !changeOutputFormat)
        return;
    
    if ([_delegate respondsToSelector:@selector(visionModeWillChange:)])
        [_delegate visionModeWillChange:self];
    
    _flags.changingModes = YES;
    
    _cameraDevice = cameraDevice;
    _cameraMode = cameraMode;
    
    _outputFormat = outputFormat;
    
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
    [self _setCameraMode:_cameraMode cameraDevice:cameraDevice outputFormat:_outputFormat];
}

- (void)setCameraMode:(PBJCameraMode)cameraMode
{
    [self _setCameraMode:cameraMode cameraDevice:_cameraDevice outputFormat:_outputFormat];
}

- (void)setOutputFormat:(PBJOutputFormat)outputFormat
{
    [self _setCameraMode:_cameraMode cameraDevice:_cameraDevice outputFormat:outputFormat];
}

- (BOOL)isCameraDeviceAvailable:(PBJCameraDevice)cameraDevice
{
    return [UIImagePickerController isCameraDeviceAvailable:(UIImagePickerControllerCameraDevice)cameraDevice];
}

- (void)setFlashMode:(PBJFlashMode)flashMode
{
    BOOL shouldChangeFlashMode = (_flashMode != flashMode);
    if (![_currentDevice hasFlash] || !shouldChangeFlashMode)
        return;

    _flashMode = flashMode;
    
    NSError *error = nil;
    if (_currentDevice && [_currentDevice lockForConfiguration:&error]) {
        
        switch (_cameraMode) {
          case PBJCameraModePhoto:
          {
            if ([_currentDevice isFlashModeSupported:(AVCaptureFlashMode)_flashMode]) {
                [_currentDevice setFlashMode:(AVCaptureFlashMode)_flashMode];
            }
            break;
          }
          case PBJCameraModeVideo:
          {
            if ([_currentDevice isFlashModeSupported:(AVCaptureFlashMode)_flashMode]) {
                [_currentDevice setFlashMode:AVCaptureFlashModeOff];
            }
            
            if ([_currentDevice isTorchModeSupported:(AVCaptureTorchMode)_flashMode]) {
                [_currentDevice setTorchMode:(AVCaptureTorchMode)_flashMode];
            }
            break;
          }
          default:
            break;
        }
    
        [_currentDevice unlockForConfiguration];
    
    } else if (error) {
        DLog(@"error locking device for flash mode change (%@)", error);
    }
}

- (PBJFlashMode)flashMode
{
    return _flashMode;
}

- (BOOL)isFlashAvailable
{
    return (_currentDevice && [_currentDevice hasFlash]);
}

#pragma mark - init

- (id)init
{
    self = [super init];
    if (self) {
        
        // setup GLES
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!_context) {
            DLog(@"failed to create GL context");
        }
        [self _setupGL];

        // default audio/video configuration
        _audioAssetBitRate = 64000;

        // Average bytes per second based on video dimensions
        // lower the bitRate, higher the compression
        // 87500, good for 480 x 360
        // 437500, good for 640 x 480
        // 1312500, good for 1280 x 720
        // 2975000, good for 1920 x 1080
        // 3750000, good for iFrame 960 x 540
        // 5000000, good for iFrame 1280 x 720

        CGFloat bytesPerSecond = 437500;
        _videoAssetBitRate = bytesPerSecond * 8;
        _videoAssetFrameInterval = 30;

        _captureSessionPreset = AVCaptureSessionPreset640x480;

        // default flags
        _flags.thumbnailEnabled = YES;
        _flags.previewPhotoRequested = NO;

        // setup queues
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

    [self _cleanUpTextures];
    
    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
        _videoTextureCache = NULL;
    }
    
    [self _destroyGL];
    [self _destroyCamera];
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
    
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn cvError = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
#else
    CVReturn cvError = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)_context, NULL, &_videoTextureCache);
#endif
    if (cvError) {
        NSLog(@"error CVOpenGLESTextureCacheCreate (%d)", cvError);
    }

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
    
    if (self.cameraMode != PBJCameraModePhoto)
	_captureDeviceAudio = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    _captureDeviceInputAudio = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceAudio error:&error];
    if (error) {
        DLog(@"error setting up audio input (%@)", error);
    }
    
    _captureOutputPhoto = [[AVCaptureStillImageOutput alloc] init];
    if (self.cameraMode != PBJCameraModePhoto)
    	_captureOutputAudio = [[AVCaptureAudioDataOutput alloc] init];
    _captureOutputVideo = [[AVCaptureVideoDataOutput alloc] init];
    
    if (self.cameraMode != PBJCameraModePhoto)
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

- (void)_setupVideoSettings {
    // setup video settings
    // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange Bi-Planar Component Y'CbCr 8-bit 4:2:0, full-range (luma=[0,255] chroma=[1,255])
    // baseAddr points to a big-endian CVPlanarPixelBufferInfo_YCbCrBiPlanar struct
    BOOL supportsFullRangeYUV = NO;
    BOOL supportsVideoRangeYUV = NO;
    NSArray *supportedPixelFormats = _captureOutputVideo.availableVideoCVPixelFormatTypes;
    for (NSNumber *currentPixelFormat in supportedPixelFormats) {
        if ([currentPixelFormat intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            supportsFullRangeYUV = YES;
        }
        if ([currentPixelFormat intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            supportsVideoRangeYUV = YES;
        }
    }
    
    NSDictionary *videoSettings = nil;
    
    if (supportsFullRangeYUV) {
        videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) };
    } else if (supportsVideoRangeYUV) {
        videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
    }
    
    if (videoSettings)
        [_captureOutputVideo setVideoSettings:videoSettings];

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
    NSString *sessionPreset = [_captureSession sessionPreset];
    
    // setup session device
    
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
    
    // setup session input/output
    
    if (shouldSwitchMode) {
    
        // disable audio when in use for photos, otherwise enable it
        
    	if (self.cameraMode == PBJCameraModePhoto) {
        
        	[_captureSession removeInput:_captureDeviceInputAudio];
        	[_captureSession removeOutput:_captureOutputAudio];
    	
        } else if (!_captureDeviceAudio && !_captureDeviceInputAudio && !_captureOutputAudio) {
        
            NSError *error = nil;
            _captureDeviceAudio = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
            _captureDeviceInputAudio = [AVCaptureDeviceInput deviceInputWithDevice:_captureDeviceAudio error:&error];
            if (error) {
                DLog(@"error setting up audio input (%@)", error);
            }

            _captureOutputAudio = [[AVCaptureAudioDataOutput alloc] init];
            [_captureOutputAudio setSampleBufferDelegate:self queue:_captureVideoDispatchQueue];
            
        }
        
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

    // setup video connection
    AVCaptureConnection *videoConnection = [_captureOutputVideo connectionWithMediaType:AVMediaTypeVideo];

    // setup input/output

    if (newCaptureOutput && newCaptureOutput == _captureOutputVideo && videoConnection) {
        
        // setup video orientation
        [self _setOrientationForConnection:videoConnection];
        
        // setup video stabilization, if available
        if ([videoConnection isVideoStabilizationSupported])
            [videoConnection setEnablesVideoStabilizationWhenAvailable:YES];

        // discard late frames
        [_captureOutputVideo setAlwaysDiscardsLateVideoFrames:NO];
        
        // specify video preset
        sessionPreset = AVCaptureSessionPreset640x480;

        [self _setupVideoSettings];
        
        // setup video device configuration
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {

            NSError *error = nil;
            if ([newCaptureDevice lockForConfiguration:&error]) {
            
                // smooth autofocus for videos
                if ([newCaptureDevice isSmoothAutoFocusSupported])
                    [newCaptureDevice setSmoothAutoFocusEnabled:YES];

                // setup framerate range
                // TODO: seek best framerate range for slow-motion recording
                CMTime frameDuration = CMTimeMake( 1, 30 );
                newCaptureDevice.activeVideoMinFrameDuration = frameDuration;
                newCaptureDevice.activeVideoMaxFrameDuration = frameDuration;
                
                [newCaptureDevice unlockForConfiguration];
        
            } else if (error) {
                DLog(@"error locking device for video device configuration (%@)", error);
            }
        
        } else {
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            // setup framerate
            CMTime frameDuration = CMTimeMake( 1, 30 );
            if ( videoConnection.supportsVideoMinFrameDuration )
                videoConnection.videoMinFrameDuration = frameDuration;
            if ( videoConnection.supportsVideoMaxFrameDuration )
                videoConnection.videoMaxFrameDuration = frameDuration;
#pragma clang diagnostic pop
        
        }
        
    } else if (newCaptureOutput && newCaptureOutput == _captureOutputPhoto) {
    
        // specify photo preset
        sessionPreset = AVCaptureSessionPresetPhoto;
    
        // setup photo settings
        NSDictionary *photoSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        AVVideoCodecJPEG, AVVideoCodecKey,
                                        nil];
        [_captureOutputPhoto setOutputSettings:photoSettings];
        
        // setup photo device configuration
        NSError *error = nil;
        if ([newCaptureDevice lockForConfiguration:&error]) {
            
            if ([newCaptureDevice isLowLightBoostSupported])
                [newCaptureDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:YES];
            
            [newCaptureDevice unlockForConfiguration];
        
        } else if (error) {
            DLog(@"error locking device for photo device configuration (%@)", error);
        }
            
    }

    // apply presets
    if ([_captureSession canSetSessionPreset:sessionPreset])
        [_captureSession setSessionPreset:sessionPreset];

    // KVO
    if (newCaptureDevice) {
        [_currentDevice removeObserver:self forKeyPath:@"adjustingFocus"];
        [_currentDevice removeObserver:self forKeyPath:@"flashAvailable"];
        [_currentDevice removeObserver:self forKeyPath:@"torchAvailable"];
        
        _currentDevice = newCaptureDevice;
        [_currentDevice addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFocusObserverContext];
        [_currentDevice addObserver:self forKeyPath:@"flashAvailable" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFlashAvailabilityObserverContext];
        [_currentDevice addObserver:self forKeyPath:@"torchAvailable" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionTorchAvailabilityObserverContext];
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
            [self _setOrientationForConnection:_previewLayer.connection];
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

// TODO: should add in exposure and white balance locks for completeness one day
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
    return [self isCaptureSessionActive] && !_flags.changingModes && isDiskSpaceAvailable;
}

- (UIImage *)_uiimageFromJPEGData:(NSData *)jpegData
{
    CGImageRef jpegCGImage = NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)jpegData);
    
    UIImageOrientation imageOrientation = UIImageOrientationUp;
    
    if (provider) {
        CGImageSourceRef imageSource = CGImageSourceCreateWithDataProvider(provider, NULL);
        if (imageSource) {
            if (CGImageSourceGetCount(imageSource) > 0) {
                jpegCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
                
                // extract the cgImage properties
                CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
                if (properties) {
                    // set orientation
                    CFNumberRef orientationProperty = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
                    if (orientationProperty) {
                        NSInteger exifOrientation = 1;
                        CFNumberGetValue(orientationProperty, kCFNumberIntType, &exifOrientation);
                        imageOrientation = [self _imageOrientationFromExifOrientation:exifOrientation];
                    }
                    
                    CFRelease(properties);
                }
                
            }
            CFRelease(imageSource);
        }
        CGDataProviderRelease(provider);
    }
    
    UIImage *image = nil;
    if (jpegCGImage) {
        image = [[UIImage alloc] initWithCGImage:jpegCGImage scale:1.0 orientation:imageOrientation];
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
                [options setObject:@(YES) forKey:(id)kCGImageSourceCreateThumbnailFromImageAlways];
                [options setObject:@(PBJVisionThumbnailWidth) forKey:(id)kCGImageSourceThumbnailMaxPixelSize];
                [options setObject:@(YES) forKey:(id)kCGImageSourceCreateThumbnailWithTransform];
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


- (UIImageOrientation)_imageOrientationFromExifOrientation:(NSInteger)exifOrientation
{
    UIImageOrientation imageOrientation = UIImageOrientationUp;
    
    switch (exifOrientation) {
        case 1:
            imageOrientation = UIImageOrientationUp;
            break;
        case 2:
            imageOrientation = UIImageOrientationUpMirrored;
            break;
        case 3:
            imageOrientation = UIImageOrientationDown;
            break;
        case 4:
            imageOrientation = UIImageOrientationDownMirrored;
            break;
        case 5:
            imageOrientation = UIImageOrientationLeftMirrored;
            break;
        case 6:
           imageOrientation = UIImageOrientationRight;
           break;
        case 7:
            imageOrientation = UIImageOrientationRightMirrored;
            break;
        case 8:
            imageOrientation = UIImageOrientationLeft;
            break;
        default:
            break;
    }
    
    return imageOrientation;
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
    if (![self _canSessionCaptureWithOutput:_currentOutput] || _cameraMode != PBJCameraModePhoto) {
        DLog(@"session is not setup properly for capture");
        return;
    }

    AVCaptureConnection *connection = [_currentOutput connectionWithMediaType:AVMediaTypeVideo];
    [self _setOrientationForConnection:connection];
    
    [_captureOutputPhoto captureStillImageAsynchronouslyFromConnection:connection completionHandler:
    ^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        
        if (!imageDataSampleBuffer) {
            DLog(@"failed to obtain image data sample buffer");
            return;
        }
    
        if (error) {
            if ([_delegate respondsToSelector:@selector(vision:capturedPhoto:error:)]) {
                [_delegate vision:self capturedPhoto:nil error:error];
            }
            return;
        }
    
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
        
        // add JPEG, UIImage, thumbnail
        NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        if (jpegData) {
            // add JPEG
            [photoDict setObject:jpegData forKey:PBJVisionPhotoJPEGKey];
            
            // add image
            UIImage *image = [self _uiimageFromJPEGData:jpegData];
            if (image) {
                [photoDict setObject:image forKey:PBJVisionPhotoImageKey];
            } else {
                DLog(@"failed to create image from JPEG");
                // TODO: return delegate on error
            }
            
            // add thumbnail
            if (_flags.thumbnailEnabled) {
                UIImage *thumbnail = [self _thumbnailJPEGData:jpegData];
                if (thumbnail)
                    [photoDict setObject:thumbnail forKey:PBJVisionPhotoThumbnailKey];
            }
            
        }
        
        if ([_delegate respondsToSelector:@selector(vision:capturedPhoto:error:)]) {
            [_delegate vision:self capturedPhoto:photoDict error:error];
        }
        
        // run a post shot focus
        [self performSelector:@selector(_focus) withObject:nil afterDelay:0.5f];
    }];
}

- (void)capturePreviewPhoto {
    [_captureOutputVideo setVideoSettings:@{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) }];
    _flags.previewPhotoRequested = YES;
}


#pragma mark - video

- (BOOL)supportsVideoCapture
{
    return ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0);
}

- (BOOL)canCaptureVideo
{
    BOOL isDiskSpaceAvailable = [PBJVisionUtilities availableDiskSpaceInBytes] > PBJVisionRequiredMinimumDiskSpaceInBytes;
    return [self supportsVideoCapture] && [self isCaptureSessionActive] && !_flags.changingModes && isDiskSpaceAvailable;
}

- (NSArray *)_metadataArray
{
    UIDevice *currentDevice = [UIDevice currentDevice];
    
    // device model
    AVMutableMetadataItem *modelItem = [[AVMutableMetadataItem alloc] init];
    [modelItem setKeySpace:AVMetadataKeySpaceCommon];
    [modelItem setKey:AVMetadataCommonKeyModel];
    [modelItem setValue:[currentDevice localizedModel]];

    // software
    AVMutableMetadataItem *softwareItem = [[AVMutableMetadataItem alloc] init];
    [softwareItem setKeySpace:AVMetadataKeySpaceCommon];
    [softwareItem setKey:AVMetadataCommonKeySoftware];
    [softwareItem setValue:[NSString stringWithFormat:@"%@ %@ PBJVision", [currentDevice systemName], [currentDevice systemVersion]]];

    // creation date
    AVMutableMetadataItem *creationDateItem = [[AVMutableMetadataItem alloc] init];
    [creationDateItem setKeySpace:AVMetadataKeySpaceCommon];
    [creationDateItem setKey:AVMetadataCommonKeyCreationDate];
    [creationDateItem setValue:[NSString PBJformattedTimestampStringFromDate:[NSDate date]]];

    return @[modelItem, softwareItem, creationDateItem];
}

- (void)startVideoCapture
{
    if (![self _canSessionCaptureWithOutput:_currentOutput]) {
        DLog(@"session is not setup properly for capture");
        return;
    }
    
    DLog(@"starting video capture");
        
    [self _enqueueBlockInCaptureVideoQueue:^{

        if (_flags.recording || _flags.paused)
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
        _startTimestamp = CMClockGetTime(CMClockGetHostTimeClock());

        
        _flags.recording = YES;
        _flags.paused = NO;
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
        
        NSArray *metadata = [self _metadataArray];
        _assetWriter.metadata = metadata;
        
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

        _flags.paused = YES;
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
        if (!_flags.recording || !_flags.paused)
            return;
 
        if (!_assetWriter) {
            DLog(@"assetWriter unavailable to resume");
            return;
        }
 
        DLog(@"resuming video capture");
       
        _flags.paused = NO;

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
        _flags.paused = NO;
        
        void (^finishWritingCompletionHandler)(void) = ^{
            _timeOffset = kCMTimeZero;
            _audioTimestamp = kCMTimeZero;
            _videoTimestamp = kCMTimeZero;
            _startTimestamp = CMClockGetTime(CMClockGetHostTimeClock());
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

#pragma mark - sample buffer setup

- (BOOL)_setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription
{
	const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormatDescription);
    if (!asbd) {
        DLog(@"audio stream description used with non-audio format description");
        return NO;
    }
    
	unsigned int channels = asbd->mChannelsPerFrame;
    double sampleRate = asbd->mSampleRate;

    DLog(@"audio stream setup, channels (%d) sampleRate (%f)", channels, sampleRate);
    
    size_t aclSize = 0;
	const AudioChannelLayout *currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(currentFormatDescription, &aclSize);
	NSData *currentChannelLayoutData = ( currentChannelLayout && aclSize > 0 ) ? [NSData dataWithBytes:currentChannelLayout length:aclSize] : [NSData data];
    
    NSDictionary *audioCompressionSettings = @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                AVNumberOfChannelsKey : @(channels),
                                                AVSampleRateKey :  @(sampleRate),
                                                AVEncoderBitRateKey : @(_audioAssetBitRate),
                                                AVChannelLayoutKey : currentChannelLayoutData };

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
    
    CMVideoDimensions videoDimensions = dimensions;
    switch (_outputFormat) {
        case PBJOutputFormatSquare:
        {
            int32_t min = MIN(dimensions.width, dimensions.height);
            videoDimensions.width = min;
            videoDimensions.height = min;
            break;
        }
        case PBJOutputFormatWidescreen:
        {
            videoDimensions.width = dimensions.width;
            videoDimensions.height = (int32_t)(dimensions.width / 1.5f);
            break;
        }
        case PBJOutputFormatPreset:
        default:
            break;
    }
    
    NSDictionary *compressionSettings = @{ AVVideoAverageBitRateKey : @(_videoAssetBitRate),
                                           AVVideoMaxKeyFrameIntervalKey : @(_videoAssetFrameInterval) };

	NSDictionary *videoSettings = @{ AVVideoCodecKey : AVVideoCodecH264,
                                     AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
                                     AVVideoWidthKey : @(videoDimensions.width),
                                     AVVideoHeightKey : @(videoDimensions.height),
                                     AVVideoCompressionPropertiesKey : compressionSettings };
    
	if ([_assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
    
		_assetWriterVideoIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
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

#pragma mark - sample buffer processing

- (void)_cleanUpTextures
{
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);

    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;        
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

// convert CoreVideo YUV pixel buffer (Y luminance and Cb Cr chroma) into RGB
// processing is done on the GPU, operation WAY more efficient than converting .on the CPU
- (void)_processSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (!_context)
        return;

    if (!_videoTextureCache)
        return;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    if (CVPixelBufferLockBaseAddress(imageBuffer, 0) != kCVReturnSuccess)
        return;

    [EAGLContext setCurrentContext:_context];

    [self _cleanUpTextures];

    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

    // only bind the vertices once or if parameters change
    
    if (_bufferWidth != width ||
        _bufferHeight != height ||
        _bufferDevice != _cameraDevice ||
        _bufferOrientation != _cameraOrientation) {
        
        _bufferWidth = width;
        _bufferHeight = height;
        _bufferDevice = _cameraDevice;
        _bufferOrientation = _cameraOrientation;
        [self _setupBuffers];
        
    }
    
    // always upload the texturs since the input may be changing
    
    CVReturn error = 0;
    
    // Y-plane
    glActiveTexture(GL_TEXTURE0);
    error = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                        _videoTextureCache,
                                                        imageBuffer,
                                                        NULL,
                                                        GL_TEXTURE_2D,
                                                        GL_RED_EXT,
                                                        (GLsizei)_bufferWidth,
                                                        (GLsizei)_bufferHeight,
                                                        GL_RED_EXT,
                                                        GL_UNSIGNED_BYTE,
                                                        0,
                                                        &_lumaTexture);
    if (error) {
        DLog(@"error CVOpenGLESTextureCacheCreateTextureFromImage (%d)", error);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); 
    
    // UV-plane
    glActiveTexture(GL_TEXTURE1);
    error = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                         _videoTextureCache,
                                                         imageBuffer,
                                                         NULL,
                                                         GL_TEXTURE_2D,
                                                         GL_RG_EXT,
                                                         (GLsizei)(_bufferWidth * 0.5),
                                                         (GLsizei)(_bufferHeight * 0.5),
                                                         GL_RG_EXT,
                                                         GL_UNSIGNED_BYTE,
                                                         1,
                                                         &_chromaTexture);
    if (error) {
        DLog(@"error CVOpenGLESTextureCacheCreateTextureFromImage (%d)", error);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    if (CVPixelBufferUnlockBaseAddress(imageBuffer, 0) != kCVReturnSuccess)
        return;

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (_flags.previewPhotoRequested) {
        _flags.previewPhotoRequested = NO;
        CGImageRef imageRef = [self cgImageFromSampleBuffer:sampleBuffer];
        if ([_delegate respondsToSelector:@selector(vision:capturedLivePhotoFromBuffer:)]) {
            [_delegate vision:self capturedLivePhotoFromBuffer:imageRef];
        }
        [self _setupVideoSettings];
    }
    
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
    
        if (!_flags.recording || _flags.paused) {
            CFRelease(sampleBuffer);
            CFRelease(formatDescription);
            return;
        }

        if (!_assetWriter) {
            CFRelease(sampleBuffer);
            CFRelease(formatDescription);
            return;
        }
     
        BOOL isAudio = (self.cameraMode != PBJCameraModePhoto) && (connection == [_captureOutputAudio connectionWithMediaType:AVMediaTypeAudio]);
        BOOL isVideo = (connection == [_captureOutputVideo connectionWithMediaType:AVMediaTypeVideo]);

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
                // update video and the last timestamp
                CMTime time = CMSampleBufferGetPresentationTimeStamp(bufferToWrite);
                CMTime duration = CMSampleBufferGetDuration(bufferToWrite);
                if (duration.value > 0)
                    time = CMTimeAdd(time, duration);
                
                if (time.value > _videoTimestamp.value) {
                    [self _writeSampleBuffer:bufferToWrite ofType:AVMediaTypeVideo];
                    _videoTimestamp = time;
                    _flags.videoWritten = YES;
                }
                
                // process the sample buffer for rendering
                if (_flags.videoRenderingEnabled && _flags.videoWritten) {
                    [self _executeBlockOnMainQueue:^{
                        [self _processSampleBuffer:bufferToWrite];
                    }];
                }
                
                CFRelease(bufferToWrite);

                [self _enqueueBlockOnMainQueue:^{
                    if ([_delegate respondsToSelector:@selector(visionDidCaptureVideoSample:)]) {
                        [_delegate visionDidCaptureVideoSample:self];
                    }
                }];
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

                [self _enqueueBlockOnMainQueue:^{
                    if ([_delegate respondsToSelector:@selector(visionDidCaptureAudioSample:)]) {
                        [_delegate visionDidCaptureAudioSample:self];
                    }
                }];
            }
        }
        
        CFRelease(sampleBuffer);
        CFRelease(formatDescription);
    }];

}

- (CGImageRef)cgImageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef newImage = CGBitmapContextCreateImage(context);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return newImage;
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
                    [_currentDevice removeObserver:self forKeyPath:@"flashAvailable"];
                    [_currentDevice removeObserver:self forKeyPath:@"torchAvailable"];
                    
                    _currentDevice = device;
                    [_currentDevice addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFocusObserverContext];
                    [_currentDevice addObserver:self forKeyPath:@"flashAvailable" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionFlashAvailabilityObserverContext];
                    [_currentDevice addObserver:self forKeyPath:@"torchAvailable" options:NSKeyValueObservingOptionNew context:(__bridge void *)PBJVisionTorchAvailabilityObserverContext];
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
            if ([_delegate respondsToSelector:@selector(vision:didChangeCleanAperture:)]) {
                [_delegate vision:self didChangeCleanAperture:_cleanAperture];
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
    
    } else if ( context == (__bridge void *)PBJVisionFlashAvailabilityObserverContext ||
                context == (__bridge void *)PBJVisionTorchAvailabilityObserverContext ) {
    
//        DLog(@"flash/torch availability did change");
        if ([_delegate respondsToSelector:@selector(visionDidChangeFlashAvailablility:)])
            [_delegate visionDidChangeFlashAvailablility:self];
    
	} else if ( context == (__bridge void *)(PBJVisionCaptureStillImageIsCapturingStillImageObserverContext) ) {
    
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		if ( isCapturingStillImage ) {
            [self _willCapturePhoto];
		} else {
            [self _didCapturePhoto];
        }
        
	} else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - OpenGLES context support

- (void)_setupBuffers
{

// unit square for testing
//    static const GLfloat unitSquareVertices[] = {
//        -1.0f, -1.0f,
//        1.0f, -1.0f,
//        -1.0f,  1.0f,
//        1.0f,  1.0f,
//    };
    
    CGSize inputSize = CGSizeMake(_bufferWidth, _bufferHeight);
    CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(inputSize, _presentationFrame);
    
    CGFloat widthScale = CGRectGetHeight(_presentationFrame) / CGRectGetHeight(insetRect);
    CGFloat heightScale = CGRectGetWidth(_presentationFrame) / CGRectGetWidth(insetRect);

    static GLfloat vertices[8];

    vertices[0] = (GLfloat) -widthScale;
    vertices[1] = (GLfloat) -heightScale;
    vertices[2] = (GLfloat) widthScale;
    vertices[3] = (GLfloat) -heightScale;
    vertices[4] = (GLfloat) -widthScale;
    vertices[5] = (GLfloat) heightScale;
    vertices[6] = (GLfloat) widthScale;
    vertices[7] = (GLfloat) heightScale;

    static const GLfloat textureCoordinates[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
    static const GLfloat textureCoordinatesVerticalFlip[] = {
        1.0f, 1.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 0.0f,
    };
    
    glEnableVertexAttribArray(PBJVisionAttributeVertex);
    glVertexAttribPointer(PBJVisionAttributeVertex, 2, GL_FLOAT, GL_FALSE, 0, vertices);
    
    if (_cameraDevice == PBJCameraDeviceFront) {
        glEnableVertexAttribArray(PBJVisionAttributeTextureCoord);
        glVertexAttribPointer(PBJVisionAttributeTextureCoord, 2, GL_FLOAT, GL_FALSE, 0, textureCoordinatesVerticalFlip);
    } else {
        glEnableVertexAttribArray(PBJVisionAttributeTextureCoord);
        glVertexAttribPointer(PBJVisionAttributeTextureCoord, 2, GL_FLOAT, GL_FALSE, 0, textureCoordinates);
    }
}

- (void)_setupGL
{
    [EAGLContext setCurrentContext:_context];
    
    [self _loadShaders];
    
    glUseProgram(_program);
        
    glUniform1i(_uniforms[PBJVisionUniformY], 0);
    glUniform1i(_uniforms[PBJVisionUniformUV], 1);
}

- (void)_destroyGL
{
    [EAGLContext setCurrentContext:_context];

    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
}

#pragma mark - OpenGLES shader support
// TODO: abstract this in future

- (BOOL)_loadShaders
{
    GLuint vertShader;
    GLuint fragShader;
    NSString *vertShaderName;
    NSString *fragShaderName;
    
    _program = glCreateProgram();
    
    vertShaderName = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self _compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderName]) {
        DLog(@"failed to compile vertex shader");
        return NO;
    }
    
    fragShaderName = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self _compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderName]) {
        DLog(@"failed to compile fragment shader");
        return NO;
    }
    
    glAttachShader(_program, vertShader);
    glAttachShader(_program, fragShader);
    
    glBindAttribLocation(_program, PBJVisionAttributeVertex, "a_position");
    glBindAttribLocation(_program, PBJVisionAttributeTextureCoord, "a_texture");
    
    if (![self _linkProgram:_program]) {
        DLog(@"failed to link program, %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    _uniforms[PBJVisionUniformY] = glGetUniformLocation(_program, "u_samplerY");
    _uniforms[PBJVisionUniformUV] = glGetUniformLocation(_program, "u_samplerUV");
    
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)_compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        DLog(@"failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)_linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}


@end

//
//  PBJVision.h
//
//  Created by Patrick Piemonte on 4/30/13.
//  Copyright (c) 2013. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// vision types

typedef NS_ENUM(NSInteger, PBJCameraDevice) {
    PBJCameraDeviceBack = UIImagePickerControllerCameraDeviceRear,
    PBJCameraDeviceFront = UIImagePickerControllerCameraDeviceFront
};

typedef NS_ENUM(NSInteger, PBJCameraMode) {
    PBJCameraModePhoto = UIImagePickerControllerCameraCaptureModePhoto,
    PBJCameraModeVideo = UIImagePickerControllerCameraCaptureModeVideo
};

typedef NS_ENUM(NSInteger, PBJCameraOrientation) {
    PBJCameraOrientationPortrait = AVCaptureVideoOrientationPortrait,
    PBJCameraOrientationPortraitUpsideDown = AVCaptureVideoOrientationPortraitUpsideDown,
    PBJCameraOrientationLandscapeRight = AVCaptureVideoOrientationLandscapeRight,
    PBJCameraOrientationLandscapeLeft = AVCaptureVideoOrientationLandscapeLeft,
};

typedef NS_ENUM(NSInteger, PBJFocusMode) {
    PBJFocusModeLocked = AVCaptureFocusModeLocked,
    PBJFocusModeAutoFocus = AVCaptureFocusModeAutoFocus,
    PBJFocusModeContinuousAutoFocus = AVCaptureFocusModeContinuousAutoFocus
};

typedef NS_ENUM(NSInteger, PBJFlashMode) {
    PBJFlashModeOff  = AVCaptureFlashModeOff,
    PBJFlashModeOn   = AVCaptureFlashModeOn,
    PBJFlashModeAuto = AVCaptureFlashModeAuto
};

typedef NS_ENUM(NSInteger, PBJOutputFormat) {
    PBJOutputFormatPreset = 0,
    PBJOutputFormatSquare,
    PBJOutputFormatWidescreen
};


// photo dictionary keys

extern NSString * const PBJVisionPhotoMetadataKey;
extern NSString * const PBJVisionPhotoJPEGKey;
extern NSString * const PBJVisionPhotoImageKey;
extern NSString * const PBJVisionPhotoThumbnailKey; // 160x120

// video dictionary keys

extern NSString * const PBJVisionVideoPathKey;
extern NSString * const PBJVisionVideoThumbnailKey;

@class EAGLContext;
@protocol PBJVisionDelegate;
@interface PBJVision : NSObject
{
}

+ (PBJVision *)sharedInstance;

@property (nonatomic, weak) id<PBJVisionDelegate> delegate;

// session

@property (nonatomic, readonly, getter=isCaptureSessionActive) BOOL captureSessionActive;

// setup

@property (nonatomic) PBJCameraOrientation cameraOrientation;
@property (nonatomic) PBJCameraDevice cameraDevice;
@property (nonatomic) PBJCameraMode cameraMode;
@property (nonatomic) PBJFocusMode focusMode;
- (BOOL)isCameraDeviceAvailable:(PBJCameraDevice)cameraDevice;

@property (nonatomic) PBJFlashMode flashMode; // flash and torch
@property (nonatomic, readonly, getter=isFlashAvailable) BOOL flashAvailable;

// video output/compression settings

@property (nonatomic) PBJOutputFormat outputFormat;
@property (nonatomic) CGFloat videoAssetBitRate;
@property (nonatomic) NSInteger audioAssetBitRate;
@property (nonatomic) NSInteger videoAssetFrameInterval;
@property (nonatomic, strong) NSString *captureSessionPreset;

// preview

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, readonly) CGRect cleanAperture;

- (void)startPreview;
- (void)stopPreview;

- (void)unfreezePreview; // preview is automatically timed and frozen with photo capture

// focus

- (void)focusAtAdjustedPoint:(CGPoint)adjustedPoint;

// photo

@property (nonatomic, readonly) BOOL canCapturePhoto;
- (void)capturePhoto;
- (void)capturePreviewPhoto;
@property (nonatomic) BOOL thumbnailEnabled; // thumbnail generation, disabling reduces processing time for an photo

// video
// use pause/resume if a session is in progress, end finalizes that recording session

@property (nonatomic, readonly, getter=isRecording) BOOL recording;
@property (nonatomic, readonly) BOOL supportsVideoCapture;
@property (nonatomic, readonly) BOOL canCaptureVideo;

@property (nonatomic, getter=isVideoRenderingEnabled) BOOL videoRenderingEnabled;
@property (nonatomic, readonly) EAGLContext *context;
@property (nonatomic) CGRect presentationFrame;

@property (nonatomic, readonly) Float64 capturedAudioSeconds;
@property (nonatomic, readonly) Float64 capturedVideoSeconds;

- (void)startVideoCapture;
- (void)pauseVideoCapture;
- (void)resumeVideoCapture;
- (void)endVideoCapture;

@end

@protocol PBJVisionDelegate <NSObject>
@optional

- (void)visionSessionWillStart:(PBJVision *)vision;
- (void)visionSessionDidStart:(PBJVision *)vision;
- (void)visionSessionDidStop:(PBJVision *)vision;

- (void)visionModeWillChange:(PBJVision *)vision;
- (void)visionModeDidChange:(PBJVision *)vision;

- (void)vision:(PBJVision *)vision didChangeCleanAperture:(CGRect)cleanAperture;

- (void)visionWillStartFocus:(PBJVision *)vision;
- (void)visionDidStopFocus:(PBJVision *)vision;

- (void)visionDidChangeFlashAvailablility:(PBJVision *)vision; // flash and torch

// photo

- (void)visionWillCapturePhoto:(PBJVision *)vision;
- (void)visionDidCapturePhoto:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedPhoto:(NSDictionary *)photoDict error:(NSError *)error;
- (void)vision:(PBJVision *)vision capturedLivePhotoFromBuffer:(CGImageRef)imageRef;

// video

- (void)visionDidStartVideoCapture:(PBJVision *)vision;
- (void)visionDidPauseVideoCapture:(PBJVision *)vision; // stopped but not ended
- (void)visionDidResumeVideoCapture:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error;

// video capture progress

- (void)visionDidCaptureVideoSample:(PBJVision *) vision;
- (void)visionDidCaptureAudioSample:(PBJVision *) vision;

@end

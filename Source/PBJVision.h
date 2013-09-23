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
@property (nonatomic, readonly, getter=isActive) BOOL active;

// setup

@property (nonatomic) PBJCameraOrientation cameraOrientation;
@property (nonatomic) PBJCameraDevice cameraDevice;
@property (nonatomic) PBJCameraMode cameraMode;

@property (nonatomic) PBJFocusMode focusMode;
@property (nonatomic) PBJFlashMode flashMode; // flash and torch

@property (nonatomic) PBJOutputFormat outputFormat;

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

// video
// use pause/resume if a session is in progress, end finalizes that recording session

@property (nonatomic, readonly, getter=isRecording) BOOL recording;
@property (nonatomic, readonly) BOOL supportsVideoCapture;
@property (nonatomic, readonly) BOOL canCaptureVideo;

@property (nonatomic, getter=isVideoRenderingEnabled) BOOL videoRenderingEnabled;
@property (nonatomic, readonly) EAGLContext *context;
@property (nonatomic) CGRect presentationFrame;

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

- (void)vision:(PBJVision *)vision cleanApertureDidChange:(CGRect)cleanAperture;
- (void)visionWillStartFocus:(PBJVision *)vision;
- (void)visionDidStopFocus:(PBJVision *)vision;


- (void)visionCameraViewDidBeginAdjustingExposure:(PBJVision *)vision;
- (void)visionCameraViewDidFinishAdjustingExposure:(PBJVision *)vision;

- (void)visionWillCapturePhoto:(PBJVision *)vision;
- (void)visionDidCapturePhoto:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedPhoto:(NSDictionary *)photoDict error:(NSError *)error;

- (void)visionDidStartVideoCapture:(PBJVision *)vision;
- (void)visionDidPauseVideoCapture:(PBJVision *)vision; // stopped but not ended
- (void)visionDidResumeVideoCapture:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error;

@end

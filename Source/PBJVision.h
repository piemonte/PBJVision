//
//  PBJVision.h
//  Vision
//
//  Created by Patrick Piemonte on 4/30/13.
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

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "PBJVisionTypes.h"

// PBJError

extern NSString * const PBJVisionErrorDomain;

typedef NS_ENUM(NSInteger, PBJVisionErrorType)
{
    PBJVisionErrorUnknown = -1,
    PBJVisionErrorCancelled = 100
};

// photo dictionary keys

extern NSString * const PBJVisionPhotoMetadataKey;
extern NSString * const PBJVisionPhotoJPEGKey;
extern NSString * const PBJVisionPhotoImageKey;
extern NSString * const PBJVisionPhotoThumbnailKey; // 160x120

// video dictionary keys

extern NSString * const PBJVisionVideoPathKey;
extern NSString * const PBJVisionVideoThumbnailKey;
extern NSString * const PBJVisionVideoCapturedDurationKey; // Captured duration in seconds

// suggested videoBitRate constants

static CGFloat const PBJVideoBitRate480x360 = 87500 * 8;
static CGFloat const PBJVideoBitRate640x480 = 437500 * 8;
static CGFloat const PBJVideoBitRate1280x720 = 1312500 * 8;
static CGFloat const PBJVideoBitRate1920x1080 = 2975000 * 8;
static CGFloat const PBJVideoBitRate960x540 = 3750000 * 8;
static CGFloat const PBJVideoBitRate1280x750 = 5000000 * 8;

@class EAGLContext;
@protocol PBJVisionDelegate;
@interface PBJVision : NSObject

+ (PBJVision *)sharedInstance;

@property (nonatomic, weak) id<PBJVisionDelegate> delegate;

// session

@property (nonatomic, readonly, getter=isCaptureSessionActive) BOOL captureSessionActive;

// setup

@property (nonatomic) PBJCameraOrientation cameraOrientation;
@property (nonatomic) PBJCameraMode cameraMode;
@property (nonatomic) PBJCameraDevice cameraDevice;
- (BOOL)isCameraDeviceAvailable:(PBJCameraDevice)cameraDevice;

@property (nonatomic) PBJFlashMode flashMode; // flash and torch
@property (nonatomic, readonly, getter=isFlashAvailable) BOOL flashAvailable;

@property (nonatomic) PBJMirroringMode mirroringMode;

// video output settings

@property (nonatomic, copy) NSString *captureSessionPreset;
@property (nonatomic) PBJOutputFormat outputFormat;

// video compression settings

@property (nonatomic) CGFloat videoBitRate;
@property (nonatomic) NSInteger audioBitRate;
@property (nonatomic) NSDictionary *additionalCompressionProperties;

// video frame rate (adjustment may change the capture format (AVCaptureDeviceFormat : FoV, zoom factor, etc)

@property (nonatomic) NSInteger videoFrameRate; // desired fps for active cameraDevice
- (BOOL)supportsVideoFrameRate:(NSInteger)videoFrameRate;

// preview

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) BOOL autoUpdatePreviewOrientation;
@property (nonatomic) PBJCameraOrientation previewOrientation;
@property (nonatomic, readonly) CGRect cleanAperture;

- (void)startPreview;
- (void)stopPreview;

- (void)unfreezePreview; // preview is automatically timed and frozen with photo capture

// focus, exposure, white balance

// note: focus and exposure modes change when adjusting on point
- (BOOL)isFocusPointOfInterestSupported;
- (void)focusExposeAndAdjustWhiteBalanceAtAdjustedPoint:(CGPoint)adjustedPoint;

@property (nonatomic) PBJFocusMode focusMode;
@property (nonatomic, readonly, getter=isFocusLockSupported) BOOL focusLockSupported;
- (void)focusAtAdjustedPointOfInterest:(CGPoint)adjustedPoint;

@property (nonatomic) PBJExposureMode exposureMode;
@property (nonatomic, readonly, getter=isExposureLockSupported) BOOL exposureLockSupported;
- (void)exposeAtAdjustedPointOfInterest:(CGPoint)adjustedPoint;

// photo

@property (nonatomic, readonly) BOOL canCapturePhoto;
- (void)capturePhoto;

@property (nonatomic) BOOL thumbnailEnabled; // thumbnail generation, disabling reduces processing time for a photo

// video
// use pause/resume if a session is in progress, end finalizes that recording session

@property (nonatomic, readonly) BOOL supportsVideoCapture;
@property (nonatomic, readonly) BOOL canCaptureVideo;
@property (nonatomic, readonly, getter=isRecording) BOOL recording;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;

@property (nonatomic, getter=isVideoRenderingEnabled) BOOL videoRenderingEnabled;
@property (nonatomic, getter=isAudioCaptureEnabled) BOOL audioCaptureEnabled;

@property (nonatomic, readonly) EAGLContext *context;
@property (nonatomic) CGRect presentationFrame;

@property (nonatomic) CMTime maximumCaptureDuration; // automatically triggers vision:capturedVideo:error: after exceeding threshold, (kCMTimeInvalid records without threshold)
@property (nonatomic, readonly) Float64 capturedAudioSeconds;
@property (nonatomic, readonly) Float64 capturedVideoSeconds;

- (void)startVideoCapture;
- (void)pauseVideoCapture;
- (void)resumeVideoCapture;
- (void)endVideoCapture;
- (void)cancelVideoCapture;

@end

@protocol PBJVisionDelegate <NSObject>
@optional

// session

- (void)visionSessionWillStart:(PBJVision *)vision;
- (void)visionSessionDidStart:(PBJVision *)vision;
- (void)visionSessionDidStop:(PBJVision *)vision;

- (void)visionSessionWasInterrupted:(PBJVision *)vision;
- (void)visionSessionInterruptionEnded:(PBJVision *)vision;

// device / mode / format

- (void)visionCameraDeviceWillChange:(PBJVision *)vision;
- (void)visionCameraDeviceDidChange:(PBJVision *)vision;

- (void)visionCameraModeWillChange:(PBJVision *)vision;
- (void)visionCameraModeDidChange:(PBJVision *)vision;

- (void)visionOutputFormatWillChange:(PBJVision *)vision;
- (void)visionOutputFormatDidChange:(PBJVision *)vision;

- (void)vision:(PBJVision *)vision didChangeCleanAperture:(CGRect)cleanAperture;

- (void)visionDidChangeVideoFormatAndFrameRate:(PBJVision *)vision;

// focus / exposure

- (void)visionWillStartFocus:(PBJVision *)vision;
- (void)visionDidStopFocus:(PBJVision *)vision;

- (void)visionWillChangeExposure:(PBJVision *)vision;
- (void)visionDidChangeExposure:(PBJVision *)vision;

- (void)visionDidChangeFlashMode:(PBJVision *)vision; // flash or torch was changed

// authorization / availability

- (void)visionDidChangeAuthorizationStatus:(PBJAuthorizationStatus)status;
- (void)visionDidChangeFlashAvailablility:(PBJVision *)vision; // flash or torch is available

// preview

- (void)visionSessionDidStartPreview:(PBJVision *)vision;
- (void)visionSessionDidStopPreview:(PBJVision *)vision;

// photo

- (void)visionWillCapturePhoto:(PBJVision *)vision;
- (void)visionDidCapturePhoto:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedPhoto:(NSDictionary *)photoDict error:(NSError *)error;

// video

- (void)visionDidStartVideoCapture:(PBJVision *)vision;
- (void)visionDidPauseVideoCapture:(PBJVision *)vision; // stopped but not ended
- (void)visionDidResumeVideoCapture:(PBJVision *)vision;
- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error;

// video capture progress

- (void)vision:(PBJVision *)vision didCaptureVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)vision:(PBJVision *)vision didCaptureAudioSample:(CMSampleBufferRef)sampleBuffer;

@end

//
//  PBJVisionTypes.h
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

#ifndef Vision_PBJVisionTypes_h
#define Vision_PBJVisionTypes_h

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

typedef NS_ENUM(NSInteger, PBJExposureMode) {
    PBJExposureModeLocked = AVCaptureExposureModeLocked,
    PBJExposureModeAutoExpose = AVCaptureExposureModeAutoExpose,
    PBJExposureModeContinuousAutoExposure = AVCaptureExposureModeContinuousAutoExposure
};

typedef NS_ENUM(NSInteger, PBJFlashMode) {
    PBJFlashModeOff  = AVCaptureFlashModeOff,
    PBJFlashModeOn   = AVCaptureFlashModeOn,
    PBJFlashModeAuto = AVCaptureFlashModeAuto
};

typedef NS_ENUM(NSInteger, PBJMirroringMode) {
	PBJMirroringAuto,
	PBJMirroringOn,
	PBJMirroringOff
};

typedef NS_ENUM(NSInteger, PBJAuthorizationStatus) {
    PBJAuthorizationStatusNotDetermined = 0,
    PBJAuthorizationStatusAuthorized,
    PBJAuthorizationStatusAudioDenied
};

typedef NS_ENUM(NSInteger, PBJOutputFormat) {
    PBJOutputFormatPreset = 0,
    PBJOutputFormatSquare,
    PBJOutputFormatWidescreen,
    PBJOutputFormatStandard /* 4:3 */
};

#endif

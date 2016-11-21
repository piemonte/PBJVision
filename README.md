![PBJVision](https://raw.githubusercontent.com/piemonte/PBJVision/master/pbj.gif)

## PBJVision

`PBJVision` is a camera library for iOS that enables easy integration of special capture features and camera interface customizations in your iOS app. [Next Level](https://github.com/NextLevel/NextLevel) is the Swift counterpart.

[![Build Status](https://api.travis-ci.org/piemonte/PBJVision.svg?branch=master)](https://travis-ci.org/piemonte/PBJVision)
[![Pod Version](https://img.shields.io/cocoapods/v/PBJVision.svg?style=flat)](http://cocoadocs.org/docsets/PBJVision/)

- Looking for a Swift version? Check out [Next Level](https://github.com/NextLevel/NextLevel).
- Looking for a video player? Check out [Player (Swift)](https://github.com/piemonte/player) and [PBJVideoPlayer (obj-c)](https://github.com/piemonte/PBJVideoPlayer).

### Features
- [x] touch-to-record video capture
- [x] slow motion capture (120 fps on [supported hardware](https://www.apple.com/iphone/compare/))
- [x] photo capture
- [x] customizable user interface and gestural interactions
- [x] ghosting (onion skinning) of last recorded segment
- [x] flash/torch support
- [x] white balance, focus, and exposure adjustment support
- [x] mirroring support

Capture is also possible without having to use the touch-to-record gesture interaction as the sample project provides.

### About

This library was originally created at [DIY](https://diy.org/) as a fun means for kids to author video and share their [skills](https://diy.org//skills). The touch-to-record interaction was pioneered by [Vine](https://vine.co/) and [Instagram](https://instagram.com/).

Thanks to everyone who has contributed and helped make this a fun project and community.

## Quick Start

`PBJVision` is available and recommended for installation using the dependency manager [CocoaPods](https://cocoapods.org/). 

To integrate, just add the following line to your `Podfile`:

```ruby
pod 'PBJVision'
```

## Usage

Import the header.

```objective-c
#import "PBJVision.h"
```

Setup the camera preview using `[[PBJVision sharedInstance] previewLayer]`.

```objective-c
    // preview and AV layer
    _previewView = [[UIView alloc] initWithFrame:CGRectZero];
    _previewView.backgroundColor = [UIColor blackColor];
    CGRect previewFrame = CGRectMake(0, 60.0f, CGRectGetWidth(self.view.frame), CGRectGetWidth(self.view.frame));
    _previewView.frame = previewFrame;
    _previewLayer = [[PBJVision sharedInstance] previewLayer];
    _previewLayer.frame = _previewView.bounds;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_previewView.layer addSublayer:_previewLayer];
```

If your view controller is managed by a Storyboard, keep the previewLayer updated for device sizes

```objective-c
- (void)viewDidLayoutSubviews
{
    _previewLayer.frame = _previewView.bounds;
}
```

Setup and configure the `PBJVision` controller, then start the camera preview.

```objective-c
- (void)_setup
{
    _longPressGestureRecognizer.enabled = YES;

    PBJVision *vision = [PBJVision sharedInstance];
    vision.delegate = self;
    vision.cameraMode = PBJCameraModeVideo;
    vision.cameraOrientation = PBJCameraOrientationPortrait;
    vision.focusMode = PBJFocusModeContinuousAutoFocus;
    vision.outputFormat = PBJOutputFormatSquare;

    [vision startPreview];
}
```

Start/pause/resume recording.

```objective-c
- (void)_handleLongPressGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state) {
      case UIGestureRecognizerStateBegan:
        {
            if (!_recording)
                [[PBJVision sharedInstance] startVideoCapture];
            else
                [[PBJVision sharedInstance] resumeVideoCapture];
            break;
        }
      case UIGestureRecognizerStateEnded:
      case UIGestureRecognizerStateCancelled:
      case UIGestureRecognizerStateFailed:
        {
            [[PBJVision sharedInstance] pauseVideoCapture];
            break;
        }
      default:
        break;
    }
}
```

End recording.

```objective-c
    [[PBJVision sharedInstance] endVideoCapture];
```

Handle the final video output or error accordingly.

```objective-c
- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error
{   
    if (error && [error.domain isEqual:PBJVisionErrorDomain] && error.code == PBJVisionErrorCancelled) {
        NSLog(@"recording session cancelled");
        return;
    } else if (error) {
        NSLog(@"encounted an error in video capture (%@)", error);
        return;
    }

    _currentVideo = videoDict;
    
    NSString *videoPath = [_currentVideo  objectForKey:PBJVisionVideoPathKey];
    [_assetLibrary writeVideoAtPathToSavedPhotosAlbum:[NSURL URLWithString:videoPath] completionBlock:^(NSURL *assetURL, NSError *error1) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Video Saved!" message: @"Saved to the camera roll."
                                                       delegate:self
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"OK", nil];
        [alert show];
    }];
}
```

To specify an automatic end capture maximum duration, set the following property on the 'PBJVision' controller.

```objective-c
    [[PBJVision sharedInstance] setMaximumCaptureDuration:CMTimeMakeWithSeconds(5, 600)]; // ~ 5 seconds
```

To adjust the video quality and compression bit rate, modify the following properties on the `PBJVision` controller.

```objective-c
    @property (nonatomic, copy) NSString *captureSessionPreset;

    @property (nonatomic) CGFloat videoBitRate;
    @property (nonatomic) NSInteger audioBitRate;
    @property (nonatomic) NSDictionary *additionalCompressionProperties;
```

## Community

Contributions and discussions are welcome!

### Project

- Need help? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/pbjvision) with the tag 'pbjvision'.
- Questions? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/pbjvision) with the tag 'pbjvision'.
- Found a bug? Open an [issue](https://github.com/piemonte/PBJVision/issues).
- Feature idea? Open an [issue](https://github.com/piemonte/PBJVision/issues).
- Want to contribute? Submit a [pull request](https://github.com/piemonte/PBJVision/blob/master/CONTRIBUTING.md).

### Related Projects

* [Next Level](https://github.com/NextLevel/NextLevel/), rad media capture in Swift
* [Player](https://github.com/piemonte/player), a simple iOS video player in Swift
* [PBJVideoPlayer](https://github.com/piemonte/PBJVideoPlayer), a simple iOS video player in Objective-C

## Resources

* [iOS Device Camera Summary](https://developer.apple.com/library/prerelease/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/Cameras/Cameras.html)
* [AV Foundation Programming Guide](https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/00_Introduction.html)
* [AV Foundation Framework Reference](https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVFoundationFramework/)
* [objc.io Camera and Photos](https://www.objc.io/issues/21-camera-and-photos/)
* [objc.io Video](https://www.objc.io/issues/23-video/)
* [Cameras, ecommerce and machine learning](http://ben-evans.com/benedictevans/2016/11/20/ku6omictaredoge4cao9cytspbz4jt)

## License

PBJVision is available under the MIT license, see the [LICENSE](https://github.com/piemonte/PBJVision/blob/master/LICENSE) file for more information.

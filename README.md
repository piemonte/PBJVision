![PBJVision](https://raw.github.com/piemonte/PBJVision/master/pbj.gif)

## PBJVision

`PBJVision` is an iOS camera engine that supports touch-to-record video, slow motion video (120 fps on [supported hardware](https://www.apple.com/iphone/compare/)), and photo capture. It is compatible with both iOS 7 and iOS 8 and is 64-bit ready. Pause and resume video capture is also possible without having to use a touch gesture as the sample project provides.

I created this library at [DIY](http://diy.org) as a fun means for kids to author video and share their skills. This same recording interaction was pioneered by [Vine](http://vine.co) and also adopted by [Instagram](http://instagram.com).

Please review the [release history](https://github.com/piemonte/PBJVision/releases) for a summary of the latest changes and more information. Contributions and help are welcome!

[![Build Status](https://travis-ci.org/piemonte/PBJVision.svg?branch=master)](https://travis-ci.org/piemonte/PBJVision)

## Installation

[CocoaPods](http://cocoapods.org) is the recommended method of installing PBJVision, just add the following line to your `Podfile`:

```ruby
pod 'PBJVision'
```

## Usage
```objective-c
#import "PBJVision.h"
```

```objective-c
- (void)_setup
{
    _longPressGestureRecognizer.enabled = YES;

    PBJVision *vision = [PBJVision sharedInstance];
    vision.delegate = self;
    [vision setCameraMode:PBJCameraModeVideo];
    [vision setCameraDevice:PBJCameraDeviceBack];
    [vision setCameraOrientation:PBJCameraOrientationPortrait];
    [vision setFocusMode:PBJFocusModeAutoFocus];

    [vision startPreview];
}
```

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

```objective-c
- (void)_handleDoneButton:(UIButton *)button
{
    [self _endCapture];
}
```

```objective-c
- (void)vision:(PBJVision *)vision capturedVideo:(NSDictionary *)videoDict error:(NSError *)error
{   
    NSString *videoPath = [_currentVideo  objectForKey:PBJVisionVideoPathKey];
    [_assetLibrary writeVideoAtPathToSavedPhotosAlbum:[NSURL URLWithString:videoPath] completionBlock:^(NSURL *assetURL, NSError *error1) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Saved!" message: @"Saved to the camera roll."
                                                       delegate:self
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"OK", nil];
        [alert show];
    }];
}
```

## Community

- Need help? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/pbjvision) with the tag 'pbjvision'.
- Questions? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/pbjvision) with the tag 'pbjvision'.
- Found a bug? Open an [issue](https://github.com/piemonte/PBJVision/issues).
- Feature idea? Open an [issue](https://github.com/piemonte/PBJVision/issues).
- Want to contribute? Submit a [pull request](https://github.com/piemonte/PBJVision/blob/master/CONTRIBUTING.md).

## Resources

* [AV Foundation Programming Guide](https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/00_Introduction.html)
* [PBJVideoPlayer, a simple iOS video player](https://github.com/piemonte/PBJVideoPlayer)

## License

PBJVision is available under the MIT license, see the [LICENSE](https://github.com/piemonte/PBJVision/blob/master/LICENSE) file for more information.

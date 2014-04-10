![PBJVision](https://raw.github.com/piemonte/PBJVision/master/pbj.gif)

## PBJVision

'PBJVision' is an iOS camera engine that supports touch-to-record video, slow motion video (120 fps), and photo capture. It is compatible with both iOS 6 and iOS 7 and supports 64-bit. Pause and resume video capture is also possible without having to use a touch gesture as the sample project provides.

I created this component at [DIY.org](http://diy.org) as a fun means for young people to author video. This same recording interaction was pioneered by [Vine](http://vine.co) and also later adopted by [Instagram](http://instagram.com).

If you need a video player, check out [PBJVideoPlayer](https://github.com/piemonte/PBJVideoPlayer).

Please review the [release history](https://github.com/piemonte/PBJVision/releases) for more information.

If you have questions or ideas, let me know! Project contributions, ideas, and collaborations are all welcome. The [github issues page](https://github.com/piemonte/PBJVision/issues) is a great place to start a discussion and allows others to benefit and chime-in on the project too.

## Installation

[CocoaPods](http://cocoapods.org) is the recommended method of installing PBJVision, just add the following line to your `Podfile`:

#### Podfile

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

## License

PBJVision is available under the MIT license, see the [LICENSE](https://github.com/piemonte/PBJVision/blob/master/LICENSE) file for more information.

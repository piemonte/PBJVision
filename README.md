![PBJVision](https://raw.github.com/piemonte/PBJVision/master/pbj.gif)

## PBJVision
'PBJVision' is an iOS camera engine that supports touch-to-record video and photo capture. It is compatible both iOS 6 and iOS 7 as well as 64-bit. Pause and resume video capture is also possible without having to use a gesture like the sample project provides.

We created this at [DIY](http://www.diy.org) as a fun means for young people to author video. This same recording interaction was pioneered by Vine and also later adopted by Instagram.

Please review the [release history](https://github.com/piemonte/PBJVision/releases) for more information. If you need a video player, check out [PBJVideoPlayer](https://github.com/piemonte/PBJVideoPlayer).

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

PBJVision is available under the MIT license, see the LICENSE file for more information.


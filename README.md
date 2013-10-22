![PBJVision](https://raw.github.com/piemonte/PBJVision/master/pbj.gif)

## PBJVision
'PBJVision' is an iOS camera engine that supports touch-to-record video and photo capture.

It supports both iOS 6 and iOS 7 as well as 64-bit.

We created this at DIY.org as a fun means for kids to author video but also as a way to easily create stop motion. This same recording interaction was pioneered by Vine and later by Instagram.

## Release History

v0.1.2 addition of onion skinning (ghosting), http://en.wikipedia.org/wiki/Onion_skinning

v0.1.1 minor bug fixes

v0.1.0 initial release of touch-to-record video

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


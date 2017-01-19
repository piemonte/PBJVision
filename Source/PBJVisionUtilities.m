//
//  PBJVisionUtilities.m
//  PBJVision
//
//  Created by Patrick Piemonte on 5/20/13.
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

#import "PBJVisionUtilities.h"
#import "PBJVision.h"

#import <ImageIO/ImageIO.h>

@implementation PBJVisionUtilities

+ (AVCaptureDevice *)captureDeviceForPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    
    return nil;
}

+ (AVCaptureDevice *)audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
        return [devices objectAtIndex:0];
    
    return nil;
}

+ (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections
{
    for ( AVCaptureConnection *connection in connections ) {
        for ( AVCaptureInputPort *port in [connection inputPorts] ) {
            if ( [[port mediaType] isEqual:mediaType] ) {
                return connection;
            }
        }
    }
    
    return nil;
}

+ (CMSampleBufferRef)createOffsetSampleBufferWithSampleBuffer:(CMSampleBufferRef)sampleBuffer withTimeOffset:(CMTime)timeOffset
{
    CMItemCount itemCount;
    
    OSStatus status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, NULL, &itemCount);
    if (status) {
        return NULL;
    }
    
    CMSampleTimingInfo *timingInfo = (CMSampleTimingInfo *)malloc(sizeof(CMSampleTimingInfo) * (unsigned long)itemCount);
    if (!timingInfo) {
        return NULL;
    }
    
    status = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, itemCount, timingInfo, &itemCount);
    if (status) {
        free(timingInfo);
        timingInfo = NULL;
        return NULL;
    }
    
    for (CMItemCount i = 0; i < itemCount; i++) {
        timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, timeOffset);
        timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, timeOffset);
    }
    
    CMSampleBufferRef offsetSampleBuffer;
    CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, itemCount, timingInfo, &offsetSampleBuffer);
    
    if (timingInfo) {
        free(timingInfo);
        timingInfo = NULL;
    }
    
    return offsetSampleBuffer;
}

+ (UIImage *)uiimageFromJPEGData:(NSData *)jpegData
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
                        imageOrientation = [PBJVisionUtilities uiimageOrientationFromExifOrientation:exifOrientation];
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

// http://sylvana.net/jpegcrop/exif_orientation.html
+ (UIImageOrientation)uiimageOrientationFromExifOrientation:(NSInteger)exifOrientation
{
    UIImageOrientation imageOrientation = UIImageOrientationUp;
    
    switch (exifOrientation) {
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
        case 1:
        default:
            // UIImageOrientationUp;
            break;
    }
    
    return imageOrientation;
}

+ (CGFloat)angleOffsetFromPortraitOrientationToOrientation:(AVCaptureVideoOrientation)orientation
{
    CGFloat angle = 0.0;
    
    switch (orientation) {
        case AVCaptureVideoOrientationPortraitUpsideDown:
            angle = (CGFloat)M_PI;
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            angle = (CGFloat)-M_PI_2;
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            angle = (CGFloat)M_PI_2;
            break;
        case AVCaptureVideoOrientationPortrait:
        default:
            break;
    }

    return angle;
}

#pragma mark - memory

+ (uint64_t)availableStorageSpaceInBytes
{
    uint64_t freeSize = 0;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    
    __autoreleasing NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error:&error];
    if (attributes) {
        NSNumber *freeFileSystemSizeInBytes = attributes[NSFileSystemFreeSize];
        if (freeFileSystemSizeInBytes) {
            freeSize = [freeFileSystemSizeInBytes unsignedLongLongValue];
        }
    }
    
    return freeSize;
}

@end

#pragma mark - NSString Extras

@implementation NSString (PBJExtras)

+ (NSString *)PBJformattedTimestampStringFromDate:(NSDate *)date
{
    if (!date)
        return nil;
    
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'"];
        [dateFormatter setLocale:[NSLocale autoupdatingCurrentLocale]];
    });
    
    return [dateFormatter stringFromDate:date];
}

@end


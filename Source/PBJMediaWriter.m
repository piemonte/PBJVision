//
//  PBJMediaWriter.m
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
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

#import "PBJMediaWriter.h"
#import "PBJVisionUtilities.h"

#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

#define LOG_WRITER 0
#if !defined(NDEBUG) && LOG_WRITER
#   define DLog(fmt, ...) NSLog((@"writer: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

@interface PBJMediaWriter ()
{
    AVAssetWriter *_assetWriter;
	AVAssetWriterInput *_assetWriterAudioIn;
	AVAssetWriterInput *_assetWriterVideoIn;
    
    NSURL *_outputURL;
    
    CMTime _audioTimestamp;
    CMTime _videoTimestamp;
    
    BOOL _audioReady;
    BOOL _videoReady;
}

@end

@implementation PBJMediaWriter

@synthesize outputURL = _outputURL;
@synthesize delegate = _delegate;

@synthesize audioTimestamp = _audioTimestamp;
@synthesize videoTimestamp = _videoTimestamp;

#pragma mark - getters/setters

- (BOOL)isAudioReady
{
    return _audioReady;
}

- (BOOL)isVideoReady
{
    return _videoReady;
}

- (NSError *)error
{
    return _assetWriter.error;
}

#pragma mark - init

- (id)initWithOutputURL:(NSURL *)outputURL
{
    self = [super init];
    if (self) {
        NSError *error = nil;
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputURL fileType:(NSString *)kUTTypeMPEG4 error:&error];
        if (error) {
            DLog(@"error setting up the asset writer (%@)", error);
            _assetWriter = nil;
            return nil;
        }

        _outputURL = outputURL;
        _assetWriter.shouldOptimizeForNetworkUse = YES;
        _assetWriter.metadata = [self _metadataArray];

        _audioTimestamp = kCMTimeInvalid;
        _videoTimestamp = kCMTimeInvalid;

        // It's possible to capture video without audio or audio without video.
        // If the user has denied access to a device, or hasn't even been asked, we don't need to set it up
        if ([[AVCaptureDevice class] respondsToSelector:@selector(authorizationStatusForMediaType:)]) {
            AVAuthorizationStatus audioAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
            
            if (audioAuthorizationStatus == AVAuthorizationStatusNotDetermined || audioAuthorizationStatus == AVAuthorizationStatusDenied) {
                _audioReady = YES;
                if (audioAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveAudioAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveAudioAuthorizationStatusDenied:self];
                }
            }
            
            AVAuthorizationStatus videoAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            
            if (videoAuthorizationStatus == AVAuthorizationStatusNotDetermined || videoAuthorizationStatus == AVAuthorizationStatusDenied) {
                _videoReady = YES;
                if (videoAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveVideoAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveVideoAuthorizationStatusDenied:self];
                }
            }
            
        }
    }
    return self;
}

#pragma mark - private

- (NSArray *)_metadataArray
{
    UIDevice *currentDevice = [UIDevice currentDevice];
    
    // device model
    AVMutableMetadataItem *modelItem = [[AVMutableMetadataItem alloc] init];
    [modelItem setKeySpace:AVMetadataKeySpaceCommon];
    [modelItem setKey:AVMetadataCommonKeyModel];
    [modelItem setValue:[currentDevice localizedModel]];

    // software
    AVMutableMetadataItem *softwareItem = [[AVMutableMetadataItem alloc] init];
    [softwareItem setKeySpace:AVMetadataKeySpaceCommon];
    [softwareItem setKey:AVMetadataCommonKeySoftware];
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *softwareName = [NSString stringWithFormat:@"%@ %@ PBJVision %@ %@", [currentDevice systemName], [currentDevice systemVersion], appName, appVersion];
    [softwareItem setValue:softwareName];

    // creation date
    AVMutableMetadataItem *creationDateItem = [[AVMutableMetadataItem alloc] init];
    [creationDateItem setKeySpace:AVMetadataKeySpaceCommon];
    [creationDateItem setKey:AVMetadataCommonKeyCreationDate];
    [creationDateItem setValue:[NSString PBJformattedTimestampStringFromDate:[NSDate date]]];

    return @[modelItem, softwareItem, creationDateItem];
}

#pragma mark - sample buffer setup

- (BOOL)setupAudioOutputDeviceWithSettings:(NSDictionary *)audioSettings
{
	if ([_assetWriter canApplyOutputSettings:audioSettings forMediaType:AVMediaTypeAudio]) {
    
		_assetWriterAudioIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
		_assetWriterAudioIn.expectsMediaDataInRealTime = YES;
        
        DLog(@"prepared audio-in with compression settings sampleRate (%f) channels (%lu) bitRate (%ld)",
                    [[audioSettings objectForKey:AVSampleRateKey] floatValue],
                    (unsigned long)[[audioSettings objectForKey:AVNumberOfChannelsKey] unsignedIntegerValue],
                    (long)[[audioSettings objectForKey:AVEncoderBitRateKey] integerValue]);
        
		if ([_assetWriter canAddInput:_assetWriterAudioIn]) {
			[_assetWriter addInput:_assetWriterAudioIn];
            _audioReady = YES;
		} else {
			DLog(@"couldn't add asset writer audio input");
		}
        
	} else {
    
		DLog(@"couldn't apply audio output settings");
        
	}
    
    return _audioReady;
}

- (BOOL)setupVideoOutputDeviceWithSettings:(NSDictionary *)videoSettings
{
	if ([_assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
    
		_assetWriterVideoIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
		_assetWriterVideoIn.expectsMediaDataInRealTime = YES;
		_assetWriterVideoIn.transform = CGAffineTransformIdentity;

#if !defined(NDEBUG) && LOG_WRITER
        NSDictionary *videoCompressionProperties = [videoSettings objectForKey:AVVideoCompressionPropertiesKey];
        if (videoCompressionProperties)
            DLog(@"prepared video-in with compression settings bps (%f) frameInterval (%ld)",
                    [[videoCompressionProperties objectForKey:AVVideoAverageBitRateKey] floatValue],
                    (long)[[videoCompressionProperties objectForKey:AVVideoMaxKeyFrameIntervalKey] integerValue]);
#endif

		if ([_assetWriter canAddInput:_assetWriterVideoIn]) {
			[_assetWriter addInput:_assetWriterVideoIn];
            _videoReady = YES;
		} else {
			DLog(@"couldn't add asset writer video input");
		}
        
	} else {
    
		DLog(@"couldn't apply video output settings");
        
	}
    
    return _videoReady;
}

#pragma mark - sample buffer writing

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
	if ( _assetWriter.status == AVAssetWriterStatusUnknown ) {
    
        if ([_assetWriter startWriting]) {
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
			[_assetWriter startSessionAtSourceTime:startTime];
            DLog(@"started writing with status (%ld)", (long)_assetWriter.status);
		} else {
			DLog(@"error when starting to write (%@)", [_assetWriter error]);
		}
        
	}
    
    if ( _assetWriter.status == AVAssetWriterStatusFailed ) {
        DLog(@"writer failure, (%@)", _assetWriter.error.localizedDescription);
        return;
    }
	
	if ( _assetWriter.status == AVAssetWriterStatusWriting ) {
		
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
		if (mediaType == AVMediaTypeVideo) {
			if (_assetWriterVideoIn.readyForMoreMediaData) {
				if ([_assetWriterVideoIn appendSampleBuffer:sampleBuffer]) {
                    _videoTimestamp = timestamp;
				} else {
					DLog(@"writer error appending video (%@)", [_assetWriter error]);
                }
			}
		} else if (mediaType == AVMediaTypeAudio) {
			_audioTimestamp = timestamp;
			if (_assetWriterAudioIn.readyForMoreMediaData) {
				if ([_assetWriterAudioIn appendSampleBuffer:sampleBuffer])
				else 
					DLog(@"writer error appending audio (%@)", [_assetWriter error]);
                
			}
		}
        
	}
    
}

- (void)finishWritingWithCompletionHandler:(void (^)(void))handler
{
    if (_assetWriter.status == AVAssetWriterStatusUnknown) {
        DLog(@"asset writer is in an unknown state, wasn't recording");
        return;
    }

    [_assetWriter finishWritingWithCompletionHandler:handler];
    
    _audioReady = NO;
    _videoReady = NO;    
}


@end

//
//  PBJVideoWriter.m
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
//  Copyright (c) 2014 Patrick Piemonte. All rights reserved.
//

#import "PBJVideoWriter.h"
#import "PBJVisionUtilities.h"

#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

#define LOG_WRITER 0
#if !defined(NDEBUG) && LOG_WRITER
#   define DLog(fmt, ...) NSLog((@"writer: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

@interface PBJVideoWriter ()
{
    AVAssetWriter *_assetWriter;
	AVAssetWriterInput *_assetWriterAudioIn;
	AVAssetWriterInput *_assetWriterVideoIn;
    
    NSURL *_outputURL;
}

@end

@implementation PBJVideoWriter

@synthesize outputURL = _outputURL;

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
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputURL fileType:(NSString *)kUTTypeQuickTimeMovie error:&error];
        if (error) {
            DLog(@"error setting up the asset writer (%@)", error);
            _assetWriter = nil;
            return nil;
        }

        _outputURL = outputURL;
        _assetWriter.shouldOptimizeForNetworkUse = YES;
        _assetWriter.metadata = [self _metadataArray];
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
    [softwareItem setValue:[NSString stringWithFormat:@"%@ %@ PBJVision", [currentDevice systemName], [currentDevice systemVersion]]];

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
        
        DLog(@"prepared audio-in with compression settings sampleRate (%f) channels (%d) bitRate (%ld)",
                    [[audioSettings objectForKey:AVSampleRateKey] floatValue],
                    [[audioSettings objectForKey:AVNumberOfChannelsKey] unsignedIntegerValue],
                    (long)[[audioSettings objectForKey:AVEncoderBitRateKey] integerValue]);
        
		if ([_assetWriter canAddInput:_assetWriterAudioIn]) {
			[_assetWriter addInput:_assetWriterAudioIn];
		} else {
			DLog(@"couldn't add asset writer audio input");
            return NO;
		}
        
	} else {
    
		DLog(@"couldn't apply audio output settings");
        return NO;
        
	}
    
    return YES;
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
		} else {
			DLog(@"couldn't add asset writer video input");
            return NO;
		}
        
	} else {
    
		DLog(@"couldn't apply video output settings");
        return NO;
        
	}
    
    return YES;
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
		
		if (mediaType == AVMediaTypeVideo) {
			if (_assetWriterVideoIn.readyForMoreMediaData) {
				if (![_assetWriterVideoIn appendSampleBuffer:sampleBuffer]) {
					DLog(@"writer error appending video (%@)", [_assetWriter error]);
				}
			}
		} else if (mediaType == AVMediaTypeAudio) {
			if (_assetWriterAudioIn.readyForMoreMediaData) {
				if (![_assetWriterAudioIn appendSampleBuffer:sampleBuffer]) {
					DLog(@"writer error appending audio (%@)", [_assetWriter error]);
				}
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
    
// _assetWriterAudioIn = nil;
// _assetWriterVideoIn = nil;

}


@end

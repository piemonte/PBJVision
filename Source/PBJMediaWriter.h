//
//  PBJMediaWriter.h
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
//  Copyright (c) 2014 Patrick Piemonte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol PBJMediaWriterDelegate;
@interface PBJMediaWriter : NSObject

- (id)initWithOutputURL:(NSURL *)outputURL;

@property (nonatomic, weak) id<PBJMediaWriterDelegate> delegate;

@property (nonatomic, readonly) NSURL *outputURL;
@property (nonatomic, readonly) NSError *error;

// setup output devices before writing

@property (nonatomic, readonly, getter=isAudioReady) BOOL audioReady;
@property (nonatomic, readonly, getter=isVideoReady) BOOL videoReady;

- (BOOL)setupAudioOutputDeviceWithSettings:(NSDictionary *)audioSettings;
- (BOOL)setupVideoOutputDeviceWithSettings:(NSDictionary *)videoSettings;

// write

@property (nonatomic, readonly) CMTime audioTimestamp;
@property (nonatomic, readonly) CMTime videoTimestamp;

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType;
- (void)finishWritingWithCompletionHandler:(void (^)(void))handler;

@end

@protocol PBJMediaWriterDelegate <NSObject>
@optional
// authorization status provides the opportunity to prompt the user for allowing capture device access
- (void)mediaWriterDidObserveAudioAuthorizationStatusDenied:(PBJMediaWriter *)mediaWriter;
- (void)mediaWriterDidObserveVideoAuthorizationStatusDenied:(PBJMediaWriter *)mediaWriter;

@end

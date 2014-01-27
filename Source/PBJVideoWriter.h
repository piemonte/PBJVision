//
//  PBJVideoWriter.h
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
//  Copyright (c) 2014 Patrick Piemonte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface PBJVideoWriter : NSObject

- (id)initWithOutputURL:(NSURL *)outputURL;

@property (nonatomic, readonly) NSURL *outputURL;
@property (nonatomic, readonly) NSError *error;

// setup output devices before writing

- (BOOL)setupAudioOutputDeviceWithSettings:(NSDictionary *)audioSettings;
- (BOOL)setupVideoOutputDeviceWithSettings:(NSDictionary *)videoSettings;

// write

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType;
- (void)finishWritingWithCompletionHandler:(void (^)(void))handler;

@end

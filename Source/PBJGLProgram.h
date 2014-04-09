//
//  PBJGLProgram.h
//  Vision
//
//  Created by Patrick Piemonte on 4/9/14.
//  Copyright (c) 2014 Patrick Piemonte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface PBJGLProgram : NSObject

- (id)initWithVertexShaderName:(NSString *)vertexShaderName fragmentShaderName:(NSString *)fragmentShaderName;

- (void)addAttribute:(NSString *)attributeName;
- (GLuint)attributeIndex:(NSString *)attributeName;

- (int)uniformLocation:(NSString *)uniformName;

- (BOOL)link;
- (void)use;

@end

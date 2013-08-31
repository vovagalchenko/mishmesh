//
//  MSHVertex.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

#define X   0
#define Y   1
#define Z   2

@interface MSHVertex : NSObject

+ (MSHVertex *)vertexWithX:(GLfloat)x
                         y:(GLfloat)y
                         z:(GLfloat)z;
- (void)addNormalWithNormalId:(id)normalId suggestedIndex:(unsigned int *)suggestedIndex;
- (GLfloat)distanceToVertex:(MSHVertex *)otherVertex;
- (NSArray *)calculateNormalForTriangleFormedWithVertex2:(MSHVertex *)vertex2 andVertex3:(MSHVertex *)vertex3;
- (BOOL)usesNormalAveraging;
- (GLKVector3)addNormalToAverage:(NSArray *)normal;

@property (nonatomic, assign) GLKVector3 position;

@end


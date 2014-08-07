//
//  MSHFile.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MSHRange.h"
#import "MSHParser.h"
#import "MSHFace.h"
#import "MSHFileTypeHint.h"

typedef enum MSHFileStatus
{
    MSHFileStatusUnknown,
    MSHFileStatusParsingVertices,
    MSHFileStatusParsingVertexNormals,
    MSHFileStatusParsingFaces,
    MSHFileStatusCalibrating,
    MSHFileStatusReady,
    MSHFileStatusFailure,
} MSHFileStatus;

@class MSHVertex;

@interface MSHFile : NSObject

- (id)initWithURL:(NSURL *)url fileTypeHint:(MSHFileTypeHint)fileTypeHint;
- (void)parseWithStatusUpdateBlock:(void (^)(MSHFile *))statusUpdateBlock;

@property (nonatomic, readonly) GLfloat *vertexCoordinates;
@property (nonatomic, readonly) GLsizeiptr vertexCoordinatesSize;
@property (nonatomic, readonly) GLuint *vertexIndices;
@property (nonatomic, readonly) GLsizeiptr vertexIndicesSize;
@property (nonatomic, readonly) GLubyte *numVerticesInFace; // The caller will need to free this space
@property (nonatomic, readonly) unsigned int numFaces;
@property (nonatomic, readonly) MSHVertex *outlierVertex;
@property (nonatomic, readonly) MSHRange xRange, yRange, zRange;
@property (nonatomic, readonly) MSHFileStatus status;
@property (nonatomic, readonly) NSError *processingError;

@end

@protocol MSHFileDelegate <NSObject>

- (void)file:(MSHFile *)file statusChanged:(MSHFileStatus)newStatus;

@end

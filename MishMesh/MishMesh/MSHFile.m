//
//  MSHFile.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHFile.h"
#import "MSHVertex.h"

@interface MSHFile()

@property (nonatomic, readwrite, strong) NSURL *localURL;
@property (nonatomic, readwrite, strong) MSHVertex *outlierVertex;
@property (nonatomic, readwrite, assign) MSHFileStatus status;
@property (nonatomic, readwrite, strong) void (^onStatusUpdateBlock)(MSHFile *);
@property (nonatomic, readwrite, strong) NSError *processingError;

@end

@implementation MSHFile

- (id)initWithURL:(NSURL *)url
{
    if (self = [super init])
    {
        NSAssert([[NSFileManager defaultManager] fileExistsAtPath:[url path]], @"File doesn't exist at the provided path.");
        self.localURL = url;
    }
    return self;
}

- (void)parseWithStatusUpdateBlock:(void (^)(MSHFile *))statusUpdateBlock
{
    NSAssert(self.localURL, @"Must have the file locally in order to parse it.");
    self.onStatusUpdateBlock = statusUpdateBlock;
    if (self.vertexCoordinates)
    {
        self.status = MSHParsingStageComplete;
    }
    else
    {
        MSHParser *parser = [[MSHParser alloc] initWithFileURL:self.localURL];
        [parser parseFileWithStatusChangeBlock:^(MSHParser *changedParser)
         {
             switch (changedParser.parserStage)
             {
                 case MSHParsingStageError:
                     self.processingError = changedParser.parseError;
                     self.status = MSHFileStatusFailure;
                     break;
                 case MSHParsingStageComplete:
                 {
                     self.status = MSHFileStatusCalibrating;
                     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
                    {
                        _numFaces = changedParser.faces.count;
                        _numVerticesInFace = malloc(sizeof(GLubyte)*_numFaces);
                        MSHFace face;
                        int i = 0;
                        int numIndices = 0;
                        for (NSValue *faceValue in changedParser.faces)
                        {
                            [faceValue getValue:&face];
                            _numVerticesInFace[i++] = face.numVertices;
                            numIndices += face.numVertices;
                        }
                        if (numIndices)
                        {
                            _vertexIndicesSize = sizeof(GLushort)*numIndices;
                            _vertexIndices = malloc(_vertexIndicesSize);
                        }
                        i = 0;
                        for (int faceIndex = 0; faceIndex < _numFaces; faceIndex++)
                        {
                            [[changedParser.faces objectAtIndex:faceIndex] getValue:&face];
                            for (int j = 0; j < _numVerticesInFace[faceIndex]; j++)
                            {
                                _vertexIndices[i++] = face.vertexIndices[j];
                            }
                        }
                        _vertexCoordinatesSize = changedParser.vertexCoordinates.count*sizeof(GLfloat);
                        _vertexCoordinates = malloc(_vertexCoordinatesSize);
                        i = 0;
                        for (NSNumber *floatNumber in changedParser.vertexCoordinates)
                        {
                            _vertexCoordinates[i++] = [floatNumber floatValue];
                        }
                        MSHVertex *centerVertex = [MSHVertex vertexWithX:getMidpoint(changedParser.xRange) y:getMidpoint(changedParser.yRange) z:getMidpoint(changedParser.zRange)];
                        GLfloat maxDistance = 0;
                        MSHVertex *outlier;
                        for (int i = 0; i < changedParser.faces.count; i++)
                        {
                            MSHFace face;
                            [[changedParser.faces objectAtIndex:i] getValue:&face];
                            for (int j = 0; j < face.numVertices; j++)
                            {
                                unsigned int verticeStartIndex = face.vertexIndices[j]*6;
                                MSHVertex *vertex = [MSHVertex vertexWithX:self.vertexCoordinates[verticeStartIndex]
                                                                         y:self.vertexCoordinates[verticeStartIndex + 1]
                                                                         z:self.vertexCoordinates[verticeStartIndex + 2]];
                                GLfloat distance = [centerVertex distanceToVertex:vertex];
                                if (distance > maxDistance)
                                {
                                    maxDistance = distance;
                                    outlier = vertex;
                                }
                            }
                        }
                        _xRange = changedParser.xRange;
                        _yRange = changedParser.yRange;
                        _zRange = changedParser.zRange;
                        self.outlierVertex = outlier;
                        self.status = MSHFileStatusReady;
                    });
                 }
                    break;
                 case MSHParsingStageVertices:
                     self.status = MSHFileStatusParsingVertices;
                     break;
                 case MSHParsingStageVertexNormals:
                     self.status = MSHFileStatusParsingVertexNormals;
                     break;
                 case MSHParsingStageFaces:
                     self.status = MSHFileStatusParsingFaces;
                     break;
                 default:
                     self.status = MSHFileStatusUnknown;
                     break;
             }
         }];
    }
}

- (void)setStatus:(MSHFileStatus)status
{
    BOOL needToNotify = _status != status;
    _status = status;
    if (needToNotify && self.onStatusUpdateBlock)
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            __weak MSHFile *me = self;
            self.onStatusUpdateBlock(me);
        });
    }
}

- (void)dealloc
{
    free(_vertexCoordinates);
    free(_vertexIndices);
}


@end

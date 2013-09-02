//
//  MSHParser.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MSHRange.h"

#define ERROR_DOMAIN_NAME       @"MSHParseError"
#define MAX_NUM_VERTICES        USHRT_MAX

typedef enum MSHParseError
{
    MSHParseErrorFileTypeUnsupported,
    MSHParseErrorUnableToOpenFile,
    MSHParseErrorFileIOFailure,
    MSHParseErrorInvalidVertexDefinition,
    MSHParseErrorInvalidNormalDefinition,
    MSHParseErrorInvalidFaceDefinition,
    MSHParseErrorVertexNumberLimitExceeded,
    MSHParseErrorNoGeometry,
    MSHParseErrorUnknown
} MSHParseError;

typedef enum MSHParsingStage
{
    MSHParsingStageUnknown,
    MSHParsingStageVertices,
    MSHParsingStageVertexNormals,
    MSHParsingStageFaces,
    MSHParsingStageComplete,
    MSHParsingStageError,
} MSHParsingStage;

@class MSHVertex;

@interface MSHParser : NSObject

- (id)initWithFileURL:(NSURL *)fileURL;
- (void)parseFileWithStatusChangeBlock:(void (^)(MSHParser *parser))completion;
- (NSError *)errorWithMessage:(NSString *)msg errorCode:(MSHParseError)errCode;

@property (nonatomic, readonly) MSHParsingStage parserStage;
@property (nonatomic, readonly) MSHRange xRange, yRange, zRange;
@property (nonatomic, readonly) NSError *parseError;
@property (nonatomic, readonly) NSArray *vertexCoordinates;
@property (nonatomic, readonly) NSArray *faces;

@end
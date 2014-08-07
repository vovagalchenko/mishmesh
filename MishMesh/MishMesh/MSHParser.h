//
//  MSHParser.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MSHRange.h"
#import "MSHFileTypeHint.h"
#import "MSHParseError.h"

#define MAX_NUM_VERTICES        UINT_MAX

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

- (id)initWithFileURL:(NSURL *)fileURL fileTypeHint:(MSHFileTypeHint)fileTypeHint;
- (void)parseFileWithStatusChangeBlock:(void (^)(MSHParser *parser))completion;
- (NSError *)errorWithMessage:(NSString *)msg errorCode:(MSHParseError)errCode;

@property (nonatomic, readonly) MSHParsingStage parserStage;
@property (nonatomic, readonly) MSHRange xRange, yRange, zRange;
@property (nonatomic, readonly) NSError *parseError;
@property (nonatomic, readonly) NSArray *vertexCoordinates;
@property (nonatomic, readonly) NSArray *faces;

@end
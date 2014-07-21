//
//  MSHObjParser.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHObjParser.h"
#import "MSHVertex.h"
#import "MSHFace.h"
#import "MSHParser_InternallyWritableProperties.h"

#define DISK_IO_CHUNK_SIZE      1<<17

@implementation MSHObjParser

- (id)initWithFileURL:(NSURL *)fileURL fileTypeHint:(MSHFileTypeHint)fileTypeHint
{
    if (self = [super init])
    {
        self.fileURL = fileURL;
        self.parserStage = MSHParsingStageUnknown;
    }
    return self;
}

- (void)parseFileWithStatusChangeBlock:(void (^)(MSHParser *parser))statusChangeUpdate
{
    NSAssert(self.fileURL && statusChangeUpdate, @"Did not submit enough to the parser.");
    self.onStatusUpdateBlock = statusChangeUpdate;
    // Don't want to use a weak version of self in the block below. Need self to stick around until the block is done.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        MSHRange outXRange = makeExtremeRange();
        MSHRange outYRange = makeExtremeRange();
        MSHRange outZRange = makeExtremeRange();
        NSMutableArray *faces = [NSMutableArray array];
        NSMutableArray *vertices = [NSMutableArray array];
        NSMutableArray *tmpVertices = [[NSMutableArray alloc] init];
        NSMutableArray *tmpNormals = [[NSMutableArray alloc] init];
        
        NSError *error = nil;
        size_t chunkSize = DISK_IO_CHUNK_SIZE;
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:self.fileURL error:&error];
        if (!fileHandle || error)
        {
            self.parseError = error;
            self.parserStage = MSHParsingStageError;
            return;
        }

        NSString *partialLine = @"";
        NSData *fileData = nil;
        do
        {
            @autoreleasepool
            {
                fileData = [fileHandle readDataOfLength:chunkSize];
                NSString *ingestedString = [[NSString alloc] initWithBytes:fileData.bytes length:fileData.length encoding:NSUTF8StringEncoding];
                NSMutableArray *ingestedLines = [NSMutableArray arrayWithArray:[ingestedString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
                ingestedString = nil;
                [ingestedLines replaceObjectAtIndex:0 withObject:[partialLine stringByAppendingString:[ingestedLines objectAtIndex:0]]];
                if (fileData.length >= chunkSize)
                {
                    partialLine = [ingestedLines lastObject];
                    [ingestedLines removeLastObject];
                }
                for (NSString *line in ingestedLines)
                {
                    NSArray *definitionComponents = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    definitionComponents = [definitionComponents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings)
                                                                                              {
                                                                                                  return ((NSString *)evaluatedObject).length > 0;
                                                                                              }]];
                    if (definitionComponents.count)
                    {
                        NSString *typeOfDefinition = [definitionComponents objectAtIndex:0];
                        switch ([typeOfDefinition characterAtIndex:0])
                        {
                            case 'v':
                                if (typeOfDefinition.length == 1)
                                {
                                    // This is a vertex definition
                                    self.parserStage = MSHParsingStageVertices;
                                    if (definitionComponents.count != 4)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Error parsing a vertex: %@", line]
                                                                       errorCode:MSHParseErrorInvalidVertexDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    GLfloat x = [[definitionComponents objectAtIndex:1] floatValue];
                                    GLfloat y = [[definitionComponents objectAtIndex:2] floatValue];
                                    GLfloat z = [[definitionComponents objectAtIndex:3] floatValue];
                                    
                                    amendRange(&outXRange, x);
                                    amendRange(&outYRange, y);
                                    amendRange(&outZRange, z);
                                    [tmpVertices addObject:[MSHVertex vertexWithX:x
                                                                                y:y
                                                                                z:z]];
                                    if (tmpVertices.count > MAX_NUM_VERTICES)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"This model exceeds the maximum number of vertices: %d", MAX_NUM_VERTICES]
                                                                       errorCode:MSHParseErrorVertexNumberLimitExceeded];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                }
                                else if ([typeOfDefinition characterAtIndex:1] == 'n')
                                {
                                    // This is a normal definition
                                    self.parserStage = MSHParsingStageVertexNormals;
                                    if (definitionComponents.count != 4)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Error parsing a normal: %@", line]
                                                                       errorCode:MSHParseErrorInvalidNormalDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    [tmpNormals addObject:[NSArray arrayWithObjects:[definitionComponents objectAtIndex:1],
                                                           [definitionComponents objectAtIndex:2],
                                                           [definitionComponents objectAtIndex:3], nil]];
                                }
                                break;
                            case 'f':
                            {
                                // This is a face definition
                                self.parserStage = MSHParsingStageFaces;
                                if (definitionComponents.count < 4)
                                {
                                    self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Unexpected number of definition components for face: %@", line]
                                                                   errorCode:MSHParseErrorInvalidFaceDefinition];
                                    self.parserStage = MSHParsingStageError;
                                    return;
                                }
                                MSHFace face = MSHFaceMake((unsigned int) definitionComponents.count - 1);
                                NSMutableArray *vertexesForNormalCalculation = nil;
                                unsigned int currentFaceIndex = 0;
                                for (int i = 1; i < definitionComponents.count; i++)
                                {
                                    NSString *definitionComponent = [definitionComponents objectAtIndex:i];
                                    NSArray *vertexDefinitionComponents = [definitionComponent componentsSeparatedByString:@"/"];
                                    if (vertexDefinitionComponents.count > 3)
                                    {
                                        self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"Unexpected number of vertex definition components in face: %@", line]
                                                                       errorCode:MSHParseErrorInvalidFaceDefinition];
                                        self.parserStage = MSHParsingStageError;
                                        return;
                                    }
                                    NSInteger vertexIndex = [[vertexDefinitionComponents objectAtIndex:0] integerValue];
                                    vertexIndex = getIndex(tmpVertices, vertexIndex);
                                    MSHVertex *vertex = [tmpVertices objectAtIndex:vertexIndex];
                                    unsigned int suggestedIndex = (unsigned int) vertices.count;
                                    id normalId = [NSNull null];
                                    // obj specification allows vertex normals to be specified explicitly or implicitly.
                                    if (vertexDefinitionComponents.count == 3)
                                    {
                                        // The vertex coordinate was specified explicitly via the "vn" directive.
                                        NSInteger normalIndex = [[vertexDefinitionComponents objectAtIndex:2] integerValue];
                                        normalIndex = getIndex(tmpNormals, normalIndex);
                                        normalId = [tmpNormals objectAtIndex:normalIndex];
                                    }
                                    else
                                    {
                                        // The normal isn't specified. We're going to have to calculate vertices for this face.
                                        // In order to do that, however, we need to gather the vertices for this face.
                                        if (!vertexesForNormalCalculation)
                                        {
                                            vertexesForNormalCalculation = [NSMutableArray array];
                                        }
                                    }
                                    // Let's associate the previously specified vertex normal with this vertex.
                                    // Note that if the vertex normal was not explicitly specified, for now the vertex normal for this vertex will be NSNull.
                                    [vertex addNormalWithNormalId:normalId suggestedIndex:&suggestedIndex];
                                    if (vertexesForNormalCalculation)
                                    {
                                        // If we're going to be calculating vertex normals for this face, we'll gather the vertices inside vertexesForNormalCalculation.
                                        [vertexesForNormalCalculation addObject:vertex];
                                    }
                                    if (suggestedIndex == vertices.count)
                                    {
                                        // This vertex has not been used with this normal before.
                                        // We will create a new vertices entry for it.
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.x]];
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.y]];
                                        [vertices addObject:[NSNumber numberWithFloat:vertex.position.z]];
                                        if ([normalId isKindOfClass:[NSArray class]])
                                        {
                                            [vertices addObject:[normalId objectAtIndex:0]];
                                            [vertices addObject:[normalId objectAtIndex:1]];
                                            [vertices addObject:[normalId objectAtIndex:2]];
                                        }
                                        else
                                        {
                                            // If the vertex normal needs to be calculated, we will put in nulls for now and fill these values in later.
                                            [vertices addObject:[NSNull null]];
                                            [vertices addObject:[NSNull null]];
                                            [vertices addObject:[NSNull null]];
                                        }
                                    }
                                    face.vertexIndices[currentFaceIndex++] = suggestedIndex/6;
                                }
                                if (vertexesForNormalCalculation)
                                {
                                    // Need to calculate the normal for this face
                                    MSHVertex *firstVertex = [vertexesForNormalCalculation objectAtIndex:0];
                                    NSArray *faceNormal = [firstVertex calculateNormalForTriangleFormedWithVertex2:[vertexesForNormalCalculation objectAtIndex:1]
                                                                                                        andVertex3:[vertexesForNormalCalculation objectAtIndex:2]];
                                    for (int vertexIndexWithinFace = 0; vertexIndexWithinFace < face.numVertices; vertexIndexWithinFace++)
                                    {
                                        unsigned int firstNormalIndex = face.vertexIndices[vertexIndexWithinFace]*6 + 3;
                                        MSHVertex *vertex = [tmpVertices objectAtIndex:face.vertexIndices[vertexIndexWithinFace]];
                                        if ([vertices objectAtIndex:firstNormalIndex] == [NSNull null] ||
                                            [vertex usesNormalAveraging])
                                        {
                                            // Need to fill this normal in
                                            GLKVector3 newAverageNormal = [vertex addNormalToAverage:faceNormal];
                                            [vertices replaceObjectAtIndex:firstNormalIndex++ withObject:[NSNumber numberWithFloat:newAverageNormal.x]];
                                            [vertices replaceObjectAtIndex:firstNormalIndex++ withObject:[NSNumber numberWithFloat:newAverageNormal.y]];
                                            [vertices replaceObjectAtIndex:firstNormalIndex withObject:[NSNumber numberWithFloat:newAverageNormal.z]];
                                        }
                                    }
                                }
                                if (vertices.count/6 > MAX_NUM_VERTICES)
                                {
                                    self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"This model exceeds the maximum number of vertices: %d", MAX_NUM_VERTICES]
                                                                   errorCode:MSHParseErrorVertexNumberLimitExceeded];
                                    self.parserStage = MSHParsingStageError;
                                    return;
                                }
                                [faces addObject:[NSValue valueWithBytes:&face objCType:@encode(MSHFace)]];
                            }
                            default:
                                break;
                        }
                    }
                }
            }
        }
        while (fileData.length == chunkSize);
        tmpVertices = nil;
        tmpNormals = nil;
        self.xRange = outXRange;
        self.yRange = outYRange;
        self.zRange = outZRange;
        self.vertexCoordinates = vertices;
        self.faces = faces;
        if (vertices.count)
        {
            self.parserStage = MSHParsingStageComplete;
        }
        else
        {
            self.parseError = [self errorWithMessage:@"The file does not include any geometry definitions." errorCode:MSHParseErrorNoGeometry];
            self.parserStage = MSHParsingStageError;
        }
    });
}

static inline NSUInteger getIndex(NSArray *array, NSInteger objIndex)
{
    if (objIndex < 0)
    {
        objIndex = array.count + objIndex;
    }
    else
    {
        objIndex -= 1;
    }
    return objIndex;
}

@end

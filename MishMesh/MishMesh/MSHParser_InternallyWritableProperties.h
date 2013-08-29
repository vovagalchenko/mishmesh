//
//  MSHParser_InternallyWritableProperties.h
//  MishMesh
//
//  Created by Vova Galchenko on 8/27/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#ifndef MishMesh_MSHParser_InternallyWritableProperties_h
#define MishMesh_MSHParser_InternallyWritableProperties_h

@interface MSHParser()

@property (nonatomic, readwrite, strong) NSURL *fileURL;
@property (nonatomic, readwrite, assign) MSHParsingStage parserStage;
@property (nonatomic, readwrite, assign) MSHRange xRange, yRange, zRange;
@property (nonatomic, readwrite, strong) NSError *parseError;
@property (nonatomic, readwrite, strong) void (^onStatusUpdateBlock)(MSHParser *);
@property (nonatomic, readwrite, strong) NSArray *vertexCoordinates;
@property (nonatomic, readwrite, strong) NSArray *faces;

@end

#endif

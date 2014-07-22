//
//  MSHParseError.h
//  MishMesh
//
//  Created by Vova Galchenko on 7/22/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#ifndef MishMesh_MSHParseError_h
#define MishMesh_MSHParseError_h

#define MSH_ERROR_DOMAIN_NAME       @"MSHParseError"

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

#endif

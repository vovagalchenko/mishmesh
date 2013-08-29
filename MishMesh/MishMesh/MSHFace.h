//
//  MSHFace.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#ifndef MishMeshSample_MSHFace_h
#define MishMeshSample_MSHFace_h

typedef struct MSHFace
{
    GLushort *vertexIndices;
    GLubyte numVertices;
} MSHFace;

static inline MSHFace MSHFaceMake(unsigned int numVertices)
{
    MSHFace face;
    face.numVertices = numVertices;
    face.vertexIndices = malloc(sizeof(unsigned short) * numVertices);
    return face;
}

#endif

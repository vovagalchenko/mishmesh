//
//  MSHVertex.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHVertex.h"

@interface MSHVertex()
{
    GLKVector3 _avgNormal;
    unsigned int _normalSampleSize;
}

@property (nonatomic, strong) NSMutableDictionary *normalCombos;

@end

@implementation MSHVertex

+ (MSHVertex *)vertexWithX:(GLfloat)x
                         y:(GLfloat)y
                         z:(GLfloat)z
{
    MSHVertex *vertex = [[MSHVertex alloc] init];
    vertex.position = GLKVector3Make(x, y, z);
    vertex->_avgNormal = GLKVector3Make(0, 0, 0);
    vertex->_normalSampleSize = 0;
    return vertex;
}

- (void)addNormalWithNormalId:(id)normalId suggestedIndex:(unsigned int *)suggestedIndex
{
    if (!self.normalCombos)
    {
        self.normalCombos = [NSMutableDictionary dictionary];
    }
    
    if ([self.normalCombos objectForKey:normalId])
    {
        // This vertex has already been used in combination with this normal
        *suggestedIndex = [[self.normalCombos objectForKey:normalId] unsignedIntValue];
    }
    else
    {
        [self.normalCombos setObject:[NSNumber numberWithUnsignedInt:*suggestedIndex] forKey:normalId];
    }
}

- (BOOL)usesNormalAveraging
{
    return _normalSampleSize > 0;
}

- (GLKVector3)addNormalToAverage:(NSArray *)normal
{
    unsigned int currentSampleSize = _normalSampleSize;
    unsigned int newSampleSize = currentSampleSize + 1;
    _avgNormal.x = (_avgNormal.x*currentSampleSize + [[normal objectAtIndex:0] floatValue])/newSampleSize;
    _avgNormal.y = (_avgNormal.y*currentSampleSize + [[normal objectAtIndex:1] floatValue])/newSampleSize;
    _avgNormal.z = (_avgNormal.z*currentSampleSize + [[normal objectAtIndex:2] floatValue])/newSampleSize;
    _normalSampleSize = newSampleSize;
    return _avgNormal;
}

- (GLfloat)xZPlaneDistanceToVertex:(MSHVertex *)otherVertex
{
    GLfloat dx = otherVertex.position.x - self.position.x;
    GLfloat dz = otherVertex.position.z - self.position.z;
    return sqrt(dx*dx + dz*dz);
}

- (NSArray *)calculateNormalForTriangleFormedWithVertex2:(MSHVertex *)vertex2 andVertex3:(MSHVertex *)vertex3
{
    GLKVector3 u = GLKVector3Subtract(vertex2.position, self.position);
    GLKVector3 v = GLKVector3Subtract(vertex3.position, self.position);
    
    GLKVector3 normal = GLKVector3CrossProduct(u, v);
    return [NSArray arrayWithObjects:
            [NSNumber numberWithFloat:normal.x],
            [NSNumber numberWithFloat:normal.y],
            [NSNumber numberWithFloat:normal.z], nil];
}

@end

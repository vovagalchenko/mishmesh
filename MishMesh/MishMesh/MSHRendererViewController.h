//
//  MSHRendererViewController.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

typedef enum MSHRendererViewControllerStatus
{
    MSHRendererViewControllerStatusUnknown,
    MSHRendererViewControllerStatusFileLoadParsingVertices,
    MSHRendererViewControllerStatusFileLoadParsingVertexNormals,
    MSHRendererViewControllerStatusFileLoadParsingFaces,
    MSHRendererViewControllerStatusMeshCalibrating,
    MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware,
    MSHRendererViewControllerStatusMeshDisplaying,
} MSHRendererViewControllerStatus;

@class MSHRendererViewController;
@protocol MSHRendererViewControllerDelegate <NSObject>

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus;
- (void)rendererEncounteredError:(NSError *)error;

@end

@interface MSHRendererViewController : GLKViewController <MSHRendererViewControllerDelegate>

- (id)initWithDelegate:(id<MSHRendererViewControllerDelegate>)rendererDelegate;
- (void)loadFile:(NSURL *)fileURL;

@property (nonatomic, weak) id<MSHRendererViewControllerDelegate>rendererDelegate;
@property (nonatomic, strong) UIColor *meshColor;
@property (nonatomic, assign) float inertiaDampeningRate;

@end

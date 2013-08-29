//
//  MMSModelDisplayViewController.h
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MishMesh/MSHRendererViewController.h"

@interface MMSRemoteModelDisplayViewController : MSHRendererViewController

- (void)showModelSelectionTableAnimated:(BOOL)animated;
- (void)setLoadingHeaderText:(NSString *)headerText infoText:(NSString *)infoText;

@end
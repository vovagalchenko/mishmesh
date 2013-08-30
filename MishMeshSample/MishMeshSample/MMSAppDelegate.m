//
//  MMSAppDelegate.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MMSAppDelegate.h"
#import "MMSRemoteModelDisplayViewController.h"

@implementation MMSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    MSHRendererViewController *rendererVC = [[MMSRemoteModelDisplayViewController alloc] init];
    self.window.rootViewController = rendererVC;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

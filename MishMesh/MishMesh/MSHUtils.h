//
//  MSHUtils.h
//  MishMesh
//
//  Created by Vova Galchenko on 8/14/15.
//  Copyright (c) 2015 Vova Galchenko. All rights reserved.
//

#ifndef MishMesh_MSHUtils_h
#define MishMesh_MSHUtils_h

#pragma mark Logging
#define VLog(s, ...)				NSLog(@"<%@:%d> %@", [[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__])
#define LineID						[NSString stringWithFormat:@"<%@:%d>", [[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__]
#define ASSERT_MAIN_THREAD()        NSAssert([[NSThread currentThread] isMainThread], @"<%@:%d> This must be executed on the main thread.",\
[[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__);

#endif
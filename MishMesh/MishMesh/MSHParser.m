//
//  MSHParser.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHParser.h"
#import "MSHObjParser.h"
#import "MSHParser_InternallyWritableProperties.h"

@interface MSHParser()

@end

@implementation MSHParser

- (id)initWithFileURL:(NSURL *)fileURL fileTypeHint:(MSHFileTypeHint)fileTypeHint
{
    id parserInstance = nil;
    if (self = [super init])
    {
        self.fileURL = fileURL;
        parserInstance = self;
        
        NSString *extension = [fileURL pathExtension];
        if (fileTypeHint == MSHFileTypeHintObj || [extension isEqualToString:@"obj"])
        {
            parserInstance =  [[MSHObjParser alloc] initWithFileURL:fileURL fileTypeHint:fileTypeHint];
            self = nil;
        }
    }
    return parserInstance;
}

- (void)parseFileWithStatusChangeBlock:(void (^)(MSHParser *parser))completion
{
    self.onStatusUpdateBlock = completion;
    self.parseError = [self errorWithMessage:[NSString stringWithFormat:@"No parser for filetype %@", [self.fileURL pathExtension]] errorCode:MSHParseErrorFileTypeUnsupported];
    self.parserStage = MSHParsingStageError;
}

- (NSError *)errorWithMessage:(NSString *)msg errorCode:(MSHParseError)errCode
{
    NSError *error = [[NSError alloc] initWithDomain:ERROR_DOMAIN_NAME
                                                code:errCode
                                            userInfo:@{NSLocalizedDescriptionKey: msg, NSFilePathErrorKey : self.fileURL.path}];
    return error;
}

- (void)setParserStage:(MSHParsingStage)parserStage
{
    BOOL stageUpdated = parserStage != _parserStage;
    _parserStage = parserStage;
    if (stageUpdated && self.onStatusUpdateBlock)
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            self.onStatusUpdateBlock(self);
        });
    }
}

@end

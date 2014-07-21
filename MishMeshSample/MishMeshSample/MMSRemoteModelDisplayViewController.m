//
//  MMSModelDisplayViewController.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MMSRemoteModelDisplayViewController.h"
#import "MMSModelPickerTableViewController.h"
#import <QuartzCore/QuartzCore.h>

#define LOADING_HUD_CORNER_RADIUS                               10.0f
#define LOADING_HUD_BACKGROUND_COLOR                            [UIColor colorWithWhite:0 alpha:.5]
#define LOADING_HUD_TEXT_COLOR                                  [UIColor whiteColor]
#define LOADING_HUD_HORIZONTAL_PADDING                          10.0f
#define LOADING_HUD_VERTICAL_PADDING                            10.0f
#define LOADING_HUD_SPINNGER_HEIGHT                             50.0f
#define ANIMATION_LENGTH                                        0.3f

@interface MMSRemoteModelDisplayViewController()

// Loading HUD
@property (strong, nonatomic) UIView *loadingView;
@property (strong, nonatomic) UIActivityIndicatorView *activityIndicator;
@property (strong, nonatomic) UILabel *loadingHeader;
@property (strong, nonatomic) UILabel *loadingLabel;

@end

static BOOL needsModal = YES;

@implementation MMSRemoteModelDisplayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.loadingView = [[UILabel alloc] init];
    self.loadingView.backgroundColor = LOADING_HUD_BACKGROUND_COLOR;
    self.loadingView.layer.cornerRadius = LOADING_HUD_CORNER_RADIUS;
    self.loadingView.alpha = 0;
    self.activityIndicator = [[UIActivityIndicatorView alloc] init];
    self.activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    self.activityIndicator.backgroundColor = [UIColor redColor];
    [self.activityIndicator startAnimating];
    self.loadingLabel = [[UILabel alloc] init];
    self.loadingLabel.textColor = LOADING_HUD_TEXT_COLOR;
    self.loadingLabel.backgroundColor = [UIColor clearColor];
    self.loadingLabel.font = [UIFont systemFontOfSize:10];
    self.loadingLabel.numberOfLines = 0;
    self.loadingLabel.textAlignment = NSTextAlignmentCenter;
    self.loadingLabel.adjustsFontSizeToFitWidth = NO;
    self.loadingHeader = [[UILabel alloc] init];
    self.loadingHeader.textColor = LOADING_HUD_TEXT_COLOR;
    self.loadingHeader.backgroundColor = [UIColor clearColor];
    self.loadingHeader.font = [UIFont boldSystemFontOfSize:10];
    self.loadingHeader.numberOfLines = 1;
    self.loadingHeader.textAlignment = NSTextAlignmentCenter;
    [self.loadingView addSubview:self.loadingHeader];
    [self.loadingView addSubview:self.activityIndicator];
    [self.loadingView addSubview:self.loadingLabel];
    [self.view addSubview:self.loadingView];
}

#pragma mark - Loading HUD

- (void)setLoadingHeaderText:(NSString *)headerText infoText:(NSString *)infoText
{
    NSAssert([[NSThread currentThread] isMainThread], @"Must be called on main thread.");
    self.loadingHeader.text = headerText;
    self.loadingLabel.text = infoText;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)hideLoadingHUD
{
    self.loadingHeader.text = @"";
    self.loadingLabel.text = @"";
    if (self.loadingView.alpha)
    {
        [UIView animateWithDuration:ANIMATION_LENGTH animations:^
         {
             self.loadingView.alpha = 0;
         }];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGSize viewSize = self.view.bounds.size;
    CGFloat loadingHUDWidth = MIN(viewSize.width, viewSize.height)/2;
    CGFloat usableHUDWidth = loadingHUDWidth - 2*LOADING_HUD_HORIZONTAL_PADDING;
    CGSize loadingLabelSize = [self.loadingLabel.text
                               sizeWithFont:self.loadingLabel.font
                               forWidth:usableHUDWidth
                               lineBreakMode:NSLineBreakByWordWrapping];
    loadingLabelSize.height = 20;
    CGSize loadingHeaderSize = [self.loadingHeader.text
                                sizeWithFont:self.loadingHeader.font
                                forWidth:usableHUDWidth
                                lineBreakMode:NSLineBreakByTruncatingTail];
    CGFloat loadingHUDHeight = MAX(loadingHUDWidth,
                                   LOADING_HUD_VERTICAL_PADDING*2 +
                                   loadingHeaderSize.height +
                                   LOADING_HUD_SPINNGER_HEIGHT +
                                   loadingLabelSize.height);
    
    void (^frameSetter)(void) = ^
    {
        self.loadingView.frame = CGRectMake((viewSize.width - loadingHUDWidth)/2, (viewSize.height - loadingHUDHeight)/2, loadingHUDWidth, loadingHUDHeight);
        self.loadingHeader.frame = CGRectMake(LOADING_HUD_HORIZONTAL_PADDING, LOADING_HUD_VERTICAL_PADDING,
                                              usableHUDWidth, loadingHeaderSize.height);
        self.activityIndicator.center = CGPointMake(CGRectGetMidX(self.loadingView.bounds), CGRectGetMidY(self.loadingView.bounds));
        self.loadingLabel.frame = CGRectMake(LOADING_HUD_HORIZONTAL_PADDING, self.loadingView.bounds.size.height - LOADING_HUD_VERTICAL_PADDING - loadingLabelSize.height,
                                             usableHUDWidth, loadingLabelSize.height);
    };
    
    if (self.loadingView.alpha)
    {
        [UIView animateWithDuration:ANIMATION_LENGTH animations:frameSetter];
    }
    else
    {
        frameSetter();
    }
    
    float loadingViewAlpha = self.loadingLabel.text.length || self.loadingHeader.text.length;
    if (self.loadingView.alpha != loadingViewAlpha)
    {
        [UIView animateWithDuration:ANIMATION_LENGTH animations:^
         {
             self.loadingView.alpha = loadingViewAlpha;
         }];
    }
    
    if (needsModal)
    {
        needsModal = NO;
        [self showModelSelectionTableAnimated:NO];
    }
}

- (void)loadFile:(NSURL *)urlToLoad fileTypeHint:(MSHFileTypeHint)fileTypeHint
{
    [self setLoadingHeaderText:@"Downloading..." infoText:@""];
    [NSURLConnection sendAsynchronousRequest:[[NSURLRequest alloc] initWithURL:urlToLoad]
                                       queue:[[NSOperationQueue alloc] init]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error)
     {
         NSAssert(!error && data, @"Error downloading!");
         NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
         NSString *documentPath = [searchPaths objectAtIndex:0];
         NSString *currentFile = [documentPath stringByAppendingPathComponent:@"current_model.obj"];
         NSFileManager *fm = [NSFileManager defaultManager];
         [fm removeItemAtPath:currentFile error:nil];
         NSAssert([data writeToFile:currentFile atomically:YES], @"Couldn't write to the current_model file.");
         dispatch_async(dispatch_get_main_queue(), ^
         {
             [super loadFile:[NSURL fileURLWithPath:currentFile] fileTypeHint:MSHFileTypeHintNone];
         });
     }];
}

- (void)showModelSelectionTableAnimated:(BOOL)animated
{
    [self presentViewController:[[MMSModelPickerTableViewController alloc] init] animated:animated completion:nil];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    UITouch *touch = [touches anyObject];
    if (touch.tapCount == 3)
    {
        [self showModelSelectionTableAnimated:YES];
    }
}

#pragma mark - MSHRendererViewControllerDelegate

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus
{
    NSString *loaderHeaderText = nil;
    NSString *loaderInfoText = @"";
    switch (newStatus)
    {
        case MSHRendererViewControllerStatusFileLoadParsingVertices:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing vertices...";
            break;
        case MSHRendererViewControllerStatusFileLoadParsingVertexNormals:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing vertex normals...";
            break;
        case MSHRendererViewControllerStatusFileLoadParsingFaces:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"parsing faces...";
            break;
        case MSHRendererViewControllerStatusMeshCalibrating:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"calibrating the mesh...";
            break;
        case MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware:
            loaderHeaderText = @"Loading File";
            loaderInfoText = @"loading into the gpu...";
            break;
        default:
            loaderInfoText = nil;
            break;
    }
    if (loaderInfoText.length > 0 || loaderHeaderText.length > 0)
    {
        [self setLoadingHeaderText:loaderHeaderText infoText:loaderInfoText];
    }
    else
    {
        [self hideLoadingHUD];
    }
}

- (void)rendererEncounteredError:(NSError *)error
{
    [self setLoadingHeaderText:@"ERROR" infoText:error.localizedDescription];
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void)
    {
        [self hideLoadingHUD];
        [self showModelSelectionTableAnimated:YES];
    });
}


@end

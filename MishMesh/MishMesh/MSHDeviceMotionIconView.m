//
//  MSHDeviceMotionIconView.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHDeviceMotionIconView.h"
#import <QuartzCore/QuartzCore.h>

#define HIGHLIGHT_PROPORTION    .4
#define HARSH_HIGHLIGHT_COLOR   [[UIColor whiteColor] colorWithAlphaComponent:0.9]

@interface MSHDeviceMotionIconView()
{
    CGGradientRef _highlightGradient;
}

@end

static CGFloat highlightGradientColors[8] = {
    0.6, 0.6, 0.6, 1.0,
    0.3, 0.3, 0.3, 1.0,
};

@implementation MSHDeviceMotionIconView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.clearsContextBeforeDrawing = YES;
        CGColorSpaceRef baseSpace = CGColorSpaceCreateDeviceRGB();
        _highlightGradient = CGGradientCreateWithColorComponents(baseSpace, highlightGradientColors, NULL, 2);
        CGColorSpaceRelease(baseSpace), baseSpace = NULL;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = .35;
        self.layer.shadowOffset = CGSizeMake(2, 3);
    }
    return self;
}

- (void)dealloc
{
    CGGradientRelease(_highlightGradient);
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextAddEllipseInRect(ctx, self.bounds);
    [[UIColor blackColor] setFill];
    CGContextFillPath(ctx);
    
    // Draw the harsh highlight.
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(1, 1, self.bounds.size.width - 2, self.bounds.size.height - 2));
    CGContextClip(ctx);
    CGContextAddRect(ctx, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height*HIGHLIGHT_PROPORTION));
    CGContextClip(ctx);
    [HARSH_HIGHLIGHT_COLOR setFill];
    CGContextFillRect(ctx, self.bounds);
    CGContextRestoreGState(ctx);
    
    // Draw the gradient highlight.
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(1, 2, self.bounds.size.width - 2, self.bounds.size.height - 2));
    CGContextClip(ctx);
    CGPoint startPoint = CGPointMake(self.bounds.size.width/2, 0);
    CGPoint endPoint = CGPointMake(self.bounds.size.width/2, self.bounds.size.height*HIGHLIGHT_PROPORTION);
    CGContextDrawLinearGradient(ctx, _highlightGradient, startPoint, endPoint, 0);
    CGContextRestoreGState(ctx);
    
    void (^drawGyroscope)(void) = ^
    {
        // The axis
        CGPoint axisOrigin = CGPointMake(self.bounds.size.width/3, self.bounds.size.height/4);
        CGPoint axisDestination = CGPointMake((2*self.bounds.size.width)/3, (3*self.bounds.size.height)/4);
        CGContextMoveToPoint(ctx, axisOrigin.x, axisOrigin.y);
        CGContextAddLineToPoint(ctx, axisDestination.x, axisDestination.y);
        CGContextStrokePath(ctx);
        // Bulbs on the axis
        CGFloat bulbRadius = 2;
        CGContextFillEllipseInRect(ctx, CGRectMake(axisOrigin.x - bulbRadius, axisOrigin.y - bulbRadius, bulbRadius*2, bulbRadius*2));
        CGContextFillEllipseInRect(ctx, CGRectMake(axisDestination.x - bulbRadius, axisDestination.y - bulbRadius, bulbRadius*2, bulbRadius*2));
        // Ellipse 1
        CGContextStrokeEllipseInRect(ctx, CGRectMake(axisOrigin.x, axisOrigin.y, axisDestination.x - axisOrigin.x, axisDestination.y - axisOrigin.y));
        // Ellipse 2
        CGFloat crookedEllipseHeight = self.bounds.size.height/5;
        CGFloat crookedEllipseWidth = self.bounds.size.width/1.5;
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, self.bounds.size.width/2, self.bounds.size.height/2);
        CGContextRotateCTM(ctx, -M_PI/8);
        CGContextTranslateCTM(ctx, -self.bounds.size.height/2, -self.bounds.size.height/2);
        CGContextStrokeEllipseInRect(ctx, CGRectMake((self.bounds.size.width - crookedEllipseWidth)/2, (self.bounds.size.height - crookedEllipseHeight)/2, crookedEllipseWidth, crookedEllipseHeight));
        CGContextRestoreGState(ctx);
    };
    
    [[UIColor blackColor] set];
    CGContextTranslateCTM(ctx, 0, -1);
    drawGyroscope();
    CGContextTranslateCTM(ctx, 0, 1);
    [[UIColor whiteColor] set];
    drawGyroscope();
}

@end


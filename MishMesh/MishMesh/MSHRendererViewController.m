//
//  MSHRendererViewController.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MSHRendererViewController.h"
#import "MSHFile.h"
#import "MSHVertex.h"
#import "MSHFace.h"
#import <CoreMotion/CoreMotion.h>
#import "MSHDeviceMotionIconView.h"

#define BUFFER_OFFSET(i)                                        ((char *)NULL + (i))
#define CAM_VERT_ANGLE                                          GLKMathDegreesToRadians(65)
#define PORTION_OF_DIMENSION_TO_FIT                             1.2f
#define RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION        0.8f
#define ROTATION_DECELERATION_RATE                              0.1f
#define MIN_SCALE                                               (CAM_VERT_ANGLE/M_PI*2)
#define MAX_SCALE                                               2*M_PI
#define DOUBLE_TAP_CHECK_TIMEOUT                                0.1f
#define ANIMATION_LENGTH                                        0.5f

#define DEVICE_MOTION_UPDATE_INTERVAL                           0.3f
#define DIMENSION_OF_DEVICE_MOTION_ICON                         40.0f
#define BOUNCE_FACTOR                                           1.2f
#define DEVICE_MOTION_ICON_PADDING                              5.0f
#define DEVICE_MOTION_ICON_RESTING_X                            self.view.bounds.size.width - DIMENSION_OF_DEVICE_MOTION_ICON - DEVICE_MOTION_ICON_PADDING
#define DEVICE_MOTION_ICON_RESTING_Y                            DEVICE_MOTION_ICON_PADDING
#define DEVICE_MOTION_ANIMATION_LENGTH                          0.2f
#define FINGER_FAT                                              22.0f

typedef struct MSHAnimationAttributes
{
    float rateOfChange;
    float targetRateOfChange;
    float changeAcceleration;
    float targetValue;
} MSHAnimationAttributes;

typedef struct EulerAngles
{
    float yaw;
    float pitch;
    float roll;
} EulerAngles;

@interface MSHRendererViewController()
{
    GLuint _vao;
    GLfloat _eyeZ; // For the view matrix
    GLfloat _rotation, _rotationRate;
    GLfloat _scale, _lastScale;
    GLfloat _aspect, _nearZ, _farZ;
    GLfloat _panX, _panY, _panZ;
    GLKMatrix4 _modelMatrix;
    GLubyte *_numVerticesInFace;
    GLuint _numFaces;
    
    MSHAnimationAttributes _scaleAnimationAttributes;
    MSHAnimationAttributes _panXAnimationAttributes;
    MSHAnimationAttributes _panYAnimationAttributes;
    MSHAnimationAttributes _pitchAnimationAttributes;
    MSHAnimationAttributes _yawAnimationAttributes;
    MSHAnimationAttributes _rollAnimationAttributes;
    EulerAngles _animatingEulerAngles;
    
    BOOL needsModal;
}

@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;
@property (strong, nonatomic) CMMotionManager *motionManager;
@property (strong, nonatomic) CMAttitude *referenceAttitude;
@property (strong, nonatomic) MSHDeviceMotionIconView *deviceMotionIconView;

@end

@implementation MSHRendererViewController

#pragma mark - Lifecycle

- (id)init
{
    return [self initWithDelegate:self];
}

- (id)initWithDelegate:(id<MSHRendererViewControllerDelegate>)rendererDelegate
{
    if (self = [super init])
    {
        self.rendererDelegate = rendererDelegate;
        self.meshColor = [UIColor colorWithRed:0.7f green:0.2f blue:0.2f alpha:1.0f];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    GLKView *view = (GLKView *)self.view;
    self.view.opaque = YES;
    self.view.backgroundColor = [UIColor colorWithRed:212.0/255.0 green:209.0/255.0 blue:187.0/255.0 alpha:1.0];
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat16;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    
    [EAGLContext setCurrentContext:self.context];
    
    self.effect = [[GLKBaseEffect alloc] init];
    self.effect.light0.enabled = GL_TRUE;
    
    CGFloat colorComponents[4];
    getRGBA(self.meshColor, colorComponents);
    self.effect.light0.diffuseColor = GLKVector4Make(colorComponents[0], colorComponents[1], colorComponents[2], colorComponents[3]);
    
    glEnable(GL_DEPTH_TEST);
    
    self.motionManager = [[CMMotionManager alloc] init];
    [self.motionManager startDeviceMotionUpdates];
    
    _scale = 1;
    [self.view addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)]];
    [self.view addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]];
    
    needsModal = YES;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (void)dealloc
{
    [self tearDownOpenGL];
    [self cleanupDisplayedMesh];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if ([self isViewLoaded] && ([[self view] window] == nil))
    {
        self.view = nil;
        [self tearDownOpenGL];
        self.context = nil;
    }
}

- (void)tearDownOpenGL
{
    [EAGLContext setCurrentContext:nil];
    self.effect = nil;
}

#pragma mark - File Loading

- (void)cleanupDisplayedMesh
{
    _vao = 0;
    free(_numVerticesInFace);
    _numVerticesInFace = NULL;
    _rotation = 0;
}

- (void)loadFile:(NSURL *)fileURL
{
    ASSERT_MAIN_THREAD();
    [self cleanupDisplayedMesh];
    NSAssert([fileURL isFileURL], @"loadFile: only operates on local file URLs.");
    MSHFile *file = [[MSHFile alloc] initWithURL:fileURL];
    __weak MSHRendererViewController *weakSelf = self;
    [file parseWithStatusUpdateBlock:^(MSHFile *parsedFile)
    {
        ASSERT_MAIN_THREAD();
        switch (parsedFile.status)
        {
            case MSHFileStatusFailure:
                [weakSelf.rendererDelegate rendererEncounteredError:parsedFile.processingError];
                break;
            case MSHFileStatusReady:
                [weakSelf loadFileIntoGraphicsHardware:file];
                break;
            case MSHFileStatusCalibrating:
                [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusMeshCalibrating];
                break;
            case MSHFileStatusParsingVertices:
                [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingVertices];
                break;
            case MSHFileStatusParsingFaces:
                [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingVertexNormals];
                break;
            case MSHFileStatusParsingVertexNormals:
                [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusFileLoadParsingFaces];
                break;
            default:
                [weakSelf.rendererDelegate rendererChangedStatus:MSHRendererViewControllerStatusUnknown];
                break;
        }
    }];
}

- (void)loadFileIntoGraphicsHardware:(MSHFile *)file
{
    [self rendererChangedStatus:MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware];
    _aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLfloat camHorizAngle = 2*atan(_aspect*tan(CAM_VERT_ANGLE/2));
    CGFloat maxPlanarDistance = [file.xZOutlier xZPlaneDistanceToVertex:[MSHVertex vertexWithX:getMidpoint(file.xRange) y:getMidpoint(file.yRange) z:getMidpoint(file.zRange)]]*2;
    GLfloat distanceToFitHorizontally = (maxPlanarDistance * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(camHorizAngle/2));
    GLfloat distanceToFitVertically = (getSpread(file.yRange) * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(CAM_VERT_ANGLE/2));
    GLfloat distanceToFitDepthWise = (maxPlanarDistance/2 * PORTION_OF_DIMENSION_TO_FIT);
    GLfloat nearZLocation = MAX(distanceToFitDepthWise, MAX(distanceToFitHorizontally, distanceToFitVertically));
    _eyeZ = nearZLocation/RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION;
    _nearZ = _eyeZ - nearZLocation;
    _farZ = _nearZ + 2*nearZLocation;
    _modelMatrix = GLKMatrix4MakeTranslation(-getMidpoint(file.xRange), -getMidpoint(file.yRange), -getMidpoint(file.zRange));
    _numVerticesInFace = file.numVerticesInFace;
    _numFaces = file.numFaces;
    
    glGenVertexArraysOES(1, &_vao);
    glBindVertexArrayOES(_vao);
    
    GLuint arrayVbo;
    glGenBuffers(1, &arrayVbo);
    glBindBuffer(GL_ARRAY_BUFFER, arrayVbo);
    glBufferData(GL_ARRAY_BUFFER, file.vertexCoordinatesSize, file.vertexCoordinates, GL_STATIC_DRAW);
    
    GLuint elementsVbo;
    glGenBuffers(1, &elementsVbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, elementsVbo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, file.vertexIndicesSize, file.vertexIndices, GL_STATIC_DRAW);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribNormal);
    glVertexAttribPointer(GLKVertexAttribNormal, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(12));
    
    glBindVertexArrayOES(0);
    
    [self rendererChangedStatus:MSHRendererViewControllerStatusMeshDisplaying];
}

#pragma mark - Handling User Input

- (void)handlePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer
{
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        _lastScale = pinchGestureRecognizer.scale;
    }
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan ||
        [pinchGestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        _scale += (pinchGestureRecognizer.scale - _lastScale);
        _scale = MAX(MIN_SCALE, _scale);
        _scale = MIN(MAX_SCALE, _scale);
        _lastScale = pinchGestureRecognizer.scale;
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressRecognizer
{
    if ([longPressRecognizer state] == UIGestureRecognizerStateBegan)
    {
        if (self.motionManager.deviceMotion.attitude)
        {
            [self.deviceMotionIconView removeFromSuperview];
            self.deviceMotionIconView = nil;
            self.deviceMotionIconView = [[MSHDeviceMotionIconView alloc] init];
            CGPoint touchLocation = [longPressRecognizer locationInView:self.view];
            self.deviceMotionIconView.frame = CGRectMake(touchLocation.x, touchLocation.y, 0, 0);
            [self.view addSubview:self.deviceMotionIconView];
            [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH*BOUNCE_FACTOR animations:^
             {
                 CGFloat dimension = DIMENSION_OF_DEVICE_MOTION_ICON*BOUNCE_FACTOR;
                 self.deviceMotionIconView.frame = CGRectMake(self.deviceMotionIconView.frame.origin.x - dimension/2,
                                                              self.deviceMotionIconView.frame.origin.y - dimension - FINGER_FAT, dimension, dimension);
             } completion:^(BOOL finished)
             {
                 [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH/2 animations:^
                  {
                      self.deviceMotionIconView.bounds = CGRectMake(0, 0,
                                                                    DIMENSION_OF_DEVICE_MOTION_ICON,
                                                                    DIMENSION_OF_DEVICE_MOTION_ICON);
                  }];
             }];
        }
    }
    else if ([longPressRecognizer state] == UIGestureRecognizerStateEnded)
    {
        self.referenceAttitude = self.motionManager.deviceMotion.attitude;
        [UIView animateWithDuration:ANIMATION_LENGTH animations:^
         {
             self.deviceMotionIconView.frame = CGRectMake(DEVICE_MOTION_ICON_RESTING_X, DEVICE_MOTION_ICON_RESTING_Y,
                                                          DIMENSION_OF_DEVICE_MOTION_ICON, DIMENSION_OF_DEVICE_MOTION_ICON);
         }];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint prevPoint = [touch previousLocationInView:self.view];
    CGPoint point = [touch locationInView:self.view];
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    GLKMatrix4 prerotationModelviewMatrix = GLKMatrix4Multiply(self.effect.transform.modelviewMatrix, GLKMatrix4Invert(GLKMatrix4MakeRotation(_rotation, 0, 1, 0), NULL));
    GLKVector3 worldPrevTouch = screenToWorld(prevPoint, self.view.bounds.size, self.effect, prerotationModelviewMatrix, viewport);
    GLKVector3 worldTouch = screenToWorld(point, self.view.bounds.size, self.effect, prerotationModelviewMatrix, viewport);
    _panX += worldPrevTouch.x - worldTouch.x;
    _panY += worldPrevTouch.y - worldTouch.y;
    _panZ += worldPrevTouch.z - worldTouch.z;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    if (self.referenceAttitude)
    {
        CMAttitude *attitude = self.motionManager.deviceMotion.attitude;
        [attitude multiplyByInverseOfAttitude:self.referenceAttitude];
        _animatingEulerAngles.pitch = attitude.pitch;
        _animatingEulerAngles.yaw = attitude.yaw;
        _animatingEulerAngles.roll = attitude.roll;
        _pitchAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.pitch, 0, ANIMATION_LENGTH);
        _yawAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.yaw, 0, ANIMATION_LENGTH);
        _rollAnimationAttributes = MSHAnimationAttributesMake(_animatingEulerAngles.roll, 0, ANIMATION_LENGTH);
        self.referenceAttitude = nil;
        [UIView animateWithDuration:DEVICE_MOTION_ANIMATION_LENGTH animations:^
         {
             self.deviceMotionIconView.frame = CGRectMake(self.deviceMotionIconView.center.x, self.deviceMotionIconView.center.y, 0, 0);
         } completion:^(BOOL finished)
         {
             [self.deviceMotionIconView removeFromSuperview];
             self.deviceMotionIconView = nil;
         }];
    }
    _rotationRate = 0;
    if (touch.tapCount == 2)
    {
        [self animateToInitialPerspective];
    }
}

static inline GLKVector3 screenToWorld(CGPoint screenPoint, CGSize screenSize, GLKBaseEffect *effect, GLKMatrix4 modelviewMatrix, GLint *viewport)
{
    screenPoint.y = screenSize.height - screenPoint.y;
    
    GLKVector3 worldZero = GLKMathProject(GLKVector3Make(0.0f, 0.0f, 0.0f),
                                          modelviewMatrix,
                                          effect.transform.projectionMatrix,
                                          viewport);
    
    bool success;
    GLKVector3 vector = GLKMathUnproject(GLKVector3Make(screenPoint.x, screenPoint.y, worldZero.z),
                                         modelviewMatrix,
                                         effect.transform.projectionMatrix,
                                         viewport,
                                         &success);
    if (!success)
    {
        VLog(@"Error unprojecting!");
    }
    
    return vector;
}

#pragma mark - Animation

- (void)animateToInitialPerspective
{
    self.view.userInteractionEnabled = NO;
    _scaleAnimationAttributes = MSHAnimationAttributesMake(_scale, 1.0f, ANIMATION_LENGTH);
    _panXAnimationAttributes = MSHAnimationAttributesMake(_panX, 0.0f, ANIMATION_LENGTH);
    _panYAnimationAttributes = MSHAnimationAttributesMake(_panY, 0.0f, ANIMATION_LENGTH);
}

static inline MSHAnimationAttributes MSHAnimationAttributesMake(float startValue, float endValue, float animationLength)
{
    MSHAnimationAttributes animationAttributes;
    float diff = endValue - startValue;
    animationAttributes.targetRateOfChange = (diff*2)/animationLength;
    animationAttributes.rateOfChange = 0;
    animationAttributes.changeAcceleration = animationAttributes.targetRateOfChange/(animationLength/2);
    animationAttributes.targetValue = endValue;
    return animationAttributes;
}

static inline BOOL applyAnimationAttributes(float *attribute, MSHAnimationAttributes *animationAttributes, NSTimeInterval timeSinceLastUpdate)
{
    BOOL animationDone = NO;
    if (fabsf((*animationAttributes).targetRateOfChange - (*animationAttributes).rateOfChange) > fabsf(timeSinceLastUpdate*(*animationAttributes).changeAcceleration) &&
        fabsf(*attribute - (*animationAttributes).targetValue) > fabsf(timeSinceLastUpdate*(*animationAttributes).rateOfChange))
    {
        (*animationAttributes).rateOfChange += timeSinceLastUpdate*(*animationAttributes).changeAcceleration;
    }
    else if ((*animationAttributes).targetRateOfChange)
    {
        (*animationAttributes).rateOfChange = (*animationAttributes).targetRateOfChange;
        (*animationAttributes).targetRateOfChange = 0;
        (*animationAttributes).changeAcceleration = -(*animationAttributes).changeAcceleration;
        
    }
    else if ((*animationAttributes).changeAcceleration)
    {
        *attribute = (*animationAttributes).targetValue;
        animationDone = YES;
        memset(animationAttributes, 0, sizeof(*animationAttributes));
    }
    else
    {
        animationDone = YES;
    }
    
    *attribute += timeSinceLastUpdate*(*animationAttributes).rateOfChange;
    
    return animationDone;
}

- (void)decelerateRotation:(NSTimer *)timer
{
    if (fabsf(_rotationRate) < ROTATION_DECELERATION_RATE)
    {
        [timer invalidate];
        _rotationRate = 0;
    }
    else if (_rotationRate > 0)
    {
        _rotationRate -= ROTATION_DECELERATION_RATE;
    }
    else
    {
        _rotationRate += ROTATION_DECELERATION_RATE;
    }
}

#pragma mark - OpenGL drawing

- (void)update
{
    // Process the rotation rate
    double deviceRotationRate = self.motionManager.deviceMotion.rotationRate.y;
    if (fabsf(deviceRotationRate) > 8)
    {
        _rotationRate = deviceRotationRate;
        [NSTimer scheduledTimerWithTimeInterval:.03 target:self selector:@selector(decelerateRotation:) userInfo:nil repeats:YES];
    }
    
    GLKMatrix4 turnedModelMatrix = GLKMatrix4Multiply(GLKMatrix4MakeYRotation(_rotation), _modelMatrix);
    GLKMatrix4 translatedTurnedModelMatrix = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(-_panX, -_panY, -_panZ), turnedModelMatrix);
    GLKMatrix4 viewMatrix = GLKMatrix4MakeLookAt(0.0f, 0.0f, _eyeZ,
                                                 0.0f, 0.0f, 0.0f,
                                                 0.0f, 1.0f, 0.0f);
    
    float timeSinceLastUpdate = self.timeSinceLastUpdate;
    if (self.referenceAttitude)
    {
        // The accelerometer is controlling the view matrix
        CMAttitude *attitude = self.motionManager.deviceMotion.attitude;
        [attitude multiplyByInverseOfAttitude:self.referenceAttitude];
        
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.yaw, 0.0f, 0.0f, -1.0f), viewMatrix);
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.roll, 0.0f, -1.0f, 0.0f), viewMatrix);
        viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(attitude.pitch, -1.0f, 0.0f, 0.0f), viewMatrix);
    }
    else if (_animatingEulerAngles.pitch || _animatingEulerAngles.yaw || _animatingEulerAngles.roll)
    {
        // We are animating back to the initial pitch and yaw (0, 0)
        applyAnimationAttributes(&_animatingEulerAngles.pitch, &_pitchAnimationAttributes, timeSinceLastUpdate);
        applyAnimationAttributes(&_animatingEulerAngles.yaw, &_yawAnimationAttributes, timeSinceLastUpdate);
        applyAnimationAttributes(&_animatingEulerAngles.roll, &_rollAnimationAttributes, timeSinceLastUpdate);
        if (_animatingEulerAngles.yaw)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.yaw, 0.0f, 0.0f, -1.0f), viewMatrix);
        if (_animatingEulerAngles.roll)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.roll, 0.0f, -1.0f, 0.0f), viewMatrix);
        if (_animatingEulerAngles.pitch)
            viewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(_animatingEulerAngles.pitch, -1.0f, 0.0f, 0.0f), viewMatrix);
    }
    self.effect.transform.modelviewMatrix = GLKMatrix4Multiply(viewMatrix, translatedTurnedModelMatrix);
    self.effect.transform.projectionMatrix = GLKMatrix4MakePerspective(CAM_VERT_ANGLE/_scale, _aspect, _nearZ, _farZ);
    
    _rotation += timeSinceLastUpdate * _rotationRate;
    
    BOOL scaleAnimationFinished = applyAnimationAttributes(&_scale, &_scaleAnimationAttributes, timeSinceLastUpdate);
    BOOL panYAnimationFinished = applyAnimationAttributes(&_panY, &_panYAnimationAttributes, timeSinceLastUpdate);
    BOOL panXAnimationFinished = applyAnimationAttributes(&_panX, &_panXAnimationAttributes, timeSinceLastUpdate);
    self.view.userInteractionEnabled = scaleAnimationFinished && panYAnimationFinished && panXAnimationFinished &&
    !_animatingEulerAngles.yaw && !_animatingEulerAngles.roll && !_animatingEulerAngles.pitch;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    CGFloat colorComponents[4];
    // Could optimize this by caching the color components for the background color.
    getRGBA(self.view.backgroundColor, colorComponents);
    glClearColor(colorComponents[0], colorComponents[1], colorComponents[2], colorComponents[3]);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    if (_vao)
    {
        glBindVertexArrayOES(_vao);
        
        [self.effect prepareToDraw];
        
        GLushort *faceOffset = 0;
        for (int i = 0; i < _numFaces; i++)
        {
            glDrawElements(GL_TRIANGLE_FAN, _numVerticesInFace[i], GL_UNSIGNED_SHORT, (const void *)faceOffset);
            faceOffset += _numVerticesInFace[i];
        }
    }
}

#pragma mark - MSHRendererViewControllerDelegate

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus
{
    
}

- (void)rendererEncounteredError:(NSError *)error
{
    
}

#pragma mark - Misc. Helpers

static inline void getRGBA(UIColor *color, CGFloat *colorComponents)
{
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color.CGColor);
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(colorSpace);
    
    switch (colorSpaceModel)
    {
        case kCGColorSpaceModelRGB:
            [color getRed:&colorComponents[0] green:&colorComponents[1] blue:&colorComponents[2] alpha:&colorComponents[3]];
            break;
        case kCGColorSpaceModelMonochrome:
        {
            CGFloat white;
            [color getWhite:&white alpha:&colorComponents[3]];
            colorComponents[0] = white;
            colorComponents[1] = white;
            colorComponents[2] = white;
        }
            break;
        default:
            NSCAssert(NO, @"Unsupported color space: %d", colorSpaceModel);
            break;
    }
}

@end


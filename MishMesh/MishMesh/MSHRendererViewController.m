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
#import <fenv.h>

#define BUFFER_OFFSET(i)                                        ((char *)NULL + (i))
#define CAM_VERT_ANGLE                                          GLKMathDegreesToRadians(65)
#define PORTION_OF_DIMENSION_TO_FIT                             1.2f
#define RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION        0.8f
#define ROTATION_DECELERATION_RATE                              0.1f
#define MAX_SCALE                                               (4*M_PI)
#define MIN_SCALE                                               1
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

#define PINCH_ANCHOR_TOLERANCE                                  2.0f

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
    GLfloat _aspect, _nearZ, _farZ;
	GLfloat _maxDistanceToFit;
    GLKMatrix4 _modelMatrix, _modelTransforms, _viewMatrix;
    GLubyte *_numVerticesInFace;
    GLuint _numFaces;
    
    GLKVector3 _outlierPosition;
    
    MSHAnimationAttributes _scaleAnimationAttributes;
    MSHAnimationAttributes _panXAnimationAttributes;
    MSHAnimationAttributes _panYAnimationAttributes;
    MSHAnimationAttributes _pitchAnimationAttributes;
    MSHAnimationAttributes _yawAnimationAttributes;
    MSHAnimationAttributes _rollAnimationAttributes;
    MSHAnimationAttributes _quaternionAnimationAttributes;
    EulerAngles _animatingEulerAngles;
    
    CGPoint _quaternionAnchorPoint;
    GLKQuaternion _currentRotationQuaternion;
    GLKQuaternion _totalQuaternion;
    
    CGPoint _panAnchorPoint;
    GLKVector3 _totalPan;

    CGPoint _lastSignificantScreenPinchAnchor;
    GLKVector3 _pinchWorldAnchorPoint;
    GLfloat _scale, _currentScale;
}

@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;
@property (strong, nonatomic) CMMotionManager *motionManager;
@property (strong, nonatomic) CMAttitude *referenceAttitude;
@property (strong, nonatomic) MSHDeviceMotionIconView *deviceMotionIconView;

@end

@implementation MSHRendererViewController

#pragma mark - UIViewController

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
    view.multipleTouchEnabled = YES;
    
    [EAGLContext setCurrentContext:self.context];
    
    self.effect = [[GLKBaseEffect alloc] init];
    self.effect.light0.enabled = GL_TRUE;
    
    CGFloat colorComponents[4];
    getRGBA(self.meshColor, colorComponents);
    self.effect.light0.diffuseColor = GLKVector4Make(colorComponents[0], colorComponents[1], colorComponents[2], colorComponents[3]);
    
    glEnable(GL_DEPTH_TEST);
    
    self.motionManager = [[CMMotionManager alloc] init];
    [self.motionManager startDeviceMotionUpdates];
    
    [self.view addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)]];
    [self.view addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]];
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    panRecognizer.minimumNumberOfTouches = 2;
    [self.view addGestureRecognizer:panRecognizer];
}

- (BOOL)shouldAutorotate
{
    return self.referenceAttitude == nil;
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


- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if (UIInterfaceOrientationIsLandscape(fromInterfaceOrientation) ^
        UIInterfaceOrientationIsLandscape(self.interfaceOrientation))
    {
        [self calculateCameraParams];
        [self animateToInitialPerspective];
    }
}

#pragma mark - File Loading

- (void)cleanupDisplayedMesh
{
    _vao = 0;
    free(_numVerticesInFace);
    _numVerticesInFace = NULL;
    _totalQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    _currentRotationQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    _totalPan = GLKVector3Make(0, 0, 0);
    _scale = 1;
    _currentScale = 1;
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

- (void)calculateCameraParams
{
    _aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLfloat camHorizAngle = 2*atan(_aspect*tan(CAM_VERT_ANGLE/2));
    GLfloat distanceToFitHorizontally = (_maxDistanceToFit * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(camHorizAngle/2));
    GLfloat distanceToFitVertically = (_maxDistanceToFit * PORTION_OF_DIMENSION_TO_FIT)/(2*tan(CAM_VERT_ANGLE/2));
    GLfloat distanceToFitDepthWise = (_maxDistanceToFit/2 * PORTION_OF_DIMENSION_TO_FIT);
    GLfloat nearZLocation = MAX(distanceToFitDepthWise, MAX(distanceToFitHorizontally, distanceToFitVertically));
    _eyeZ = nearZLocation/RATIO_OF_NEAR_Z_BOUND_LOCATION_TO_EYE_Z_LOCATION;
    _nearZ = _eyeZ - nearZLocation;
    _farZ = _nearZ + 2*nearZLocation;
    
}

- (void)loadFileIntoGraphicsHardware:(MSHFile *)file
{
    [self rendererChangedStatus:MSHRendererViewControllerStatusMeshLoadingIntoGraphicsHardware];
    
    _maxDistanceToFit = [file.outlierVertex distanceToVertex:[MSHVertex vertexWithX:getMidpoint(file.xRange) y:getMidpoint(file.yRange) z:getMidpoint(file.zRange)]]*2;
    [self calculateCameraParams];
    
    _modelMatrix = GLKMatrix4MakeTranslation(-getMidpoint(file.xRange), -getMidpoint(file.yRange), -getMidpoint(file.zRange));
    _numVerticesInFace = file.numVerticesInFace;
    _numFaces = file.numFaces;
    
    _outlierPosition = file.outlierVertex.position;
    
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
    GLKMatrix4 transformsExceptRotation = GLKMatrix4Multiply(_modelTransforms, GLKMatrix4Invert([self totalRotationMatrix], NULL));
    GLKMatrix4 modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, GLKMatrix4Multiply(transformsExceptRotation, _modelMatrix));
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        _lastSignificantScreenPinchAnchor = [pinchGestureRecognizer locationInView:self.view];
        _pinchWorldAnchorPoint = screenToWorld(_lastSignificantScreenPinchAnchor, self.view.bounds.size,
                                         self.effect, modelviewMatrix);
    }
    if ([pinchGestureRecognizer state] == UIGestureRecognizerStateBegan ||
        [pinchGestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        
        _currentScale = MIN(MAX_SCALE/_scale, MAX(MIN_SCALE/_scale, pinchGestureRecognizer.scale));
        
        if (pinchGestureRecognizer.numberOfTouches == 2)
        {
            CGPoint newScreenAnchorPoint = [pinchGestureRecognizer locationInView:self.view];
            CGFloat distanceToLastSignificantAnchor = getDistance(newScreenAnchorPoint, _lastSignificantScreenPinchAnchor);
            if (_currentScale > 1.0f || distanceToLastSignificantAnchor > PINCH_ANCHOR_TOLERANCE)
            {
                GLKVector3 newWorldAnchorPoint = screenToWorld(newScreenAnchorPoint, self.view.bounds.size, self.effect, modelviewMatrix);
                if (!isnan(newWorldAnchorPoint.x) && !isnan(newWorldAnchorPoint.y) && !isnan(newWorldAnchorPoint.z))
                {
                    _lastSignificantScreenPinchAnchor = newScreenAnchorPoint;
                    GLKVector3 additionalPan = GLKVector3Make(_pinchWorldAnchorPoint.x - newWorldAnchorPoint.x,
                                                              _pinchWorldAnchorPoint.y - newWorldAnchorPoint.y,
                                                              0);
                    _totalPan = GLKVector3Add(_totalPan, additionalPan);
                }
            }
        }
    }
    else if (pinchGestureRecognizer.state == UIGestureRecognizerStateEnded ||
             pinchGestureRecognizer.state == UIGestureRecognizerStateCancelled)
    {
        _scale = MIN(MAX_SCALE, MAX(MIN_SCALE, _currentScale*_scale));
        _currentScale = 1;
    }
}

static inline CGFloat getDistance(CGPoint point1, CGPoint point2)
{
    CGFloat dx = point1.x - point2.x;
    CGFloat dy = point1.y - point2.y;
    return sqrtf(dx*dx + dy*dy);
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPressRecognizer
{
    if ([longPressRecognizer state] == UIGestureRecognizerStateBegan)
    {
        if (self.motionManager.deviceMotion.attitude && UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
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
    else if ([longPressRecognizer state] == UIGestureRecognizerStateEnded && UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
    {
        self.referenceAttitude = self.motionManager.deviceMotion.attitude;
        [UIView animateWithDuration:ANIMATION_LENGTH animations:^
         {
             self.deviceMotionIconView.frame = CGRectMake(DEVICE_MOTION_ICON_RESTING_X, DEVICE_MOTION_ICON_RESTING_Y,
                                                          DIMENSION_OF_DEVICE_MOTION_ICON, DIMENSION_OF_DEVICE_MOTION_ICON);
         }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)panRecognizer
{
    if ([panRecognizer state] == UIGestureRecognizerStateBegan)
    {
        _panAnchorPoint = [panRecognizer locationInView:self.view];
    }
    else if ([panRecognizer state] == UIGestureRecognizerStateChanged && panRecognizer.numberOfTouches >= 2)
    {
        CGPoint touchPoint = [panRecognizer locationInView:self.view];
        GLKMatrix4 modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, _modelMatrix);
        GLKVector3 panAnchorPoint = screenToWorld(_panAnchorPoint, self.view.bounds.size, self.effect, modelviewMatrix);
        GLKVector3 worldTouchPoint = screenToWorld(touchPoint, self.view.bounds.size, self.effect, modelviewMatrix);
        GLKVector3 additionalPan = GLKVector3Make((panAnchorPoint.x - worldTouchPoint.x),
                                                  (panAnchorPoint.y - worldTouchPoint.y),
                                                  (panAnchorPoint.z - worldTouchPoint.z));
        _totalPan = GLKVector3Add(_totalPan, additionalPan);
        _panAnchorPoint = touchPoint;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    _quaternionAnchorPoint = [[touches anyObject] locationInView:self.view];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    if (touches.count == 1 && event.allTouches.count == 1)
    {
        // Single finger dragging will trigger rotation.
        CGPoint currentTouchPoint = [touch locationInView:self.view];
        GLKVector3 currentTouchSphereVector = mapTouchToSphere(self.view.bounds.size, currentTouchPoint);
        GLKVector3 previousTouchSphereVector = mapTouchToSphere(self.view.bounds.size, _quaternionAnchorPoint);
        
        _currentRotationQuaternion = getQuaternion(previousTouchSphereVector, currentTouchSphereVector);
        // The axis of rotation is undefined when the quaternion angle becomes M_PI.
        // We'll flush the current quaternion when the angle get to M_PI/2.
        if (GLKQuaternionAngle(_currentRotationQuaternion) >= M_PI_2)
        {
            [self flushCurrenQuaternionWithNewAnchorPoint:currentTouchPoint];
        }
    }
}

- (void)flushCurrenQuaternionWithNewAnchorPoint:(CGPoint)newAnchorPoint
{
    _totalQuaternion = GLKQuaternionMultiply(_currentRotationQuaternion, _totalQuaternion);
    _currentRotationQuaternion = GLKQuaternionMake(0, 0, 0, 1);
    _quaternionAnchorPoint = newAnchorPoint;
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
    if (touch.tapCount == 2)
    {
        [self animateToInitialPerspective];
    }
    if ([touches count] == 1)
    {
        [self flushCurrenQuaternionWithNewAnchorPoint:CGPointMake(0, 0)];
    }
}


static inline GLKVector3 screenToWorld(CGPoint screenPoint, CGSize screenSize, GLKBaseEffect *effect, GLKMatrix4 modelviewMatrix)
{
    screenPoint.y = screenSize.height - screenPoint.y;
    GLint viewport[4];
    viewport[0] = 0;
    viewport[1] = 0;
    viewport[2] = screenSize.width;
    viewport[3] = screenSize.height;
    
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
        vector = GLKVector3Make(nan(""), nan(""), nan(""));
    }
    
    return vector;
}

#pragma mark - Animation

- (void)animateToInitialPerspective
{
    self.view.userInteractionEnabled = NO;
    _scaleAnimationAttributes = MSHAnimationAttributesMake(_scale, 1.0f, ANIMATION_LENGTH);
    _panXAnimationAttributes = MSHAnimationAttributesMake(_totalPan.x, 0.0f, ANIMATION_LENGTH);
    _panYAnimationAttributes = MSHAnimationAttributesMake(_totalPan.y, 0.0f, ANIMATION_LENGTH);
    float quaternionAngle = GLKQuaternionAngle(_totalQuaternion);
    _quaternionAnimationAttributes = MSHAnimationAttributesMake(quaternionAngle, 0.0f, ANIMATION_LENGTH);
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

#pragma mark - OpenGL drawing

- (void)update
{
    GLKQuaternion finalQuaternion = [self totalQuaternion];
    float timeSinceLastUpdate = self.timeSinceLastUpdate;
    float oldQuaternionAngle = GLKQuaternionAngle(finalQuaternion);
    float newQuaternionAngle = oldQuaternionAngle;
    BOOL quaternionAnimationFinished = applyAnimationAttributes(&newQuaternionAngle, &_quaternionAnimationAttributes, timeSinceLastUpdate);
    finalQuaternion = GLKQuaternionMakeWithAngleAndVector3Axis(newQuaternionAngle, GLKQuaternionAxis(finalQuaternion));
    if (oldQuaternionAngle != newQuaternionAngle)
    {
        _totalQuaternion = finalQuaternion;
    }
    _modelTransforms = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(-_totalPan.x, -_totalPan.y, -_totalPan.z),
                                          GLKMatrix4Multiply(GLKMatrix4MakeScale(_scale*_currentScale, _scale*_currentScale, _scale*_currentScale),
                                                             GLKMatrix4MakeWithQuaternion(finalQuaternion)));
    GLKMatrix4 transformedModelMatrix = GLKMatrix4Multiply(_modelTransforms, _modelMatrix);
    GLKMatrix4 viewMatrix = GLKMatrix4MakeLookAt(0, 0, _eyeZ,
                                                 0, 0, 0,
                                                 0.0f, 1.0f, 0.0f);
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
    _viewMatrix = viewMatrix;
    self.effect.transform.modelviewMatrix = GLKMatrix4Multiply(_viewMatrix, transformedModelMatrix);
    self.effect.transform.projectionMatrix = GLKMatrix4MakePerspective(CAM_VERT_ANGLE, _aspect, _nearZ, _farZ);
    
    BOOL scaleAnimationFinished = applyAnimationAttributes(&_scale, &_scaleAnimationAttributes, timeSinceLastUpdate);
    BOOL panXAnimationFinished = applyAnimationAttributes(&_totalPan.x, &_panXAnimationAttributes, timeSinceLastUpdate);
    BOOL panYAnimationFinished = applyAnimationAttributes(&_totalPan.y, &_panYAnimationAttributes, timeSinceLastUpdate);
    self.view.userInteractionEnabled = scaleAnimationFinished && panYAnimationFinished && panXAnimationFinished && quaternionAnimationFinished &&
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

#pragma mark - Quaternion Rotation Helpers

- (GLKMatrix4)totalRotationMatrix
{
    return GLKMatrix4MakeWithQuaternion([self totalQuaternion]);
}

- (GLKQuaternion)totalQuaternion
{
    return GLKQuaternionMultiply(_currentRotationQuaternion, _totalQuaternion);
}

static inline GLKVector3 mapTouchToSphere(CGSize viewSize, CGPoint touchCoordinates)
{
    CGFloat sphereRadius = MIN(viewSize.width, viewSize.height)/2.0f;
    GLKVector3 xyCenter = GLKVector3Make(viewSize.width/2, viewSize.height/2, 0);
    GLKVector3 touchVectorFromCenter = GLKVector3Subtract(GLKVector3Make(touchCoordinates.x, touchCoordinates.y, 0), xyCenter);
    touchVectorFromCenter = GLKVector3Make(touchVectorFromCenter.x, -touchVectorFromCenter.y, touchVectorFromCenter.z);
    
    GLfloat radiusSquared = sphereRadius*sphereRadius;
    GLfloat xyLengthSquared = touchVectorFromCenter.x*touchVectorFromCenter.x + touchVectorFromCenter.y*touchVectorFromCenter.y;
    
    // Pythagoras has entered the building
    if (radiusSquared >= xyLengthSquared)
        touchVectorFromCenter.z = sqrt(radiusSquared - xyLengthSquared);
    else
    {
        touchVectorFromCenter.x *= radiusSquared/sqrt(xyLengthSquared);
        touchVectorFromCenter.y *= radiusSquared/sqrt(xyLengthSquared);
        touchVectorFromCenter.z = 0;
    }
    return GLKVector3Normalize(touchVectorFromCenter);
}

static inline GLKQuaternion getQuaternion(GLKVector3 unitVector1, GLKVector3 unitVector2)
{
    GLKVector3 axis = GLKVector3CrossProduct(unitVector1, unitVector2);
    GLfloat angle = acosf(GLKVector3DotProduct(unitVector1, unitVector2));
    GLKQuaternion result = GLKQuaternionMakeWithAngleAndVector3Axis(angle, axis);
    if (result.w != 1)
        result = GLKQuaternionNormalize(result);
    return result;
}

static inline void printQuaternion(GLKQuaternion quaternion)
{
    GLKVector3 axis = GLKQuaternionAxis(quaternion);
    float angle = GLKQuaternionAngle(quaternion);
    VLog(@"(%f, %f, %f) %f", axis.x, axis.y, axis.z, angle);
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


#pragma mark - MSHRendererViewControllerDelegate

- (void)rendererChangedStatus:(MSHRendererViewControllerStatus)newStatus
{
    
}

- (void)rendererEncounteredError:(NSError *)error
{
    
}

@end


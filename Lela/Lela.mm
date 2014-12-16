//
//  Lela.m
//  Lela
//
//  Created by Brian Nickel on 7/12/13.
//  Copyright (c) 2013 Brian Nickel. All rights reserved.
//

#import "Lela.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "LPyramid.h"
#include "RGBAImage.h"
#include "CompareArgs.h"
#include "Metric.h"

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

@implementation Lela

+ (NSString *)imageNameForScreenNamed:(NSString *)screenName
{
    CGSize screenSize = [self screenSize];
    CGFloat scale = [UIScreen mainScreen].scale;
    NSString *idiom;
    
    switch ([UIDevice currentDevice].userInterfaceIdiom) {
        case UIUserInterfaceIdiomPad:   idiom = @"ipad";   break;
        case UIUserInterfaceIdiomPhone: idiom = @"iphone"; break;
    }
    NSString *version = [[UIDevice currentDevice] systemVersion];
    
    return [NSString stringWithFormat:@"%@-%dx%d@%dx-%@,iOS%@", screenName, (int)screenSize.width, (int)screenSize.height, (int)roundf(scale), idiom, version];
}

+ (NSString *)directoryForTestRunNamed:(NSString *)name
{
#if TARGET_IPHONE_SIMULATOR
    return [@"/tmp/Lela Tests" stringByAppendingPathComponent:name];
#else
    NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    return [[path stringByAppendingPathComponent:@"Lela Tests"] stringByAppendingPathComponent:name];
#endif
}

+ (NSString *)directoryForExpectedImages
{
    return [[NSBundle bundleForClass:self] resourcePath];
}

+ (NSString *)saveImage:(UIImage *)image type:(LelaResultImageType)type named:(NSString *)name testRun:(NSString *)testRun
{
    NSString *fileName;
    NSString *imageNameForScreen = [self imageNameForScreenNamed:name];
    switch (type) {
        case LelaResultImageTypeActual:     fileName = imageNameForScreen; break;
        case LelaResultImageTypeExpected:   fileName = [NSString stringWithFormat:@"%@-%@", imageNameForScreen, @"Expected"]; break;
        case LelaResultImageTypeDifference: fileName = [NSString stringWithFormat:@"%@-%@", imageNameForScreen, @"Difference"]; break;
    }
    
    NSString *directoryPath = [self directoryForTestRunNamed:testRun];
    NSString *filePath = [[directoryPath stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"png"];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:NULL];
    
    [UIImagePNGRepresentation(image) writeToFile:filePath atomically:YES];
    
    return filePath;
}

+ (UIImage *)expectedImageWithName:(NSString *)name
{
    NSString *fileName = [[self imageNameForScreenNamed:name] stringByAppendingPathExtension:@"png"];
    NSString *filePath = [[self directoryForExpectedImages] stringByAppendingPathComponent:fileName];
    return [UIImage imageWithContentsOfFile:filePath];
}

+ (CGSize)screenSize
{
    CGSize imageSize = [UIScreen mainScreen].bounds.size;;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsLandscape(orientation) && SYSTEM_VERSION_LESS_THAN(@"8.0")) {
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        imageSize.width = screenSize.height;
        imageSize.height = screenSize.width;
    }
    return imageSize;
}

+ (UIImage *)captureScreenshot
{
    CGSize imageSize = [self screenSize];
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, window.center.x, window.center.y);
        CGContextConcatCTM(context, window.transform);
        CGContextTranslateCTM(context, -window.bounds.size.width * window.layer.anchorPoint.x, -window.bounds.size.height * window.layer.anchorPoint.y);
        if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {
            UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
            if (orientation == UIInterfaceOrientationLandscapeLeft) {
                CGContextRotateCTM(context, M_PI_2);
                CGContextTranslateCTM(context, 0, -imageSize.width);
            } else if (orientation == UIInterfaceOrientationLandscapeRight) {
                CGContextRotateCTM(context, -M_PI_2);
                CGContextTranslateCTM(context, -imageSize.height, 0);
            } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
                CGContextRotateCTM(context, M_PI);
                CGContextTranslateCTM(context, -imageSize.width, -imageSize.height);
            }
        }
        if ([window respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        } else {
            [window.layer renderInContext:context];
        }
        CGContextRestoreGState(context);
    }
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (BOOL)compareExpectedImage:(UIImage *)expected toActual:(UIImage *)actual options:(NSDictionary *)options difference:(UIImage **)difference errorDescription:(NSString **)errorDescription
{
    CompareArgs args;
    args.ImgA = RGBAImage::ReadFromUIImage(expected);
    args.ImgB = RGBAImage::ReadFromUIImage(actual);
    args.ImgDiff = new RGBAImage(args.ImgA->Get_Width(), args.ImgA->Get_Height(), "Output");
    args.ThresholdPixels = [options[LECompareOptionThresholdPixels] unsignedIntValue];
    
    BOOL success = Yee_Compare(args);
    
    if (!success && difference) {
        *difference = args.ImgDiff->Get_UIImage();
        if (errorDescription != nil) {
            NSString *errorMessage = [NSString stringWithCString:args.ErrorStr.c_str()
                                                        encoding:[NSString defaultCStringEncoding]];
            errorMessage = [errorMessage stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            *errorDescription = errorMessage;
        }
    }
    
    return success;
}

@end

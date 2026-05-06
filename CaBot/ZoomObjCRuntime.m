/*******************************************************************************
 * Copyright (c) 2021  Carnegie Mellon University
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

#import "ZoomObjCRuntime.h"
#import <UIKit/UIKit.h>

@implementation UIViewController (ZoomTopViewController)

- (UIViewController *)topViewController
{
    if ([self isKindOfClass:[UINavigationController class]]) {
        UIViewController *visible = ((UINavigationController *)self).visibleViewController;
        return visible ? [visible topViewController] : self;
    }
    if ([self isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = ((UITabBarController *)self).selectedViewController;
        return selected ? [selected topViewController] : self;
    }
    if (self.presentedViewController) {
        return [self.presentedViewController topViewController];
    }
    for (UIViewController *child in self.childViewControllers.reverseObjectEnumerator) {
        if (child.viewIfLoaded.window != nil) {
            return [child topViewController];
        }
    }
    return self;
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    UIViewController *topController = [self topViewController];
    UINavigationController *navigationController = nil;

    if ([topController isKindOfClass:[UINavigationController class]]) {
        navigationController = (UINavigationController *)topController;
    } else {
        navigationController = topController.navigationController;
    }

    if (navigationController != nil) {
        [navigationController pushViewController:viewController animated:animated];
        return;
    }

    if (viewController.modalPresentationStyle == UIModalPresentationNone) {
        viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    [topController presentViewController:viewController animated:animated completion:nil];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
    UIViewController *topController = [self topViewController];
    UINavigationController *navigationController = nil;

    if ([topController isKindOfClass:[UINavigationController class]]) {
        navigationController = (UINavigationController *)topController;
    } else {
        navigationController = topController.navigationController;
    }

    if (navigationController != nil) {
        return [navigationController popViewControllerAnimated:animated];
    }

    UIViewController *presented = topController.presentedViewController;
    if (presented != nil) {
        [presented dismissViewControllerAnimated:animated completion:nil];
        return presented;
    }
    if (topController.presentingViewController != nil) {
        UIViewController *controller = topController;
        [topController dismissViewControllerAnimated:animated completion:nil];
        return controller;
    }
    return nil;
}

- (NSArray<UIViewController *> *)viewControllers
{
    UIViewController *topController = [self topViewController];
    UINavigationController *navigationController = nil;

    if ([topController isKindOfClass:[UINavigationController class]]) {
        navigationController = (UINavigationController *)topController;
    } else {
        navigationController = topController.navigationController;
    }

    if (navigationController != nil) {
        return navigationController.viewControllers;
    }

    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    UIViewController *current = topController;
    while (current != nil) {
        [controllers insertObject:current atIndex:0];
        current = current.presentingViewController;
    }
    return controllers.copy;
}

@end

@implementation ZoomObjCRuntime

+ (nullable NSInvocation *)invocationForSelector:(SEL)selector onTarget:(id)target {
    if (target == nil || selector == NULL || ![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature == nil) {
        return nil;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    return invocation;
}

+ (nullable id)invokeObjectSelector:(NSString *)selector onTarget:(id)target {
    return [self invokeObjectSelector:selector onTarget:target objectArg:nil];
}

+ (nullable id)invokeObjectSelector:(NSString *)selector onTarget:(id)target objectArg:(nullable id)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return nil;
    }
    if (arg != nil && invocation.methodSignature.numberOfArguments > 2) {
        id localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
    const char *returnType = invocation.methodSignature.methodReturnType;
    if (strcmp(returnType, @encode(id)) != 0 && strcmp(returnType, @encode(Class)) != 0) {
        return nil;
    }
    __unsafe_unretained id returnValue = nil;
    [invocation getReturnValue:&returnValue];
    return returnValue;
}

+ (void)invokeVoidSelector:(NSString *)selector onTarget:(id)target {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return;
    }
    [invocation invoke];
}

+ (void)invokeVoidSelector:(NSString *)selector onTarget:(id)target objectArg:(nullable id)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return;
    }
    if (invocation.methodSignature.numberOfArguments > 2) {
        id localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
}

+ (void)invokeVoidSelector:(NSString *)selector onTarget:(id)target boolArg:(BOOL)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return;
    }
    if (invocation.methodSignature.numberOfArguments > 2) {
        BOOL localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
}

+ (void)invokeVoidSelector:(NSString *)selector onTarget:(id)target integerArg:(NSInteger)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return;
    }
    if (invocation.methodSignature.numberOfArguments > 2) {
        NSInteger localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
}

+ (BOOL)invokeBoolSelector:(NSString *)selector onTarget:(id)target objectArg:(nullable id)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return NO;
    }
    if (arg != nil && invocation.methodSignature.numberOfArguments > 2) {
        id localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
    BOOL returnValue = NO;
    [invocation getReturnValue:&returnValue];
    return returnValue;
}

+ (BOOL)invokeBoolSelector:(NSString *)selector onTarget:(id)target boolArg:(BOOL)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return NO;
    }
    if (invocation.methodSignature.numberOfArguments > 2) {
        BOOL localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
    BOOL returnValue = NO;
    [invocation getReturnValue:&returnValue];
    return returnValue;
}

+ (NSInteger)invokeIntegerSelector:(NSString *)selector onTarget:(id)target objectArg:(nullable id)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return NSNotFound;
    }
    if (arg != nil && invocation.methodSignature.numberOfArguments > 2) {
        id localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
    NSInteger returnValue = NSNotFound;
    [invocation getReturnValue:&returnValue];
    return returnValue;
}

+ (NSInteger)invokeIntegerSelector:(NSString *)selector onTarget:(id)target boolArg:(BOOL)arg {
    SEL sel = NSSelectorFromString(selector);
    NSInvocation *invocation = [self invocationForSelector:sel onTarget:target];
    if (invocation == nil) {
        return NSNotFound;
    }
    if (invocation.methodSignature.numberOfArguments > 2) {
        BOOL localArg = arg;
        [invocation setArgument:&localArg atIndex:2];
    }
    [invocation invoke];
    NSInteger returnValue = NSNotFound;
    [invocation getReturnValue:&returnValue];
    return returnValue;
}

+ (BOOL)setValue:(nullable id)value forKey:(NSString *)key onTarget:(id)target {
    if (target == nil || key.length == 0) {
        return NO;
    }
    @try {
        [target setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

@end

// FirebaseBootstrap.m
//
// Initializes Firebase at app launch without modifying Godot's AppDelegate
// (which lives inside libgodot.a). The +load class method runs once when the
// Objective-C runtime loads this binary; we register an observer for
// UIApplicationDidFinishLaunchingNotification and configure FirebaseApp from
// there — before the game starts logging events.
//
// AnalyticsBridge.swift then takes over for forwarding GDScript events.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>

@import FirebaseCore;

@interface TLFirebaseBootstrap : NSObject
@end

@implementation TLFirebaseBootstrap

+ (void)load {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        if ([FIRApp defaultApp] == nil) {
#if DEBUG
            // Force Firebase Analytics DebugView on for Debug builds (works
            // without scheme args, which devicectl can't pass). Release skips it.
            [[NSUserDefaults standardUserDefaults]
                setBool:YES forKey:@"/google/measurement/debug_mode"];
            NSLog(@"[FirebaseBootstrap] DEBUG build: Analytics DebugView enabled");
#endif
            [FIRApp configure];
            NSLog(@"[FirebaseBootstrap] FirebaseApp.configure() done");
        }
#if !DEBUG
        // Anonymous Apple attribution only; no Tenjin SDK or tracking prompt.
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        BOOL declined = [[defaults stringForKey:@"jfun_install_measurement.choice"] isEqual:@"deny"]
            || [[defaults dictionaryForKey:@"jfun_install_measurement"][@"choice"] isEqual:@"deny"];
        if (!declined) {
            if (@available(iOS 16.1, *)) {
                [SKAdNetwork updatePostbackConversionValue:0 coarseValue:SKAdNetworkCoarseConversionValueLow lockWindow:NO completionHandler:^(NSError *error) {}];
            } else if (@available(iOS 15.4, *)) {
                [SKAdNetwork updatePostbackConversionValue:0 completionHandler:^(NSError *error) {}];
            } else {
                [SKAdNetwork updateConversionValue:0];
            }
        }
#endif
        // Kick off the GDScript event-forwarder. The Swift module name depends
        // on how Godot names the iOS target, so try the likely variants.
        Class bridge = Nil;
        for (NSString *name in @[ @"TinkerLab.AnalyticsBridge",
                                  @"Tinker_Lab.AnalyticsBridge",
                                  @"AnalyticsBridge" ]) {
            bridge = NSClassFromString(name);
            if (bridge) { break; }
        }
        if (bridge) {
            [bridge performSelector:@selector(start)];
        } else {
            NSLog(@"[FirebaseBootstrap] AnalyticsBridge class not found");
        }
    }];
}

@end

#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <Foundation/Foundation.h>
#import "../DIPNPrefsKeys.h"

// 偏好设置路径（rootless 环境）
static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.axs.dipn.plist";

@interface DIPNListController : PSListController
@end

@implementation DIPNListController

- (instancetype)init {
    self = [super init];
    if (self) {
        // 设置偏好设置文件路径
        self.specifierPlistPath = @"/Library/PreferenceBundles/DIPNSettings.bundle/Root.plist";
    }
    return self;
}

- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target {
    NSArray *specifiers = [super loadSpecifiersFromPlistName:name target:target];

    // 设置默认值
    for (PSSpecifier *specifier in specifiers) {
        NSString *key = [specifier propertyForKey:@"key"];
        if (key) {
            id defaultValue = [specifier propertyForKey:@"default"];
            if (defaultValue && ![self readPreferenceValue:key]) {
                [self setPreferenceValue:defaultValue specifier:specifier];
            }
        }
    }

    return specifiers;
}

- (id)readPreferenceValue:(NSString *)key {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
    return prefs[key];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
    prefs[key] = value;
    [prefs writeToFile:kPrefsPath atomically:YES];

    // 发送设置变更通知
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(DIPN_PREFS_CHANGED_NOTIFICATION),
        NULL, NULL, YES
    );
}

- (void)respring {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/killall"];
    [task setArguments:@[@"-9", @"SpringBoard"]];
    [task launch];
}

- (void)openGithub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/axs66/Dynamic-Island-Push-Notification"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

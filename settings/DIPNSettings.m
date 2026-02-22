#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <spawn.h>
#import "../DIPNPrefsKeys.h"

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.axs.dipn.plist";

@interface DIPNListController : PSListController
@end

@implementation DIPNListController

- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target {
    NSArray *specifiers = [super loadSpecifiersFromPlistName:name target:target];

    for (PSSpecifier *specifier in specifiers) {
        NSString *key = [specifier propertyForKey:@"key"];
        if (key) {
            id defaultValue = [specifier propertyForKey:@"default"];
            id currentValue = [super readPreferenceValue:specifier];
            if (defaultValue && !currentValue) {
                [self setPreferenceValue:defaultValue specifier:specifier];
            }
        }
    }

    return specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return nil;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    return prefs[key];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
    prefs[key] = value;
    [prefs writeToFile:kPrefsPath atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(DIPN_PREFS_CHANGED_NOTIFICATION),
        NULL, NULL, YES
    );
}

- (void)respring {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

- (void)openGithub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/359266613/DynamicIslandPushNotification"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

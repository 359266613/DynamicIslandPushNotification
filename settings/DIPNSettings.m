#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <spawn.h>
#import "../DIPNPrefsKeys.h"

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.axs.dipn.plist";

@interface DIPNListController : PSListController
@end

@implementation DIPNListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: @{};
    NSString *key = specifier.properties[@"key"];
    return prefs[key] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[@"key"];
    if (!key) return;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
    if (value) {
        prefs[key] = value;
    } else {
        [prefs removeObjectForKey:key];
    }
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

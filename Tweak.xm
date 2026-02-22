#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UserNotifications/UserNotifications.h>
#import "DIPNLog.h"
#import "DIPNPrefsKeys.h"

#pragma mark - 常量定义
static const CGFloat kExpandedIslandWidth = 250.0;
static const CGFloat kExpandedIslandHeight = 80.0;
static const CGFloat kAnimationDuration = 0.3;
static const CGFloat kDefaultDisplayDuration = 3.0;

#pragma mark - 全局变量
static BOOL gEnabled = YES;
static BOOL gShowAppIcon = YES;
static BOOL gShowTitle = YES;
static BOOL gShowBody = YES;
static CGFloat gDisplayDuration = kDefaultDisplayDuration;
static NSInteger gMaxBodyLength = 50;

static UIView *gIslandNotificationView = nil;
static UILabel *gTitleLabel = nil;
static UILabel *gBodyLabel = nil;
static UIImageView *gAppIconView = nil;
static NSTimer *gDismissTimer = nil;
static __weak UIView *gCurrentIslandView = nil;

#pragma mark - 私有类声明

@interface SAUIElementView : UIView
@end

@interface SBBulletinBannerController : NSObject
+ (instancetype)sharedInstance;
@end

@interface BBBulletin : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *sectionID;
@property (nonatomic, retain) UIImage *icon;
@property (nonatomic, copy) NSString *publisherBundleID;
@end

@interface SBBannerView : UIView
@property (nonatomic, retain) BBBulletin *bulletin;
@end

@interface BBContent : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, retain) UIImage *icon;
@end

@interface SBBulletin : NSObject
@property (nonatomic, copy) NSString *sectionID;
@property (nonatomic, retain) BBContent *content;
@end

@interface SBLockScreenNotificationContext : NSObject
- (void)_presentNotification:(id)notification;
@end

@interface NCNotificationRequest : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@end

@interface NCNotificationContent : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *subtitle;
@end

#pragma mark - 函数声明
static void loadPrefs(void);
static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void showNotificationInIsland(NSString *title, NSString *body, UIImage *icon, NSString *bundleID);
static void hideNotificationFromIsland(void);
static void createIslandNotificationView(void);
static void animateIslandToExpanded(void);
static void animateIslandToCompact(void);
static UIView *findIslandView(void);
static UIImage *getAppIconForBundle(NSString *bundleID);

#pragma mark - 设置加载
static void loadPrefs(void) {
    @try {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:DIPN_PREFS_PATH] ?: @{};

        id e = prefs[DIPN_KEY_ENABLED];
        gEnabled = e ? [e boolValue] : YES;

        id sai = prefs[DIPN_KEY_SHOW_APP_ICON];
        gShowAppIcon = sai ? [sai boolValue] : YES;

        id st = prefs[DIPN_KEY_SHOW_TITLE];
        gShowTitle = st ? [st boolValue] : YES;

        id sb = prefs[DIPN_KEY_SHOW_BODY];
        gShowBody = sb ? [sb boolValue] : YES;

        id dd = prefs[DIPN_KEY_DISPLAY_DURATION];
        gDisplayDuration = dd ? [dd floatValue] : kDefaultDisplayDuration;

        id mbl = prefs[DIPN_KEY_MAX_BODY_LENGTH];
        gMaxBodyLength = mbl ? [mbl integerValue] : 50;

        DIPNLogInfo(@"设置已加载: enabled=%d, duration=%.1f", gEnabled, gDisplayDuration);
    } @catch (NSException *exception) {
        DIPNLogError(@"加载设置失败: %@", exception);
        gEnabled = YES;
    }
}

static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
}

#pragma mark - 查找灵动岛视图
static UIView *findIslandView(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count > 0) {
                UIView *view = [stack lastObject];
                [stack removeLastObject];
                if ([view isKindOfClass:%c(SAUIElementView)]) {
                    return view;
                }
                [stack addObjectsFromArray:view.subviews];
            }
        }
    }
    return nil;
}

#pragma mark - 灵动岛通知视图
static void createIslandNotificationView(void) {
    if (gIslandNotificationView) return;

    gIslandNotificationView = [[UIView alloc] init];
    gIslandNotificationView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    gIslandNotificationView.layer.cornerRadius = 20.0;
    gIslandNotificationView.layer.masksToBounds = YES;
    gIslandNotificationView.clipsToBounds = YES;
    gIslandNotificationView.userInteractionEnabled = NO;

    gAppIconView = [[UIImageView alloc] init];
    gAppIconView.contentMode = UIViewContentModeScaleAspectFit;
    gAppIconView.layer.cornerRadius = 8.0;
    gAppIconView.layer.masksToBounds = YES;
    gAppIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gAppIconView];

    gTitleLabel = [[UILabel alloc] init];
    gTitleLabel.font = [UIFont boldSystemFontOfSize:14];
    gTitleLabel.textColor = [UIColor whiteColor];
    gTitleLabel.numberOfLines = 1;
    gTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gTitleLabel];

    gBodyLabel = [[UILabel alloc] init];
    gBodyLabel.font = [UIFont systemFontOfSize:12];
    gBodyLabel.textColor = [UIColor lightGrayColor];
    gBodyLabel.numberOfLines = 2;
    gBodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gBodyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [gAppIconView.leadingAnchor constraintEqualToAnchor:gIslandNotificationView.leadingAnchor constant:12],
        [gAppIconView.centerYAnchor constraintEqualToAnchor:gIslandNotificationView.centerYAnchor],
        [gAppIconView.widthAnchor constraintEqualToConstant:28],
        [gAppIconView.heightAnchor constraintEqualToConstant:28],

        [gTitleLabel.leadingAnchor constraintEqualToAnchor:gAppIconView.trailingAnchor constant:10],
        [gTitleLabel.topAnchor constraintEqualToAnchor:gIslandNotificationView.topAnchor constant:12],
        [gTitleLabel.trailingAnchor constraintEqualToAnchor:gIslandNotificationView.trailingAnchor constant:-12],

        [gBodyLabel.leadingAnchor constraintEqualToAnchor:gAppIconView.trailingAnchor constant:10],
        [gBodyLabel.topAnchor constraintEqualToAnchor:gTitleLabel.bottomAnchor constant:4],
        [gBodyLabel.trailingAnchor constraintEqualToAnchor:gIslandNotificationView.trailingAnchor constant:-12],
        [gBodyLabel.bottomAnchor constraintLessThanOrEqualToAnchor:gIslandNotificationView.bottomAnchor constant:-8],
    ]];

    DIPNLogInfo(@"灵动岛通知视图已创建");
}

static void animateIslandToExpanded(void) {
    if (!gIslandNotificationView || !gCurrentIslandView) return;

    CGRect islandFrame = gCurrentIslandView.frame;

    [UIView animateWithDuration:kAnimationDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        gIslandNotificationView.frame = CGRectMake(
            islandFrame.origin.x - (kExpandedIslandWidth - islandFrame.size.width) / 2,
            islandFrame.origin.y,
            kExpandedIslandWidth,
            kExpandedIslandHeight
        );
        gIslandNotificationView.alpha = 1.0;
    } completion:nil];
}

static void animateIslandToCompact(void) {
    if (!gIslandNotificationView) return;

    [UIView animateWithDuration:kAnimationDuration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        gIslandNotificationView.alpha = 0;
    } completion:^(BOOL finished) {
        [gIslandNotificationView removeFromSuperview];
    }];
}

#pragma mark - 显示/隐藏通知
static void showNotificationInIsland(NSString *title, NSString *body, UIImage *icon, NSString *bundleID) {
    if (!gEnabled) {
        DIPNLogInfo(@"插件已禁用，跳过显示");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDismissTimer) {
            [gDismissTimer invalidate];
            gDismissTimer = nil;
        }

        UIView *islandView = findIslandView();
        if (!islandView) {
            DIPNLogWarn(@"未找到灵动岛视图");
            return;
        }

        gCurrentIslandView = islandView;
        createIslandNotificationView();

        if (gShowAppIcon && icon) {
            gAppIconView.image = icon;
            gAppIconView.hidden = NO;
        } else {
            gAppIconView.hidden = YES;
        }

        if (gShowTitle && title) {
            gTitleLabel.text = title;
            gTitleLabel.hidden = NO;
        } else {
            gTitleLabel.hidden = YES;
        }

        if (gShowBody && body) {
            NSString *displayBody = body;
            if (body.length > gMaxBodyLength) {
                displayBody = [[body substringToIndex:gMaxBodyLength] stringByAppendingString:@"..."];
            }
            gBodyLabel.text = displayBody;
            gBodyLabel.hidden = NO;
        } else {
            gBodyLabel.hidden = YES;
        }

        if (gIslandNotificationView.superview != islandView) {
            [islandView addSubview:gIslandNotificationView];
        }

        CGRect islandFrame = islandView.frame;
        gIslandNotificationView.frame = islandFrame;
        gIslandNotificationView.alpha = 0;

        animateIslandToExpanded();

        DIPNLogInfo(@"通知已显示: %@ - %@", title, body);

        gDismissTimer = [NSTimer scheduledTimerWithTimeInterval:gDisplayDuration repeats:NO block:^(NSTimer *timer) {
            hideNotificationFromIsland();
        }];
    });
}

static void hideNotificationFromIsland(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDismissTimer) {
            [gDismissTimer invalidate];
            gDismissTimer = nil;
        }
        animateIslandToCompact();
        DIPNLogInfo(@"通知已隐藏");
    });
}

#pragma mark - 获取 App 图标
static UIImage *getAppIconForBundle(NSString *bundleID) {
    if (!bundleID) return nil;

    @try {
        Class sbIconClass = objc_getClass("SBIcon");
        if (sbIconClass) {
            id sbIconModel = [%c(SBIconModel) sharedInstance];
            if (sbIconModel) {
                SEL iconForDisplayIdentifierSel = @selector(iconForDisplayIdentifier:);
                if ([sbIconModel respondsToSelector:iconForDisplayIdentifierSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id icon = [sbIconModel performSelector:iconForDisplayIdentifierSel withObject:bundleID];
                    if (icon) {
                        SEL iconImageSel = @selector(iconImage);
                        if ([icon respondsToSelector:iconImageSel]) {
                            return [icon performSelector:iconImageSel];
                        }
                    }
#pragma clang diagnostic pop
                }
            }
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"获取图标失败: %@", exception);
    }

    return nil;
}

#pragma mark - Hook SBBannerView
%hook SBBannerView

- (void)didMoveToWindow {
    %orig;

    @try {
        if (!self.window) return;

        BBBulletin *bulletin = self.bulletin;
        if (!bulletin) return;

        NSString *title = bulletin.title ?: @"";
        NSString *body = bulletin.message ?: @"";
        NSString *bundleID = bulletin.publisherBundleID ?: @"";
        UIImage *icon = bulletin.icon ?: getAppIconForBundle(bundleID);

        DIPNLogInfo(@"[SBBannerView] 捕获通知: %@ from %@", title, bundleID);
        showNotificationInIsland(title, body, icon, bundleID);
    } @catch (NSException *exception) {
        DIPNLogError(@"[SBBannerView] hook 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SBBulletinBannerController
%hook SBBulletinBannerController

- (void)_addBannerView:(UIView *)bannerView forBulletin:(id)bulletin {
    %orig;

    @try {
        if (![bulletin isKindOfClass:%c(BBBulletin)]) return;

        BBBulletin *bb = (BBBulletin *)bulletin;
        NSString *title = bb.title ?: @"";
        NSString *body = bb.message ?: @"";
        NSString *bundleID = bb.publisherBundleID ?: @"";
        UIImage *icon = bb.icon ?: getAppIconForBundle(bundleID);

        DIPNLogInfo(@"[SBBulletinBannerController] 捕获通知: %@ from %@", title, bundleID);
        showNotificationInIsland(title, body, icon, bundleID);
    } @catch (NSException *exception) {
        DIPNLogError(@"[SBBulletinBannerController] hook 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SBBulletin (BBBulletin)
%hook SBBulletin

- (void)setContent:(BBContent *)content {
    %orig;

    @try {
        if (!content) return;

        NSString *title = content.title ?: content.subtitle ?: @"";
        NSString *body = content.message ?: @"";
        NSString *bundleID = self.sectionID ?: @"";
        UIImage *icon = content.icon ?: getAppIconForBundle(bundleID);

        DIPNLogInfo(@"[SBBulletin] 捕获通知: %@ from %@", title, bundleID);
        showNotificationInIsland(title, body, icon, bundleID);
    } @catch (NSException *exception) {
        DIPNLogError(@"[SBBulletin] hook 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SAUIElementView
%hook SAUIElementView

- (void)didMoveToWindow {
    %orig;

    @try {
        if (self.window) {
            gCurrentIslandView = self;
            DIPNLogInfo(@"灵动岛视图已附加");
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"[SAUIElementView] hook 异常: %@", exception);
    }
}

- (void)layoutSubviews {
    %orig;

    @try {
        if (gIslandNotificationView && gIslandNotificationView.superview == self) {
            [self bringSubviewToFront:gIslandNotificationView];
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"[SAUIElementView] layoutSubviews 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SpringBoard
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    DIPNLogInfo(@"SpringBoard 启动完成");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gCurrentIslandView = findIslandView();
        if (gCurrentIslandView) {
            DIPNLogInfo(@"灵动岛视图已找到");
        }
    });
}

%end

#pragma mark - 构造函数
%ctor {
    @autoreleasepool {
        DIPNLogInfo(@"灵动岛推送通知插件初始化");

        loadPrefs();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            prefsChangedCallback,
            CFSTR(DIPN_PREFS_CHANGED_NOTIFICATION),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );

        %init(_ungrouped);
    }
}

#pragma mark - 析构函数
%dtor {
    @autoreleasepool {
        if (gDismissTimer) {
            [gDismissTimer invalidate];
            gDismissTimer = nil;
        }

        if (gIslandNotificationView) {
            [gIslandNotificationView removeFromSuperview];
            gIslandNotificationView = nil;
        }

        DIPNLogInfo(@"灵动岛推送通知插件已卸载");
    }
}

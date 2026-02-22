#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UserNotifications/UserNotifications.h>
#import "DIPNLog.h"
#import "DIPNPrefsKeys.h"

#pragma mark - 常量定义
static const CGFloat kCompactIslandWidth = 126.0;
static const CGFloat kCompactIslandHeight = 37.0;
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
static NSArray<NSString *> *gBlacklist = nil;
static BOOL gWhitelistMode = NO;
static NSArray<NSString *> *gWhitelist = nil;

static UIView *gIslandNotificationView = nil;
static UILabel *gTitleLabel = nil;
static UILabel *gBodyLabel = nil;
static UIImageView *gAppIconView = nil;
static NSTimer *gDismissTimer = nil;
static __weak UIView *gCurrentIslandView = nil;

#pragma mark - 私有类声明

// 灵动岛视图
@interface SAUIElementView : UIView
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, assign) CGRect compactFrame;
@property (nonatomic, assign) CGRect expandedFrame;
@end

// 通知相关类
@interface SBBulletinBannerController : NSObject
+ (instancetype)sharedInstance;
- (void)_addBannerView:(UIView *)bannerView forBulletin:(id)bulletin;
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

@interface NCNotificationRequest : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, retain) NSDictionary *content;
@end

@interface NCNotificationContent : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, retain) UIImage *icon;
@end

@interface SBUserNotification : NSObject
@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *alertBody;
@property (nonatomic, copy) NSString *bundleIdentifier;
@end

// SpringBoard 通知中心
@interface SBBulletinBannerWindow : UIView
@end

@interface SBNotificationCenterController : NSObject
+ (instancetype)sharedInstance;
@end

#pragma mark - 函数声明
static void loadPrefs(void);
static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static BOOL shouldShowNotificationForBundle(NSString *bundleID);
static void showNotificationInIsland(NSString *title, NSString *body, UIImage *icon, NSString *bundleID);
static void hideNotificationFromIsland(void);
static void createIslandNotificationView(void);
static void updateIslandNotificationLayout(void);
static void animateIslandToExpanded(void);
static void animateIslandToCompact(void);
static UIView *findIslandView(void);

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

        id bl = prefs[DIPN_KEY_BLACKLIST];
        gBlacklist = [bl isKindOfClass:[NSArray class]] ? (NSArray *)bl : @[];

        id wlm = prefs[DIPN_KEY_WHITELIST_MODE];
        gWhitelistMode = wlm ? [wlm boolValue] : NO;

        id wl = prefs[DIPN_KEY_WHITELIST];
        gWhitelist = [wl isKindOfClass:[NSArray class]] ? (NSArray *)wl : @[];

        DIPNLogInfo(@"设置已加载: enabled=%d, duration=%.1f", gEnabled, gDisplayDuration);
    } @catch (NSException *exception) {
        DIPNLogError(@"加载设置失败: %@", exception);
        gEnabled = YES;
    }
}

static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
}

#pragma mark - 过滤检查
static BOOL shouldShowNotificationForBundle(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) {
        return YES;
    }

    // 白名单模式
    if (gWhitelistMode) {
        for (NSString *allowed in gWhitelist) {
            if ([bundleID isEqualToString:allowed] || [bundleID hasPrefix:allowed]) {
                return YES;
            }
        }
        return NO;
    }

    // 黑名单模式
    for (NSString *blocked in gBlacklist) {
        if ([bundleID isEqualToString:blocked] || [bundleID hasPrefix:blocked]) {
            return NO;
        }
    }

    return YES;
}

#pragma mark - 查找灵动岛视图
static UIView *findIslandView(void) {
    // 遍历所有窗口查找灵动岛
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            // 递归查找 SAUIElementView
            __block UIView *foundView = nil;
            void (^__block recursiveBlock)(UIView *) = nil;
            recursiveBlock = ^(UIView *view) {
                if ([view isKindOfClass:%c(SAUIElementView)]) {
                    foundView = view;
                    return;
                }
                for (UIView *subview in view.subviews) {
                    if (foundView) return;
                    recursiveBlock(subview);
                }
            };
            recursiveBlock(window);
            if (foundView) return foundView;
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

    // App 图标
    gAppIconView = [[UIImageView alloc] init];
    gAppIconView.contentMode = UIViewContentModeScaleAspectFit;
    gAppIconView.layer.cornerRadius = 8.0;
    gAppIconView.layer.masksToBounds = YES;
    gAppIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gAppIconView];

    // 标题标签
    gTitleLabel = [[UILabel alloc] init];
    gTitleLabel.font = [UIFont boldSystemFontOfSize:14];
    gTitleLabel.textColor = [UIColor whiteColor];
    gTitleLabel.numberOfLines = 1;
    gTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gTitleLabel];

    // 正文标签
    gBodyLabel = [[UILabel alloc] init];
    gBodyLabel.font = [UIFont systemFontOfSize:12];
    gBodyLabel.textColor = [UIColor lightGrayColor];
    gBodyLabel.numberOfLines = 2;
    gBodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gIslandNotificationView addSubview:gBodyLabel];

    // 设置约束
    [NSLayoutConstraint activateConstraints:@[
        // App 图标约束
        [gAppIconView.leadingAnchor constraintEqualToAnchor:gIslandNotificationView.leadingAnchor constant:12],
        [gAppIconView.centerYAnchor constraintEqualToAnchor:gIslandNotificationView.centerYAnchor],
        [gAppIconView.widthAnchor constraintEqualToConstant:28],
        [gAppIconView.heightAnchor constraintEqualToConstant:28],

        // 标题约束
        [gTitleLabel.leadingAnchor constraintEqualToAnchor:gAppIconView.trailingAnchor constant:10],
        [gTitleLabel.topAnchor constraintEqualToAnchor:gIslandNotificationView.topAnchor constant:12],
        [gTitleLabel.trailingAnchor constraintEqualToAnchor:gIslandNotificationView.trailingAnchor constant:-12],

        // 正文约束
        [gBodyLabel.leadingAnchor constraintEqualToAnchor:gAppIconView.trailingAnchor constant:10],
        [gBodyLabel.topAnchor constraintEqualToAnchor:gTitleLabel.bottomAnchor constant:4],
        [gBodyLabel.trailingAnchor constraintEqualToAnchor:gIslandNotificationView.trailingAnchor constant:-12],
        [gBodyLabel.bottomAnchor constraintLessThanOrEqualToAnchor:gIslandNotificationView.bottomAnchor constant:-8],
    ]];

    DIPNLogInfo(@"灵动岛通知视图已创建");
}

static void updateIslandNotificationLayout(void) {
    if (!gIslandNotificationView || !gCurrentIslandView) return;

    CGRect islandFrame = gCurrentIslandView.frame;
    gIslandNotificationView.frame = islandFrame;

    // 根据内容调整布局
    BOOL hasBody = gBodyLabel.text.length > 0;
    CGFloat height = hasBody ? kExpandedIslandHeight : 50;

    [UIView animateWithDuration:kAnimationDuration animations:^{
        gIslandNotificationView.frame = CGRectMake(
            islandFrame.origin.x,
            islandFrame.origin.y,
            kExpandedIslandWidth,
            height
        );
    }];
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

    if (!shouldShowNotificationForBundle(bundleID)) {
        DIPNLogInfo(@"Bundle %@ 在过滤列表中，跳过", bundleID);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // 取消之前的隐藏计时器
        if (gDismissTimer) {
            [gDismissTimer invalidate];
            gDismissTimer = nil;
        }

        // 查找灵动岛视图
        UIView *islandView = findIslandView();
        if (!islandView) {
            DIPNLogWarn(@"未找到灵动岛视图");
            return;
        }

        gCurrentIslandView = islandView;

        // 创建通知视图
        createIslandNotificationView();

        // 设置内容
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

        // 添加到灵动岛
        if (gIslandNotificationView.superview != islandView) {
            [islandView addSubview:gIslandNotificationView];
        }

        // 初始状态
        CGRect islandFrame = islandView.frame;
        gIslandNotificationView.frame = islandFrame;
        gIslandNotificationView.alpha = 0;

        // 动画展开
        animateIslandToExpanded();

        DIPNLogInfo(@"通知已显示: %@ - %@", title, body);

        // 设置自动隐藏
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

#pragma mark - Hook SBBannerView (横幅通知)
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

        DIPNLogInfo(@"捕获横幅通知: %@ from %@", title, bundleID);
        showNotificationInIsland(title, body, icon, bundleID);
    } @catch (NSException *exception) {
        DIPNLogError(@"SBBannerView hook 异常: %@", exception);
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

        DIPNLogInfo(@"捕获 Bulletin 通知: %@ from %@", title, bundleID);
        showNotificationInIsland(title, body, icon, bundleID);
    } @catch (NSException *exception) {
        DIPNLogError(@"SBBulletinBannerController hook 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SAUIElementView (灵动岛视图)
%hook SAUIElementView

- (void)didMoveToWindow {
    %orig;

    @try {
        if (self.window) {
            gCurrentIslandView = self;
            DIPNLogInfo(@"灵动岛视图已附加");
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"SAUIElementView hook 异常: %@", exception);
    }
}

- (void)layoutSubviews {
    %orig;

    @try {
        if (gIslandNotificationView && gIslandNotificationView.superview == self) {
            // 保持通知视图在顶层
            [self bringSubviewToFront:gIslandNotificationView];
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"layoutSubviews hook 异常: %@", exception);
    }
}

%end

#pragma mark - Hook SpringBoard 应用通知
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    DIPNLogInfo(@"SpringBoard 启动完成");

    // 延迟初始化，等待灵动岛视图创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gCurrentIslandView = findIslandView();
        if (gCurrentIslandView) {
            DIPNLogInfo(@"灵动岛视图已找到");
        }
    });
}

// Hook 远程推送通知
- (void)_receivedRemoteNotification:(id)notification {
    %orig;

    @try {
        DIPNLogInfo(@"收到远程推送通知");

        // 尝试从通知中提取信息
        if ([notification isKindOfClass:[NSDictionary class]]) {
            NSDictionary *userInfo = (NSDictionary *)notification;
            NSDictionary *aps = userInfo[@"aps"];

            NSString *title = nil;
            NSString *body = nil;

            // iOS 10+ 格式
            if (aps[@"alert"]) {
                id alert = aps[@"alert"];
                if ([alert isKindOfClass:[NSString class]]) {
                    body = alert;
                } else if ([alert isKindOfClass:[NSDictionary class]]) {
                    title = ((NSDictionary *)alert)[@"title"];
                    body = ((NSDictionary *)alert)[@"body"];
                }
            }

            if (title || body) {
                showNotificationInIsland(title ?: @"通知", body ?: @"", nil, @"");
            }
        }
    } @catch (NSException *exception) {
        DIPNLogError(@"_receivedRemoteNotification hook 异常: %@", exception);
    }
}

%end

#pragma mark - 构造函数
%ctor {
    @autoreleasepool {
        DIPNLogInfo(@"灵动岛推送通知插件初始化");

        // 加载设置
        loadPrefs();

        // 注册设置变更通知
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            prefsChangedCallback,
            CFSTR(DIPN_PREFS_CHANGED_NOTIFICATION),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );

        // 初始化 hook
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

export TARGET := iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless
export INSTALL_TARGET_PROCESSES = SpringBoard
DIPN_LOG_LEVEL ?= 2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DynamicIslandPushNotification
DynamicIslandPushNotification_FILES = Tweak.xm
DynamicIslandPushNotification_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR) -DDIPN_LOG_LEVEL=$(DIPN_LOG_LEVEL)
DynamicIslandPushNotification_FRAMEWORKS = UIKit AVFoundation QuartzCore CoreFoundation UserNotifications
DynamicIslandPushNotification_LDFLAGS = -Wl,-no_warn_duplicate_libraries

include $(THEOS_MAKE_PATH)/tweak.mk

# 设置子项目
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk

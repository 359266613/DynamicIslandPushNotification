ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Preferences
DIPN_LOG_LEVEL ?= 2

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DIPNSettings
DIPNSettings_FILES = DIPNSettings.m
DIPNSettings_INSTALL_PATH = /Library/PreferenceBundles
DIPNSettings_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/.. -DDIPN_LOG_LEVEL=$(DIPN_LOG_LEVEL)
DIPNSettings_FRAMEWORKS = UIKit Foundation
DIPNSettings_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/DIPNSettings.plist$(ECHO_END)

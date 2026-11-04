TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e

TWEAK_NAME = Auxo16Probe

Auxo16Probe_FILES = probe/Auxo16Probe.m
Auxo16Probe_FRAMEWORKS = Foundation UIKit
Auxo16Probe_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
Auxo16Probe_CFLAGS = -fobjc-arc -O2 -Wno-unused-function

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

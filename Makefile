THEOS_DEVICE_IP		= 192.168.1.19
THEOS_DEVICE_PORT	= 22
# export THEOS_PACKAGE_SCHEME=rootless
# export THEOS_PACKAGE_SCHEME=roothide
export ARCHS		= arm64 arm64e
export SDKVERSION	= 14.5
export SYSROOT		= $(THEOS)/sdks/iPhoneOS14.5.sdk
export SDKROOT		= $(THEOS)/sdks/iPhoneOS14.5.sdk
export TARGET		= iphone:clang:14.5:14.5
export LANGUAGE		= en_US.UTF-8
export LC_ALL		= en_US.UTF-8
export LANG			= en_US.UTF-8
export LC_CTYPE		= en_US.UTF-8
export DEBUG				= 0
export FINALPACKAGE			= 1
export GO_EASY_ON_ME		= 1
export THEOS_LEAN_AND_MEAN 	= 1

ifneq ($(wildcard ~/.theosconfig),)
include ~/.theosconfig
endif

include $(THEOS)/makefiles/common.mk

TOOL_NAME = JetsamCTL

$(TOOL_NAME)_FILES 			= main.m
$(TOOL_NAME)_LIBRARIES 	   += CrossOverIPC
$(TOOL_NAME)_INSTALL_PATH 	= /usr/bin

ifeq ($(THEOS_PACKAGE_SCHEME), roothide)
	$(TOOL_NAME)_CFLAGS		+= -DIS_ROOTHIDE
	LAUNCH_DAEMON_FILE 		= LaunchDaemons/com.simpzan.jetsamctl-hide.plist
	PACKAGE_BUILDNAME		:= roothide
else ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
	$(TOOL_NAME)_CFLAGS		+= -DIS_ROOTLESS
	LAUNCH_DAEMON_FILE 		= LaunchDaemons/com.simpzan.jetsamctl-less.plist
	PACKAGE_BUILDNAME		:= rootless
else
    $(info 👉 Building Kids_DeviceProof for ROOTFULL mode)
	LAUNCH_DAEMON_FILE 		= LaunchDaemons/com.simpzan.jetsamctl.plist
	PACKAGE_BUILDNAME		:= rootfull
endif

ifeq ($(DEBUG), 1)
export DEBUG_CFLAGS = -DKDEBUG
endif

$(TOOL_NAME)_CFLAGS			+= $(DEBUG_CFLAGS)
$(TOOL_NAME)_LDFLAGS 		+= -rpath /usr/lib -rpath /var/jb/usr/lib -rpath @loader_path/.jbroot/usr/lib
$(TOOL_NAME)_CODESIGN_FLAGS += -Sent.plist

include $(THEOS_MAKE_PATH)/tool.mk

THEOS_TMP_DIR=$(THEOS_BUILD_DIR)/.theos/_tmp

before-stage::
ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
	@mkdir -p "$(THEOS_TMP_DIR)/var/jb"
endif
	@find . -name ".DS_Store" -delete

internal-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"
	@cp "$(LAUNCH_DAEMON_FILE)" "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.simpzan.jetsamctl.plist"
	@ldid -Sent.plist $(THEOS_STAGING_DIR)/usr/bin/$(TOOL_NAME)

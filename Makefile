APP_NAME=HandMirror
BUILD_DIR=build
APP_BUNDLE=$(BUILD_DIR)/$(APP_NAME).app
CONTENTS=$(APP_BUNDLE)/Contents
MACOS=$(CONTENTS)/MacOS
RESOURCES=$(CONTENTS)/Resources

SRCS=MirrorApp.swift MirrorWindow.swift CameraView.swift StatusMenu.swift

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SRCS) Info.plist
	mkdir -p $(MACOS)
	mkdir -p $(RESOURCES)
	cp Info.plist $(CONTENTS)/Info.plist
	[ -f AppIcon.icns ] && cp AppIcon.icns $(RESOURCES)/AppIcon.icns || true
	swiftc -O -sdk $$(xcrun --show-sdk-path --sdk macosx) \
		$(SRCS) \
		-o $(MACOS)/$(APP_NAME)
	chmod +x $(MACOS)/$(APP_NAME)
	@echo "=========================================="
	@echo "🎉 HandMirror.app build successful!"
	@echo "👉 Run: open $(APP_BUNDLE)"
	@echo "=========================================="

clean:
	rm -rf $(BUILD_DIR)

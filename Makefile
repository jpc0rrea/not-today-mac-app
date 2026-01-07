# NotToday Makefile

.PHONY: all build install uninstall clean xcode cli-only

# Default: install CLI with scheduling
all: cli-only

# Build the Swift app (requires full Xcode project)
build:
	@echo "Building NotToday..."
	swift build -c release
	@echo "Build complete. Binary at .build/release/NotToday"

# Install CLI tools and LaunchAgent
cli-only:
	@echo "Installing NotToday CLI..."
	@chmod +x Scripts/install.sh
	@./Scripts/install.sh

# Full install with built app
install: build
	@echo "Installing NotToday..."
	@chmod +x Scripts/install.sh
	@./Scripts/install.sh
	@echo ""
	@echo "To run the GUI app, execute:"
	@echo "  .build/release/NotToday"

# Uninstall everything
uninstall:
	@echo "Uninstalling NotToday..."
	@chmod +x Scripts/uninstall.sh
	@./Scripts/uninstall.sh

# Clean build artifacts
clean:
	@echo "Cleaning..."
	swift package clean
	rm -rf .build

# Generate app icons from favicon design
icons:
	@echo "Generating icons..."
	python3 generate_icons.py
	@if [ -d "AppIcon.iconset" ]; then \
		echo "Creating AppIcon.icns..."; \
		iconutil -c icns AppIcon.iconset; \
		cp AppIcon.icns NotToday.app/Contents/Resources/AppIcon.icns 2>/dev/null || true; \
		echo "Icons generated successfully!"; \
	else \
		echo "Error: AppIcon.iconset not found"; \
	fi

# Generate Xcode project using xcodegen
xcode:
	@if command -v xcodegen >/dev/null 2>&1; then \
		echo "Generating Xcode project..."; \
		xcodegen generate; \
		echo "Opening NotToday.xcodeproj..."; \
		open NotToday.xcodeproj; \
	else \
		echo "XcodeGen not found. Install it with:"; \
		echo "  brew install xcodegen"; \
		echo ""; \
		echo "Or create the Xcode project manually:"; \
		echo "  1. Open Xcode"; \
		echo "  2. File → New → Project → macOS App"; \
		echo "  3. Copy source files from NotToday/Sources/NotToday/"; \
	fi

# Quick status check
status:
	@if [ -f "$$HOME/Library/Application Support/NotToday/nottoday-cli.sh" ]; then \
		"$$HOME/Library/Application Support/NotToday/nottoday-cli.sh" status; \
	else \
		echo "NotToday not installed. Run 'make install' first."; \
	fi

# Release build with signing and notarization
# Prerequisites:
#   1. Apple Developer Program membership ($99/year)
#   2. Developer ID Application certificate installed
#   3. App-specific password for notarization
#   4. Run: xcrun notarytool store-credentials "notary" (one-time setup)
release:
	@echo "Building NotToday for release..."
	@if [ ! -f NotToday.xcodeproj/project.pbxproj ]; then \
		echo "Generating Xcode project..."; \
		xcodegen generate; \
	fi
	@echo "Building release configuration..."
	xcodebuild -project NotToday.xcodeproj \
		-scheme NotToday \
		-configuration Release \
		-derivedDataPath build \
		CODE_SIGN_IDENTITY="Developer ID Application" \
		build
	@echo "Creating DMG..."
	@if command -v create-dmg >/dev/null 2>&1; then \
		create-dmg \
			--volname "NotToday" \
			--window-pos 200 120 \
			--window-size 600 400 \
			--icon-size 100 \
			--icon "NotToday.app" 150 190 \
			--app-drop-link 450 185 \
			"NotToday-1.0.0.dmg" \
			"build/Build/Products/Release/NotToday.app"; \
	else \
		echo "create-dmg not found. Install with: npm install -g create-dmg"; \
		echo "Creating simple DMG instead..."; \
		hdiutil create -volname "NotToday" -srcfolder "build/Build/Products/Release/NotToday.app" -ov -format UDZO "NotToday-1.0.0.dmg"; \
	fi
	@echo ""
	@echo "DMG created: NotToday-1.0.0.dmg"
	@echo ""
	@echo "Next steps for notarization:"
	@echo "  1. xcrun notarytool submit NotToday-1.0.0.dmg --keychain-profile \"notary\" --wait"
	@echo "  2. xcrun stapler staple NotToday-1.0.0.dmg"
	@echo ""

# Setup notarization credentials (run once)
notary-setup:
	@echo "Setting up notarization credentials..."
	@echo "You will need:"
	@echo "  - Your Apple ID email"
	@echo "  - An app-specific password (create at appleid.apple.com)"
	@echo "  - Your Team ID (find in Apple Developer portal)"
	@echo ""
	xcrun notarytool store-credentials "notary" --apple-id "" --team-id ""

# Help
help:
	@echo "NotToday Makefile Commands:"
	@echo ""
	@echo "  make              - Install CLI tool with automatic scheduling"
	@echo "  make cli-only     - Same as above (CLI only, no GUI)"
	@echo "  make build        - Build the Swift app"
	@echo "  make install      - Build and install everything"
	@echo "  make uninstall    - Remove NotToday"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make icons        - Regenerate app and menu bar icons"
	@echo "  make xcode        - Generate and open Xcode project"
	@echo "  make status       - Check current blocking status"
	@echo "  make release      - Build signed DMG for distribution"
	@echo "  make notary-setup - Setup notarization credentials"
	@echo ""

# Lan Mouse Pro - convenience targets.
#
#   make help     this help
#   make run      run the app on the connected device (flutter run)
#   make release  build the release APK (Gradle route)

FLUTTER ?= flutter
SERVICE := lan-mouse-clipboard.service
UNIT_DIR := $(HOME)/.config/systemd/user

.PHONY: help run release clipboard-install clipboard-uninstall clipboard-start clipboard-stop clipboard-restart clipboard-status clipboard-logs

help:
	@echo "Lan Mouse Pro"
	@echo ""
	@echo "  make run                  Run the app (flutter run)"
	@echo "  make release              Build release APK -> build/app/outputs/flutter-apk/app-release.apk"
	@echo ""
	@echo "  make clipboard-install    Install and enable the PC clipboard helper"
	@echo "  make clipboard-uninstall  Disable and remove the clipboard helper"
	@echo "  make clipboard-start      Start the clipboard helper"
	@echo "  make clipboard-stop       Stop the clipboard helper"
	@echo "  make clipboard-restart    Restart the clipboard helper"
	@echo "  make clipboard-status     Clipboard helper status"
	@echo "  make clipboard-logs       Follow clipboard helper logs"

run:
	$(FLUTTER) run

release:
	cd android && ./gradlew assembleRelease
	@echo "APK: build/app/outputs/flutter-apk/app-release.apk"

clipboard-install:
	sh tools/install-clipboard-helper.sh

clipboard-uninstall:
	sh tools/install-clipboard-helper.sh uninstall

clipboard-start:
	systemctl --user start $(SERVICE)

clipboard-stop:
	systemctl --user stop $(SERVICE)

clipboard-restart:
	systemctl --user restart $(SERVICE)

clipboard-status:
	systemctl --user status $(SERVICE) --no-pager

clipboard-logs:
	journalctl --user -u $(SERVICE) -f

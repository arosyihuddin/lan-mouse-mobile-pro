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
	mkdir -p $(UNIT_DIR)
	cp tools/lan-mouse-clipboard.service $(UNIT_DIR)/$(SERVICE)
	systemctl --user daemon-reload
	systemctl --user enable --now $(SERVICE)
	@echo "Clipboard helper enabled."

clipboard-uninstall:
	-systemctl --user disable --now $(SERVICE)
	rm -f $(UNIT_DIR)/$(SERVICE)
	systemctl --user daemon-reload
	@echo "Clipboard helper removed."

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

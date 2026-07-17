LABEL := com.local.run-comfyui
DOMAIN := gui/$(shell id -u)
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist
SERVICE := $(DOMAIN)/$(LABEL)
PORT := 8188

.PHONY: help start stop restart load unload status logs errors logs-all \
        check-port validate-plist install-plist remove-plist

help:
	@echo "ComfyUI LaunchAgent commands"
	@echo ""
	@echo "  make start         Start the loaded LaunchAgent"
	@echo "  make stop          Stop and unload the LaunchAgent"
	@echo "  make restart       Restart the LaunchAgent"
	@echo "  make load          Load the plist and start ComfyUI"
	@echo "  make unload        Unload the LaunchAgent"
	@echo "  make status        Show launchd service status"
	@echo "  make logs          Follow standard output"
	@echo "  make errors        Follow error output"
	@echo "  make logs-all      Follow both log files"
	@echo "  make check-port    Check what is listening on port $(PORT)"
	@echo "  make validate-plist Validate the plist syntax"

start:
	@if launchctl print "$(SERVICE)" >/dev/null 2>&1; then \
		launchctl kickstart -k "$(SERVICE)"; \
	else \
		launchctl bootstrap "$(DOMAIN)" "$(PLIST)"; \
	fi
	@echo "ComfyUI LaunchAgent started."

stop:
	@launchctl bootout "$(DOMAIN)" "$(PLIST)" 2>/dev/null || true
	@echo "ComfyUI LaunchAgent stopped."

restart:
	@launchctl bootout "$(DOMAIN)" "$(PLIST)" 2>/dev/null || true
	@launchctl bootstrap "$(DOMAIN)" "$(PLIST)"
	@echo "ComfyUI LaunchAgent restarted."

load:
	@launchctl bootstrap "$(DOMAIN)" "$(PLIST)"
	@echo "ComfyUI LaunchAgent loaded."

unload:
	@launchctl bootout "$(DOMAIN)" "$(PLIST)" 2>/dev/null || true
	@echo "ComfyUI LaunchAgent unloaded."

status:
	@launchctl print "$(SERVICE)"

logs:
	@tail -f "$(HOME)/Library/Logs/comfyui.log"

errors:
	@tail -f "$(HOME)/Library/Logs/comfyui.error.log"

logs-all:
	@tail -f \
		"$(HOME)/Library/Logs/comfyui.log" \
		"$(HOME)/Library/Logs/comfyui.error.log"

check-port:
	@lsof -nP -iTCP:$(PORT) -sTCP:LISTEN || true

validate-plist:
	@plutil -lint "$(PLIST)"

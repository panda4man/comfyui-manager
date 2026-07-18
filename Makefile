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
	@echo "  make install-plist Render and install the LaunchAgent plist"
	@echo "  make remove-plist  Unload and remove the installed plist"

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
	@tail -f "$(HOME)/Library/Logs/ComfyUI/comfyui.log"

errors:
	@tail -f "$(HOME)/Library/Logs/ComfyUI/comfyui-error.log"

logs-all:
	@tail -f \
		"$(HOME)/Library/Logs/ComfyUI/comfyui.log" \
		"$(HOME)/Library/Logs/ComfyUI/comfyui-error.log"

check-port:
	@lsof -nP -iTCP:$(PORT) -sTCP:LISTEN || true

validate-plist:
	@plutil -lint "$(PLIST)"

install-plist:
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@bash -c 'set -e; source ./config.sh; \
	  sed \
	    -e "s|{{LABEL}}|$(LABEL)|g" \
	    -e "s|{{RUN_SCRIPT}}|$$SCRIPT_DIR/run-comfyui|g" \
	    -e "s|{{COMFY_DIR}}|$$COMFY_DIR|g" \
	    -e "s|{{CONDA_ENV}}|$$CONDA_ENV|g" \
	    -e "s|{{LISTEN_ADDRESS}}|$$LISTEN_ADDRESS|g" \
	    -e "s|{{LISTEN_PORT}}|$$LISTEN_PORT|g" \
	    -e "s|{{LOG_FILE}}|$$LOG_FILE|g" \
	    -e "s|{{ERROR_LOG_FILE}}|$$ERROR_LOG_FILE|g" \
	    config/com.local.run-comfyui.plist.template > "$(PLIST)"'
	@plutil -lint "$(PLIST)"
	@echo "Installed plist: $(PLIST)"

remove-plist:
	@launchctl bootout "$(DOMAIN)" "$(PLIST)" 2>/dev/null || true
	@rm -f "$(PLIST)"
	@echo "Removed plist: $(PLIST)"

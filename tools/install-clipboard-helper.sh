#!/bin/sh
# Lan Mouse Pro - clipboard helper installer (self-contained).
#
# The Lan Mouse protocol has no clipboard messages, so text
# clipboard sharing needs this small helper on the PC. Running
# this script once installs it as a systemd user service:
#
#   sh install-clipboard-helper.sh
#
# Remove it again with:
#
#   sh install-clipboard-helper.sh uninstall
#
# Requirements: python3 and wl-clipboard (wl-paste / wl-copy).
set -e

BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE="lan-mouse-clipboard.service"
TARGET="$BIN_DIR/lan-mouse-clipboard-helper.py"

if [ "$1" = "uninstall" ]; then
    systemctl --user disable --now "$SERVICE" 2>/dev/null || true
    rm -f "$UNIT_DIR/$SERVICE" "$TARGET"
    systemctl --user daemon-reload
    echo "Clipboard helper removed."
    exit 0
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 not found - please install Python 3 first."; exit 1; }
command -v wl-paste >/dev/null 2>&1 || { echo "wl-paste not found - please install wl-clipboard first (e.g. sudo pacman -S wl-clipboard / sudo apt install wl-clipboard)."; exit 1; }

mkdir -p "$BIN_DIR" "$UNIT_DIR"

cat > "$TARGET" <<'PYEOF'
#!/usr/bin/env python3
"""Clipboard bridge between this PC and the Lan Mouse Mobile client.

The lan-mouse protocol has no clipboard messages (it is roadmap-only
upstream), so this helper runs next to the daemon and syncs TEXT
clipboards over a tiny UDP protocol on port 4243:

    LMHELLO          phone -> PC (broadcast ok): discovery ping
    LMHERE           PC -> phone: "the PC is here" (learn its address)
    LMCLIP <base64>  both ways: new clipboard text, UTF-8

PC -> phone: the PC clipboard is polled with wl-paste and changes
are pushed to the phone. Phone -> PC: received text is installed
with wl-copy. Each side remembers the hash of the last text it
received/applied and never echoes that text back, so the two
clipboards converge instead of bouncing.

The phone's address is read from the lan-mouse config
(~/.config/lan-mouse/config.toml, the client hostname) and relearned
from any packet the phone sends, so IP changes heal themselves.
"""

import base64
import hashlib
import re
import socket
import subprocess
import threading
import time
from pathlib import Path

PORT = 4243
MAX_TEXT_BYTES = 32768
POLL_SECONDS = 0.8
CONFIG = Path.home() / ".config" / "lan-mouse" / "config.toml"


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def config_phone_ip() -> str | None:
    try:
        m = re.search(r'hostname\s*=\s*"([^"]+)"', CONFIG.read_text())
        if m and re.fullmatch(r"\d+\.\d+\.\d+\.\d+", m.group(1)):
            return m.group(1)
    except OSError:
        pass
    return None


def read_pc_clipboard() -> str | None:
    try:
        r = subprocess.run(
            ["wl-paste", "--no-newline"],
            capture_output=True, timeout=3,
        )
        if r.returncode != 0:
            return None
        return r.stdout.decode("utf-8", errors="replace")
    except Exception:
        return None


def write_pc_clipboard(text: str) -> None:
    try:
        subprocess.run(
            ["wl-copy"], input=text.encode("utf-8"), timeout=3,
        )
    except Exception as e:
        log(f"wl-copy failed: {e}")


class Bridge:
    def __init__(self) -> None:
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("0.0.0.0", PORT))
        ip = config_phone_ip()
        self.phone_addr = (ip, PORT) if ip else None
        self.last_received = ""   # hash of last text applied from phone
        self.last_pc = ""         # hash of last PC clipboard text seen
        self.last_sent = ""       # hash of last text sent to the phone
        log(f"clipboard bridge up; phone from config: {ip}")

    def send(self, payload: bytes, addr) -> None:
        try:
            self.sock.sendto(payload, addr)
        except OSError as e:
            log(f"send failed: {e}")

    def send_clip(self, text: str, addr) -> None:
        raw = text.encode("utf-8")
        if len(raw) > MAX_TEXT_BYTES:
            log(f"clipboard text too large ({len(raw)} B), skipped")
            return
        self.last_sent = text_hash(text)
        self.send(b"LMCLIP " + base64.b64encode(raw), addr)

    def receive_loop(self) -> None:
        while True:
            try:
                data, addr = self.sock.recvfrom(65535)
            except OSError:
                continue
            self.phone_addr = (addr[0], PORT)
            if data == b"LMHELLO":
                self.send(b"LMHERE", addr)
            elif data.startswith(b"LMCLIP "):
                self.send(b"LMHERE", addr)
                try:
                    text = base64.b64decode(data[7:]).decode("utf-8")
                except Exception:
                    continue
                h = text_hash(text)
                if h == self.last_received or h == self.last_sent:
                    continue
                self.last_received = h
                self.last_pc = h
                write_pc_clipboard(text)
                log(f"clipboard <- phone ({len(text)} chars)")

    def poll_loop(self) -> None:
        while True:
            time.sleep(POLL_SECONDS)
            text = read_pc_clipboard()
            if text is None or text == "":
                continue
            h = text_hash(text)
            if h == self.last_pc:
                continue
            self.last_pc = h
            if h == self.last_received:
                continue  # we just applied this from the phone
            if self.phone_addr is not None:
                self.send_clip(text, self.phone_addr)
                log(f"clipboard -> phone ({len(text)} chars)")

    def run(self) -> None:
        if self.phone_addr is not None:
            self.send(b"LMHERE", self.phone_addr)
        threading.Thread(target=self.receive_loop, daemon=True).start()
        self.poll_loop()


if __name__ == "__main__":
    Bridge().run()
PYEOF
chmod +x "$TARGET"

cat > "$UNIT_DIR/$SERVICE" <<EOF
[Unit]
Description=Lan Mouse Pro clipboard bridge
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 $TARGET
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE"
echo "Clipboard helper installed and running (service: $SERVICE)."
echo "Logs: journalctl --user -u $SERVICE -f"

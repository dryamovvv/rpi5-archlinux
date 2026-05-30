#!/bin/bash
set -euo pipefail

USER_NAME="__USER_NAME__"
SWAPFILE_SIZE="__SWAPFILE_SIZE__"
IDENTITY_FILE="/usr/local/lib/rpi5-archlinux/user.json"

log() { echo "firstboot: $*" >&2; }

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
	log "creating user $USER_NAME via useradd"
	useradd -m -G wheel "$USER_NAME"
	if [[ -f "$IDENTITY_FILE" ]]; then
		chpasswd -e <<<"${USER_NAME}:$(python3 -c "
import json
d = json.load(open('$IDENTITY_FILE'))
print(d['privileged']['hashedPassword'][0])
")"
		log "password set from user.json hash"
	else
		passwd -d "$USER_NAME"
	fi
fi

if [[ -n "$USER_NAME" ]]; then
	loginctl enable-linger "$USER_NAME" 2>/dev/null || true

	if [[ -f "/home/.ssh/authorized_keys" ]]; then
		user_home=$(getent passwd "$USER_NAME" | cut -d: -f6)
		if [[ -n "$user_home" && -d "$user_home" ]]; then
			mkdir -p "$user_home/.ssh"
			chmod 0700 "$user_home/.ssh"
			cp "/home/.ssh/authorized_keys" "$user_home/.ssh/"
			chmod 0600 "$user_home/.ssh/authorized_keys"
			chown -R "$USER_NAME:$USER_NAME" "$user_home/.ssh"
		fi
	fi

	if command -v snapper >/dev/null 2>&1 && ! snapper -c user_home list >/dev/null 2>&1; then
		user_home_dir=$(getent passwd "$USER_NAME" | cut -d: -f6)
		if [[ -n "$user_home_dir" && -d "$user_home_dir" ]]; then
			snapper -c user_home create-config "$user_home_dir"
			if [[ -f /etc/snapper/configs/user_home ]]; then
				sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/user_home
				sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/user_home
				sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="4"/' /etc/snapper/configs/user_home
				sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="3"/' /etc/snapper/configs/user_home
			fi
		fi
	fi
fi

if [[ -n "$SWAPFILE_SIZE" ]] && command -v btrfs >/dev/null 2>&1 &&
	[[ "$(findmnt -n -o FSTYPE /)" == "btrfs" ]] &&
	! swapon --show | grep -q /swap/swapfile; then
	if ! mountpoint -q /swap 2>/dev/null; then
		mkdir -p /swap
		mount -t btrfs -o subvol=@swap,noatime,nodatacow "$(findmnt -n -o SOURCE /)" /swap 2>/dev/null || true
	fi
	if mountpoint -q /swap 2>/dev/null; then
		log "creating ${SWAPFILE_SIZE} swapfile (runs in background)..."
		(
			btrfs filesystem mkswapfile --size "$SWAPFILE_SIZE" --uuid clear /swap/swapfile
			grep -q "/swap/swapfile" /etc/fstab 2>/dev/null ||
				echo "/swap/swapfile none swap defaults,pri=1 0 0" >>/etc/fstab
			swapon --fixpgsz /swap/swapfile 2>/dev/null || true
		) &
	fi
fi

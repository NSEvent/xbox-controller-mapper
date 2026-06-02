#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$repo_root/build/remote-mic"
driver_src="$build_dir/ControllerKeysRemoteMic.driver"
helper_src="$build_dir/controllerkeys-remote-mic-capture"
hal_dir="/Library/Audio/Plug-Ins/HAL"
support_dir="/Library/Application Support/ControllerKeys/RemoteMicBridge"
scripts_dir="$support_dir/Scripts"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root; this installer writes /Library and installs a setuid capture helper." >&2
	exit 1
fi

if [ ! -d "$driver_src" ]; then
	echo "Missing built driver: $driver_src" >&2
	exit 1
fi
if [ ! -x "$helper_src" ]; then
	echo "Missing built capture helper: $helper_src" >&2
	exit 1
fi

mkdir -p "$hal_dir" "$scripts_dir"
/usr/sbin/chown -R root:wheel "$support_dir"
/bin/chmod -R go-w "$support_dir"
/usr/bin/ditto "$driver_src" "$hal_dir/ControllerKeysRemoteMic.driver"
/usr/sbin/chown -R root:wheel "$hal_dir/ControllerKeysRemoteMic.driver"
/bin/chmod -R go-w "$hal_dir/ControllerKeysRemoteMic.driver"

for script in \
	apple-tv-remote-packetlogger-live.py \
	apple-tv-remote-pklg-decode.py \
	apple_tv_remote_coreaudio_ring.py \
	apple-tv-remote-mic-probe.swift
do
	/usr/bin/install -o root -g wheel -m 0755 "$repo_root/Scripts/$script" "$scripts_dir/$script"
done

/usr/bin/install -o root -g wheel -m 0755 "$helper_src" "$support_dir/controllerkeys-remote-mic-capture"

/usr/sbin/chown root:wheel "$support_dir/controllerkeys-remote-mic-capture"
/bin/chmod 4755 "$support_dir/controllerkeys-remote-mic-capture"

/usr/bin/killall coreaudiod >/dev/null 2>&1 || true
echo "Installed ControllerKeys Remote Mic driver and capture helper."

#!/usr/bin/env bash
# Bluefin/Razer post-install verification.
# READ-ONLY: does not update, enroll keys, alter boot order, or change configuration.

set -uo pipefail

report="${HOME}/bluefin-verification-$(date -u +%Y%m%d-%H%M%SZ).txt"

section() {
    local title="$1"
    shift
    {
        printf '\n===== %s =====\n' "$title"
        "$@"
    } >>"$report" 2>&1 || {
        printf 'COMMAND FAILED OR FEATURE UNAVAILABLE (exit %s)\n' "$?" >>"$report"
    }
}

capture_shell() {
    local title="$1"
    local command_text="$2"
    {
        printf '\n===== %s =====\n' "$title"
        bash -o pipefail -c "$command_text"
    } >>"$report" 2>&1 || {
        printf 'COMMAND FAILED OR FEATURE UNAVAILABLE (exit %s)\n' "$?" >>"$report"
    }
}

{
    printf 'Bluefin on Razer verification (READ-ONLY)\n'
    printf 'Generated UTC: %s\n' "$(date -u --iso-8601=seconds)"
    printf 'Serial numbers and disk unique IDs are intentionally omitted.\n'
    printf 'Review before sharing: diagnostic logs can still contain filenames or device names.\n'
} >"$report"

section 'OS RELEASE' sh -c 'cat /etc/os-release; printf "\nKernel: "; uname -r'
section 'ATOMIC DEPLOYMENTS' rpm-ostree status
section 'BOOTC STATUS' bootc status
section 'UEFI BOOT ENTRIES' efibootmgr
section 'SECURE BOOT STATE' mokutil --sb-state
capture_shell 'ENROLLED UNIVERSAL BLUE KEYS' "mokutil --list-enrolled | grep -Ei 'ublue|universal|subject|issuer'"
section 'KERNEL LOCKDOWN' sh -c 'cat /sys/kernel/security/lockdown 2>/dev/null || true'
capture_shell 'NVIDIA MODULE SIGNER' "modinfo nvidia 2>/dev/null | grep -E '^(filename|version|signer|sig_key|sig_hashalgo):'"
section 'NVIDIA STATUS' nvidia-smi
capture_shell 'DISPLAY ADAPTERS AND DRIVERS' "lspci -nnk | grep -A4 -Ei 'VGA|3D|Display'"
section 'BLOCK DEVICES' lsblk -e 7 -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,MOUNTPOINTS,MODEL,TRAN
section 'MOUNTS' findmnt --real
section 'FIRMWARE SECURITY' fwupdmgr security
capture_shell 'FIRMWARE DEVICES' "fwupdmgr get-devices | sed -E '/^[[:space:]]*(Device ID|GUID|Serial Number|Instance ID):/d'"
capture_shell 'AVAILABLE FIRMWARE UPDATES' "fwupdmgr get-updates | sed -E '/^[[:space:]]*(Device ID|GUID|Serial Number|Instance ID):/d'"
section 'PODMAN INFO' podman info
section 'DOCKER INFO' docker info
capture_shell 'CONTAINER GPU DEVICES' "find /dev -maxdepth 3 \( -type c -o -type l \) 2>/dev/null | grep -E 'nvidia|dri' | sort"
capture_shell 'AUDIO SERVER' "wpctl status 2>/dev/null || pactl info 2>/dev/null"
section 'SLEEP MODES' sh -c 'cat /sys/power/mem_sleep 2>/dev/null; systemctl status nvidia-suspend.service nvidia-resume.service --no-pager 2>/dev/null || true'
section 'FAILED SERVICES' systemctl --failed --no-pager
capture_shell 'RECENT HIGH-PRIORITY KERNEL ERRORS' "journalctl -b -p warning..alert --no-pager | tail -n 250"

digest="$(sha256sum "$report" | awk '{print $1}')"
printf 'Read-only verification finished.\nReport: %s\nSHA256: %s\n' "$report" "$digest"
printf 'Manual tests still required: displays, brightness, Wi-Fi, Bluetooth, audio, webcam, USB, thermals, and five suspend/resume cycles.\n'

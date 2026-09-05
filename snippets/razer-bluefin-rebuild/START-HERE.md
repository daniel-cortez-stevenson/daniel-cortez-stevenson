# Razer Blade 15 (2022) secure rebuild runbook

Target reported by the current installation: **Razer Blade 15 (2022), RZ09-0421x, Intel/NVIDIA hybrid graphics, RTX 3080 Ti**.

This runbook deliberately stops before each irreversible action. Do not skip a gate. Commands marked **READ-ONLY** collect information. A wipe or firmware operation is never launched by the supplied scripts.

## Intended final architecture

Do not put Bluefin and Windows on different partitions of the same SSD. Bluefin explicitly says that dual boot from one disk is unsupported and recommends a dedicated disk plus the firmware boot selector.

Recommended layout:

| Physical device | Contents | Filesystem/encryption | Purpose |
|---|---|---|---|
| Original 1 TB NVMe | Windows 11 Home | NTFS + BitLocker | Rekordbox, Razer firmware tools, Windows-only software |
| New 2 TB or 4 TB NVMe | Bluefin LTS NVIDIA Stable | Installer-managed Linux layout + full-disk encryption | Primary OS, containers, models, Whisper, embeddings, development |
| Optional external/NAS volume | Shared data only | Chosen separately | Deliberate interchange and backup |

Bluefin should be first in the UEFI boot order. Each SSD should have its own EFI System Partition and boot independently. Use the Razer boot menu to start Windows; do not make one operating system's bootloader responsible for the other.

### What happens to the remaining storage?

There is no safe, native filesystem that simultaneously gives Windows and Linux their best security and reliability characteristics:

- Bluefin's Linux filesystem is not natively writable by Windows.
- NTFS is writable by Linux, but Windows hibernation/Fast Startup must be disabled before Linux writes to it.
- BitLocker is not a convenient shared-filesystem solution for Bluefin.
- exFAT is interoperable but lacks journaling and Unix permissions; it is poor storage for containers, models, databases, or a sole music-library copy.

Therefore, let each OS own its physical SSD initially. After both installations are stable, choose one of these:

1. **Recommended:** no internal shared partition. Exchange files through an external encrypted SSD, NAS, or explicitly synchronized directory.
2. **DJ convenience:** shrink Windows and create a separate 250-500 GB NTFS `SHARED` volume. Disable Windows hibernation/Fast Startup with `powercfg.exe /hibernate off`. Keep backups and do not place container storage, Linux home directories, databases, or model caches there. If it must be confidential in both systems, design a VeraCrypt-based shared volume later.
3. **One SSD only:** do not install Bluefin. Use Ubuntu/Kubuntu/Ubuntu Studio for a conventional supported same-disk dual boot, or postpone Linux until a second SSD is installed.

## Trust model: what “completely wipe” can mean

| Level | Action | What it addresses |
|---|---|---|
| Rebuild | Delete every old partition and install from trusted media | Old OS, OEM recovery, boot files, applications, user data |
| NVMe sanitize | Controller-supported sanitize/format from trusted boot media | Remnant user data, including areas ordinary partition deletion may not address |
| Replace SSD | Install a new NVMe | Old drive contents and concern about that drive's controller/firmware |
| OEM firmware update | Apply exact Razer BIOS/EC/keyboard packages | Rewrites the regions that Razer's signed updater is designed to update |
| Hardware-forensic assurance | External SPI programming or motherboard replacement | Higher-assurance response to a credible firmware implant concern |

An OEM BIOS updater is not a byte-for-byte replacement of every programmable component. For an ordinary used-laptop threat model, a trusted clean installation, exact OEM firmware updates, factory Secure Boot keys, a cleared TPM, encryption, and new credentials are proportionate. If there is evidence of targeted compromise, return the laptop or use a qualified service rather than treating a consumer updater as forensic proof.

---

# PHASE 0 — collect state

## Gate 0: nothing destructive yet

1. Copy `01-collect-prewipe-state.ps1` to the laptop.
2. Open PowerShell **as Administrator** in that directory.
3. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\01-collect-prewipe-state.ps1
```

The script creates a timestamped text report on the Desktop. Send that report back before proceeding. It intentionally omits serial numbers, full license keys, device IDs, tenant IDs, and disk unique IDs.

**STOP 0:** Do not wipe anything until the report confirms the exact model, Windows edition/activation, BIOS version, TPM/Secure Boot state, and number/size of NVMe drives.

Optional: if the current wallpaper is what you meant by the desktop being beautiful, copy only the image—not OEM programs or recovery files—before wiping:

```powershell
$wallpaper = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
if (Test-Path -LiteralPath $wallpaper) {
    $extension = [IO.Path]::GetExtension($wallpaper)
    $destination = Join-Path ([Environment]::GetFolderPath('Desktop')) "current-wallpaper-backup$extension"
    Copy-Item -LiteralPath $wallpaper -Destination $destination
}
```

Treat anything recovered from the old installation as untrusted data. Do not preserve executables, drivers, scripts, browser profiles, or the Razer recovery partition.

---

# PHASE 1 — storage decision and installation media

## Gate 1: decide the physical disk layout

Proceed with Bluefin only when two internal NVMe devices are present:

- Identify the original 1 TB SSD from the audit.
- Install a new 2 TB minimum or 4 TB preferred NVMe in the second M.2 slot.
- Record each drive's manufacturer, model, and capacity on paper.

If only one NVMe is present, **STOP 1**. Install the second SSD first or choose Ubuntu instead of Bluefin.

## Create media on another trusted computer

Use two different USB drives. Disconnect all backup and external data drives before any installer is booted.

### Windows 11 USB

Use Microsoft's current Media Creation Tool:

<https://www.microsoft.com/software-download/windows11>

The existing license is Windows 11 Home, so reinstall **Home**, not Pro. A matching firmware-embedded or digital license normally activates automatically.

### Bluefin LTS NVIDIA USB

The former **Bluefin GDX LTS** image is being consolidated into **Bluefin LTS NVIDIA**. The intended installed stream is:

`ghcr.io/projectbluefin/bluefin-lts-nvidia:stable`

Use the current official **Bluefin LTS → NVIDIA** download. During the naming transition the official ISO may still be called:

`bluefin-gdx-lts-x86_64.iso`

Download page:

<https://docs.projectbluefin.io/downloads/>

Download its accompanying checksum file and verify it on a trusted machine.

Do not infer an ISO URL or download a historical mirror. Follow the current official NVIDIA/LTS link and use the checksum offered next to that exact download. Put only that Bluefin ISO and its checksum file in a new directory, open a shell there, and verify them.

PowerShell:

```powershell
$iso = @(Get-ChildItem -File '*.iso')
$checksum = @(Get-ChildItem -File '*CHECKSUM*')
if ($iso.Count -ne 1 -or $checksum.Count -ne 1) { throw 'Expected exactly one ISO and one CHECKSUM file.' }
Get-FileHash -LiteralPath $iso[0].FullName -Algorithm SHA256
Get-Content -LiteralPath $checksum[0].FullName
```

Linux:

```bash
set -- ./*.iso
[ "$#" -eq 1 ] || { echo 'Expected exactly one ISO'; exit 1; }
sha256sum -c ./*CHECKSUM*
```

The calculated digest must exactly equal the published digest. Use **Fedora Media Writer**, which Bluefin recommends; Ventoy is explicitly unsupported. Writing an installer USB is intentionally not scripted here because selecting the wrong removable device would destroy it.

Keep Secure Boot enabled when testing the Bluefin USB. Bluefin's documentation is temporarily inconsistent during the GDX/LTS migration, so successful Secure Boot of the exact ISO is an explicit acceptance gate—not an assumption.

**STOP 2:** Confirm that both USB drives boot in UEFI mode, that the Bluefin checksum matches, and that the Bluefin live environment starts with Secure Boot still enabled. If the LTS NVIDIA image will not boot securely, use normal `bluefin-nvidia-open-stable-x86_64.iso` as the fallback; do not permanently weaken Secure Boot for the preferred image.

---

# PHASE 2 — establish a clean Windows firmware-service installation

Windows goes first because the official Razer firmware updaters are Windows applications.

## Gate 2: isolate the Windows target

For the safest installation:

1. Power off and unplug the laptop.
2. Leave only the original 1 TB SSD installed, or disable the new SSD in firmware if the firmware genuinely exposes that option.
3. Insert only the Microsoft installer USB.
4. Boot its **UEFI** entry from the Razer boot menu.

Do not depend on disk numbering when two drives are attached. Windows Setup's `Disk 0` label is not a stable physical identity.

## Clean installation

Select Windows 11 Home and a custom installation. On the isolated original SSD, delete every partition—including the old OEM Recovery partition—until only unallocated space remains. Install into that unallocated space.

This is the first irreversible operation.

**STOP 3:** Confirm physically that only the intended original SSD is connected before deleting partitions.

Do not restore a Razer recovery image. Do not import drivers from the old installation. Let Windows Update obtain its baseline drivers.

## Update the clean Windows baseline

1. Complete Windows Setup with a temporary local/admin account if available in the installer flow.
2. Run Windows Update repeatedly, including applicable firmware/driver updates, rebooting until it is settled.
3. Confirm Windows Home activation.
4. Do not enable BitLocker yet; firmware and partition decisions come first.

## Apply only exact Razer firmware

First confirm the computer reports `RZ09-0421x`. Then use only these official Razer pages:

- Model support hub: <https://mysupport.razer.com/app/answers/detail/a_id/5900>
- Firmware/BIOS index: <https://mysupport.razer.com/app/answers/detail/a_id/4166>
- Current RZ09-0421x customer firmware: <https://mysupport.razer.com/app/answers/detail/a_id/14711>
- RZ09-0421x EC and keyboard updater: <https://mysupport.razer.com/app/answers/detail/a_id/9727>
- RZ09-0421x BIOS updater: <https://mysupport.razer.com/app/answers/detail/a_id/9729>

Rules:

- The updater title and detected model must both say RZ09-0421x.
- Follow the order and prerequisites on the current Razer pages; do not assume a version number from this document.
- Use the original AC adapter and ensure the battery is charged.
- Suspend BitLocker if it somehow became enabled.
- Close applications and never interrupt power or force a reboot during a flash.
- Never use a third-party BIOS image, modded BIOS, generic driver updater, or force-flash option.

If an updater rejects the model, reports an unexpected downgrade, cannot update after a clean Windows installation, or the firmware asks for an unknown administrator password, **STOP 4** and return/escalate the laptop.

## Reset ownership-related firmware state

After successful official updates, enter firmware directly:

```powershell
shutdown.exe /r /fw /t 0
```

The unavoidable firmware-menu checks are:

- Load factory/optimized defaults.
- UEFI-only boot; disable Legacy/CSM.
- Restore factory/default Secure Boot keys if the firmware exposes key management.
- Enable TPM/Intel PTT.
- Enable CPU virtualization and IOMMU/VT-d.
- Disable network/PXE boot unless needed.
- Inspect for an unknown firmware administrator password or unexpected Absolute/Computrace/enterprise-management state.

Do not permanently disable an Absolute/Computrace option casually; some firmware makes that selection irreversible. If it is activated or managed unexpectedly, stop and investigate ownership.

Back in Windows, after confirming there is no data to retain, clear old TPM ownership using Windows—not a generic firmware-menu command:

```powershell
Clear-Tpm
```

This destroys TPM-protected keys and may require a physical-presence confirmation during reboot. It is appropriate only because the old installation is being discarded.

Run `02-verify-clean-windows.ps1` as Administrator and retain its report.

**STOP 5:** Send or inspect the clean-Windows report. Require: activated Windows Home, Secure Boot enabled, TPM ready, expected BIOS version, no unexplained firmware/device errors.

---

# PHASE 3 — optional shared-data decision

The default recommendation is **no shared internal partition yet**. Let Windows use the original SSD and Bluefin use the new SSD.

If a shared DJ/music volume is required, make that decision only after both operating systems pass verification. The exact resize/create command must be generated from the final disk report; do not paste a generic `diskpart clean`, `Resize-Partition`, `nvme format`, or `nvme sanitize` command.

If Windows data will ever be written from Linux, disable hibernation and Fast Startup first:

```powershell
powercfg.exe /hibernate off
```

Then shut Windows down fully before mounting its shared NTFS volume from Linux:

```powershell
shutdown.exe /s /t 0
```

---

# PHASE 4 — install Bluefin LTS NVIDIA on its own SSD

## Gate 4: isolate the Bluefin target

1. Shut down fully.
2. Disconnect/remove the Windows SSD temporarily, or disable it in firmware if supported.
3. Install the new 2/4 TB SSD as the only enabled internal target.
4. Boot the verified Bluefin USB in UEFI mode.

If the installer does not show exactly one internal target of the new SSD's expected model and capacity, **STOP 6**.

## Install

Use automatic partitioning across the **entire new SSD**, as Bluefin recommends. Enable disk encryption if the installer presents the option. If full-disk encryption is missing or the proposed storage screen is ambiguous, stop and take a photograph before committing.

Install with Secure Boot enabled. If the firmware refuses the LTS NVIDIA installer, stop and use the normal Bluefin NVIDIA Stable fallback. Do not install an operating system that requires Secure Boot to remain disabled.

During the MOK screen on first boot:

1. Select **Enroll MOK**.
2. Confirm the key.
3. Enter the documented one-time password: `universalblue`.
4. Reboot.

If the enrollment screen is missed, Bluefin documents:

```bash
ujust enroll-secure-boot-key
```

After enrollment, ensure Secure Boot is enabled in firmware.

On the first desktop boot, update before adding accounts or secrets:

```bash
ujust update
systemctl reboot
```

After reboot, enable Bluefin's developer environment and inspect the installed image:

```bash
ujust devmode
bootc status
```

The booted image should be `ghcr.io/projectbluefin/bluefin-lts-nvidia:stable` or its explicitly documented successor. A legacy `ublue-os/bluefin-gdx:lts` installation must complete its supported automatic migration and reboot before acceptance. Do not manually rebase between normal Bluefin and Bluefin LTS; Bluefin documents that path as unsupported.

The former GDX monolithic AI payload is moving into userspace. Consume CUDA frameworks through signed containers and install user tools through Bluefin's supported Brew/container workflow; do not layer random CUDA or NVIDIA RPMs onto the host. `ujust aimode` was announced but was not yet available when this runbook was written, so it is deliberately not used here.

## Reconnect Windows and make Bluefin default

1. Shut down and reconnect the Windows SSD.
2. Start Bluefin using the firmware boot menu.
3. Run `03-verify-bluefin.sh` and retain its report.
4. Inspect `efibootmgr` in the report.

Do not script `efibootmgr -o` until the actual Bluefin and Windows boot-entry numbers are known. After the report identifies them, either set Bluefin first in the firmware UI or generate one exact `efibootmgr -o` command. Use the firmware boot menu when Windows is wanted.

**STOP 7:** Bluefin is accepted only if Secure Boot, its enrolled key, NVIDIA, the internal display, external display, audio, Wi-Fi, Bluetooth, suspend/resume, thermals, and repeated updates behave correctly.

---

# PHASE 5 — acceptance test before committing secrets

Run through all of the following before treating Bluefin as trusted production equipment:

- `mokutil --sb-state` says SecureBoot enabled.
- `nvidia-smi` sees the RTX 3080 Ti without errors.
- A GPU-enabled container can execute `nvidia-smi`.
- Internal 4K/144 Hz modes and brightness work.
- External display outputs work.
- Suspend/resume works at least five times, including once on battery.
- Wi-Fi, Bluetooth, speakers, microphone, webcam, keyboard, trackpad, and USB work.
- Idle and sustained-load temperatures are reasonable; no battery swelling is visible.
- `fwupdmgr security` is reviewed; unsupported checks are distinguished from failures.
- Bluefin can update and reboot, and the previous deployment is available for rollback.
- Windows independently boots from its own drive and remains activated.

Only after acceptance:

- Set your own firmware administrator password and store it in your password manager.
- Enable BitLocker on the Windows OS volume and retain its recovery key outside the laptop.
- Confirm Bluefin disk encryption and retain its recovery material outside the laptop.
- Enroll personal accounts, SSH keys, passkeys, API credentials, or private repositories.

If Bluefin fails the hybrid-NVIDIA, suspend, or thermal acceptance tests, replace only the Linux SSD installation with Ubuntu Studio/Kubuntu/Ubuntu 26.04 LTS. Leave the clean Windows SSD intact.

## Primary sources

- Bluefin installation, dedicated-drive, NVIDIA-laptop and Secure Boot guidance: <https://docs.projectbluefin.io/installation/>
- Bluefin current downloads: <https://docs.projectbluefin.io/downloads/>
- Bluefin LTS description and limitations: <https://docs.projectbluefin.io/lts/>
- Bluefin GDX/LTS NVIDIA migration: <https://docs.projectbluefin.io/blog/>
- Bluefin GDX purpose and legacy ISO name: <https://docs.projectbluefin.io/gdx/>
- Microsoft installation-media instructions: <https://support.microsoft.com/en-us/windows/deployment/install-upgrade/create-installation-media-for-windows>
- Microsoft clean-install instructions: <https://support.microsoft.com/en-us/windows/deployment/install-upgrade/reinstall-windows-with-the-installation-media>
- Razer RZ09-0421x support hub: <https://mysupport.razer.com/app/answers/detail/a_id/5900>

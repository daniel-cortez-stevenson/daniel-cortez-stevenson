# Razer Blade 15 (2022) secure rebuild runbook

Target reported by the current installation: **Razer Blade 15 (2022), RZ09-0421x, Intel/NVIDIA hybrid graphics, RTX 3080 Ti**.

This runbook deliberately stops before each irreversible action. Do not skip a gate. Commands marked **READ-ONLY** collect information. A wipe or firmware operation is never launched by the supplied scripts.

## Audited baseline for this laptop

Audit received 2026-09-06. These observations apply to this machine, not to every RZ09-0421x:

| Check | Observed | Decision |
|---|---|---|
| BIOS | Razer 2.00, released 2022-06-24 | Update required. The current exact-model release observed during this review is 2.06; re-check Razer immediately before flashing. |
| Boot security | UEFI, Secure Boot enabled, TPM present/ready/enabled | Preserve Secure Boot; clear old TPM ownership only after data recovery. |
| Ownership indicators | No Azure AD, Enterprise, domain, workplace, or local Autopilot assignment indicators | Good local result, but a clean Windows OOBE check is still required because cloud Autopilot registration is not disproved by local registry state. |
| Internal storage | One healthy 1 TB Samsung NVMe; reported wear 0 | Safe candidate for whole-disk Bluefin after backups and exact-device confirmation. |
| Battery | 80.219 Wh design, 74.459 Wh full-charge (~92.8%) | Capacity passes. Inspect physically for swelling before firmware work. |
| CPU virtualization | Supported, but disabled in firmware | Enable Intel virtualization and VT-d/IOMMU after loading BIOS defaults. |

## Important image correction after re-checking Bluefin

This Intel-plus-NVIDIA laptop is a **dual-GPU NVIDIA laptop**, which Bluefin currently places in support Tier 3 and recommends Ubuntu or a custom image for if testing fails. Bluefin LTS/GDX currently also documents Secure Boot and hibernation as mutually exclusive and says its LTS images are not Secure-Boot-enabled.

Therefore this runbook's security-preserving default is now **normal Bluefin NVIDIA Stable**, using the current official `bluefin-nvidia-open-stable-x86_64.iso`. It keeps Secure Boot as an acceptance requirement and still provides Bluefin's container-first development and local-AI tooling. Do not substitute Bluefin GDX/LTS unless its official documentation later says the exact image supports Secure Boot, or you consciously decide that leaving Secure Boot off is acceptable. For this used machine, that trade is not recommended.

## Intended architecture: one SSD now, two SSDs later

Do not divide the current internal SSD between Bluefin and Windows. Bluefin explicitly says same-disk dual boot is unsupported and recommends a dedicated drive with automatic partitioning.

### Stage A — today

| Physical device | Contents | Purpose |
|---|---|---|
| Internal 1 TB NVMe | **Bluefin NVIDIA Stable**, installer-managed encryption | Primary OS; the entire terabyte is available to Linux, containers, models, Whisper, embeddings, and development |
| External backup drive | Selected personal data; official Windows installer files; optionally a quarantined image of the old SSD | Recovery/archive only; it is not trusted as an operating system |
| Separate USB stick | Verified Bluefin installer | Installation/recovery media |
| Separate USB stick | Official Windows 11 installer | A clean way to reinstall the licensed Windows edition later |

### Stage B — after adding another internal NVMe

| Physical device | Contents | Purpose |
|---|---|---|
| Current internal 1 TB NVMe | Bluefin NVIDIA Stable | Primary OS |
| New internal NVMe | Fresh Windows 11 Home + BitLocker | Rekordbox, Razer firmware tools, and other Windows-only software |

Each internal SSD will then have its own EFI System Partition and boot independently. Keep Bluefin first in the UEFI boot order and use the Razer firmware boot menu when Windows is wanted. Do not make one operating system's bootloader responsible for the other.

### “Preserving Windows” does not require preserving this installation

The Windows **license** and the Windows **installation currently on disk** are different things. Microsoft documents that a digital license is associated with the device hardware and that the same Windows edition can be reinstalled on the same device without entering a product key. The audit records the installed edition and activation state without exposing the full key.

For this used machine, the preferred recovery set is:

1. An official Windows 11 installer USB.
2. A backup of known personal files and configuration exports.
3. The audit report showing Windows 11 Home activation and whether an OEM key exists in firmware.
4. Optionally, a full image of the old SSD labelled **UNTRUSTED — DO NOT BOOT**.

Do not clone the seller's Windows installation to an external drive and then treat it as trusted. That preserves exactly the software and configuration the rebuild is intended to eliminate.

### Can Windows boot from an external drive temporarily?

Only as a compromise. Microsoft removed Windows To Go in Windows 10 version 2004, so a current portable Windows installation made with Rufus, WinToUSB, or similar tooling is not a Microsoft-supported deployment.

- Do not attempt it on a USB thumb drive or spinning hard disk.
- A fresh installation on a fast external NVMe SSD in a reliable USB 3.2 Gen 2 or Thunderbolt enclosure can be usable for occasional Windows access.
- Expect rough edges around updates, sleep, BitLocker, device removal, audio latency, and performance.
- Do not use portable Windows to flash BIOS/EC firmware or for a live Rekordbox performance.
- Never boot the quarantined image of the old installation as the temporary Windows environment.

If Windows is needed before the second internal SSD arrives, either use a fresh Windows virtual machine for ordinary applications or deliberately create a fresh portable Windows environment on an external NVMe. Otherwise, skip portable Windows entirely.

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

## Use native 64-bit Windows Terminal

**Windows Terminal is the window; PowerShell is the shell running inside its tab.** Close the legacy window titled `Windows PowerShell (x86)`. On 64-bit Windows, that shortcut redirects `System32` commands and caused the earlier `dsregcmd.exe` and `powercfg.exe` failures.

Open the correct terminal without navigating German menus:

1. Press the Windows key, type `Terminal`, and press **Ctrl+Shift+Enter**.
2. Approve the administrator prompt.
3. In the tab menu, choose **Windows PowerShell** or **PowerShell**—never a profile containing `(x86)`.
4. Paste this architecture check:

```powershell
[pscustomobject]@{
    ProcessIs64Bit = [Environment]::Is64BitProcess
    ProcessBits = [IntPtr]::Size * 8
    PowerShellHome = $PSHOME
}
```

Require `ProcessIs64Bit : True` and `ProcessBits : 64`. The two supplied `.ps1` files also detect a 32-bit host and relaunch themselves in native 64-bit Windows PowerShell, but starting in the correct terminal makes every interactive command behave consistently.

PowerShell navigation for a Linux/macOS user:

| Goal | PowerShell command |
|---|---|
| Show the current directory | `pwd` |
| Go to Downloads | `cd $HOME\Downloads` |
| List files | `dir` or `Get-ChildItem` |
| List PowerShell scripts | `dir *.ps1` |
| Open the current folder in Explorer | `explorer.exe .` |
| Read a text file | `Get-Content .\file.txt` |
| Locate a command | `Get-Command command-name` |
| Run a script in this directory | `& .\script-name.ps1` |
| Complete a path/command | Press **Tab** |
| Recall the previous command | Press **Up Arrow** |
| Stop the current command | Press **Ctrl+C** |

The `&` is PowerShell's call operator, and `.` means the current directory. Unlike Bash, PowerShell normally requires `.\` when executing a file from the current directory. Avoid `Remove-Item`/`rm` while learning: deletion is not a trip to the Recycle Bin.

## Gate 0: nothing destructive yet

1. Copy `01-collect-prewipe-state.ps1` to the laptop.
2. Open native 64-bit Windows Terminal **as Administrator** and select a PowerShell tab.
3. Run:

```powershell
cd $HOME\Downloads
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\01-collect-prewipe-state.ps1
```

The script creates a timestamped text report on the Desktop. Send that report back before proceeding. It intentionally omits serial numbers, full license keys, device IDs, tenant IDs, and disk unique IDs.

**STOP 0:** Do not wipe anything until the report confirms the exact model, Windows edition/activation, BIOS version, TPM/Secure Boot state, battery health, ownership indicators, virtualization state, and number/size of NVMe drives. This audited laptop passed the information-collection gate; its BIOS update and virtualization changes remain outstanding.

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

# PHASE 1 — backup, license evidence, and installation media

## Gate 1: identify the only internal disk and the external targets

From the audit, write down the internal NVMe's manufacturer, model, and capacity. The intended destructive target is the single internal 1 TB NVMe. Bluefin will own all of it.

Before connecting backup media, list the current disks:

```powershell
Get-Disk | Sort-Object Number | Format-Table Number,FriendlyName,SerialNumber,BusType,PartitionStyle,Size -AutoSize
```

Connect the external backup drive, run the command again, and identify the new device by model, serial number, bus type, and capacity. Do not identify a destructive target by `Disk 0` alone.

Back up only deliberate personal data: documents, source code, music projects, license/deactivation information, and the wallpaper if wanted. Do not carry forward executables, drivers, scheduled tasks, browser profiles, recovery partitions, or OEM utilities from the old installation.

If a forensic-style full image is desired, create it from trusted Rescuezilla/Clonezilla media and label it **UNTRUSTED — DO NOT BOOT**. This is optional and is not needed to retain the Windows license. The destination must have enough free space; a raw uncompressed image may require approximately the full 1 TB capacity.

## Create media on another trusted computer

Use two different USB drives. Disconnect all backup and external data drives before any installer is booted.

### Windows 11 USB

Use Microsoft's current Media Creation Tool:

<https://www.microsoft.com/software-download/windows11>

The existing license is Windows 11 Home, so reinstall **Home**, not Pro. A matching digital or firmware-embedded license should reactivate automatically on the same device. Keep this installer after Bluefin is installed; it is the clean Windows recovery path for the future second SSD.

### Bluefin NVIDIA Stable USB

Use the current official **Bluefin → NVIDIA** download. For this x86-64 Intel/NVIDIA laptop, the expected filename at the time of this review is:

`bluefin-nvidia-open-stable-x86_64.iso`

Do **not** choose `bluefin-gdx-lts-x86_64.iso` for this rebuild. GDX is the NVIDIA/CUDA edition of Bluefin LTS, but the current LTS documentation says those images are not Secure-Boot-enabled. Normal Bluefin also includes its developer and local-AI workflow; add tools in userspace or signed containers after the machine passes acceptance testing.

Download page:

<https://docs.projectbluefin.io/downloads/>

Download its accompanying checksum file and verify it on a trusted machine.

Do not infer an ISO URL or download a historical mirror. Follow the current official Bluefin NVIDIA link and use the checksum offered next to that exact download. Put only that Bluefin ISO and its checksum file in a new directory, open a shell there, and verify them.

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

Keep Secure Boot enabled when testing the Bluefin USB. Successful Secure Boot of the exact ISO is an explicit acceptance gate—not an assumption. Because Bluefin classifies dual-GPU NVIDIA laptops as Tier 3, display switching, suspend, external monitors, thermals, and NVIDIA containers must all be tested before secrets are enrolled.

**STOP 2:** Confirm the backup opens on another trusted computer, both USB drives boot in UEFI mode, the Bluefin checksum matches, and `bluefin-nvidia-open-stable-x86_64.iso` starts with Secure Boot still enabled. If it will not boot securely or the hybrid GPU behaves badly, use Ubuntu as the fallback; do not permanently weaken Secure Boot to force Bluefin onto this used laptop.

---

# PHASE 2 — firmware decision before erasing Windows

The official Razer firmware updaters are Windows applications. That creates one important gate: decide whether the machine needs a BIOS, EC, or keyboard-firmware update **before** giving the internal SSD to Bluefin.

**This laptop is Gate 2B, not Gate 2A.** Its audit reports BIOS 2.00 dated 2022-06-24. The current exact-model release found during the 2026-09-06 review is 2.06. Treat the exact Razer page and the signed updater's detected model/version as the source of truth at flash time; never force a downgrade or install a package merely because its filename resembles the expected one.

First confirm the audit reports `RZ09-0421x`. Compare its BIOS/EC versions with the current exact-model packages on these official Razer pages:

- Model support hub: <https://mysupport.razer.com/app/answers/detail/a_id/5900>
- Firmware/BIOS index: <https://mysupport.razer.com/app/answers/detail/a_id/4166>
- Current RZ09-0421x customer firmware: <https://mysupport.razer.com/app/answers/detail/a_id/14711>
- RZ09-0421x EC and keyboard updater: <https://mysupport.razer.com/app/answers/detail/a_id/9727>
- RZ09-0421x BIOS updater: <https://mysupport.razer.com/app/answers/detail/a_id/9729/~/razer-blade-15-%282022%29-bios-updater-%7C-rz09-0421x>

## Gate 2A: firmware is already current

This branch does not apply to the audited BIOS 2.00 state. On a later run, if the exact-model Razer pages and updater confirm that BIOS/EC/keyboard firmware is current, do not reflash merely for reassurance. Proceed to the ownership-state reset below and then the Bluefin installation.

## Gate 2B: firmware needs an update

Do not flash firmware from the seller's old Windows installation or from an unofficial portable Windows environment. The safest sequence is:

1. Confirm the backup and installer USBs.
2. Boot the official Microsoft USB in UEFI mode.
3. Select Windows 11 Home and a custom installation.
4. Delete every partition on the **single verified internal 1 TB NVMe** and install into the resulting unallocated space.
5. During Windows out-of-box setup, **stop** if organization branding appears or Windows requires an unfamiliar work/school account. Local checks cannot disprove a cloud-side Autopilot registration; contact the seller before proceeding if enrollment is imposed.
6. Let Windows Update establish a clean baseline; do not import old drivers or OEM recovery software.
7. Confirm activation, leave BitLocker off temporarily, and apply only the exact Razer packages.
8. Run `02-verify-clean-windows.ps1` from native 64-bit Windows Terminal and retain the report.
9. After firmware verification, this temporary Windows installation will itself be erased by the Bluefin installer.

This temporary clean-Windows cycle is extra work, but it keeps firmware flashing on the supported internal-Windows path.

**STOP 3:** The partition deletion in step 4 is irreversible. Before doing it, disconnect every external data/backup drive and physically confirm that the installer shows only the intended internal 1 TB NVMe.

Firmware rules:

- The updater title and detected model must both say RZ09-0421x.
- The expected BIOS target from this review is 2.06 or a newer exact-model successor shown by Razer. If the page/updater offers something different, stop and verify rather than forcing it.
- Follow the order and prerequisites on the current Razer pages.
- Use the original AC adapter and ensure the battery is charged.
- Inspect the chassis, trackpad, and bottom cover for battery swelling before flashing. Do not flash a swollen or unstable laptop.
- Suspend BitLocker if it somehow became enabled.
- Close applications and never interrupt power or force a reboot during a flash.
- Never use a third-party BIOS image, modded BIOS, generic driver updater, or force-flash option.

If an updater rejects the model, reports an unexpected downgrade, cannot update after a clean Windows installation, or the firmware asks for an unknown administrator password, **STOP 4** and return/escalate the laptop.

## Reset ownership-related firmware state

After confirming current firmware or completing the exact official updates, enter firmware directly:

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

If a clean Windows firmware-service installation was performed, clear old TPM ownership after confirming there is no data to retain:

```powershell
Clear-Tpm
```

This destroys TPM-protected keys and may require a physical-presence confirmation during reboot. It is appropriate only because the old installation is being discarded.

Run `02-verify-clean-windows.ps1` as Administrator from native 64-bit Windows Terminal and retain its report:

```powershell
cd $HOME\Downloads
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\02-verify-clean-windows.ps1
```

The report must say `PowerShell process: 64-bit`, show BIOS 2.06 or the currently documented exact-model successor, and show `VirtualizationFirmwareEnabled : True`. If firmware was already current and the clean-Windows cycle was skipped, retain the original audit plus photographs of the reviewed firmware settings instead.

**STOP 5:** Require: backup verified; Windows edition/activation recorded; BIOS 2.06 or current exact-model successor; factory Secure Boot keys restored; Secure Boot enabled; TPM/PTT, Intel virtualization, and VT-d/IOMMU enabled; no unknown firmware password or unexplained ownership/management state.

---

# PHASE 3 — install Bluefin across the entire internal SSD

## Gate 3: isolate the Bluefin target

1. Shut down fully.
2. Disconnect every external backup, archive, and Windows drive.
3. Leave only the verified Bluefin installer USB attached.
4. Boot the USB's UEFI entry with Secure Boot enabled.
5. Confirm the installer shows exactly one internal target matching the audited 1 TB NVMe model and capacity.

If any other internal target appears, or the model/capacity does not match, **STOP 6**. Do not guess from disk numbers.

## Install

Use automatic partitioning across the **entire internal 1 TB SSD**, as Bluefin recommends. This deletes the temporary or old Windows installation, OEM recovery partition, boot files, and all remaining data on that drive. Enable disk encryption if the installer presents the option. If encryption is missing or the proposed storage screen is ambiguous, stop and take a photograph before committing.

**STOP 7 — final wipe confirmation:** Verify the backup again, confirm the target's model and capacity, and confirm every external data drive is disconnected. Only then approve the installer's destructive operation.

Install `bluefin-nvidia-open-stable-x86_64.iso` with Secure Boot enabled. If the firmware refuses it, stop and use the Ubuntu fallback. Do not switch to GDX/LTS or another image that requires Secure Boot to remain disabled.

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

The booted deployment must identify itself as the normal Bluefin NVIDIA Stable family corresponding to the verified ISO. Record the exact image printed by `bootc status`; do not guess or manually switch to an image name copied from this document. Do not rebase between normal Bluefin and Bluefin LTS/GDX—Bluefin documents that boundary as unsupported and requires a fresh installation or an explicitly supported migration.

Install AI tools through Bluefin's supported userspace/container workflow; do not layer random CUDA or NVIDIA RPMs onto the host. Current Bluefin documentation provides GPU acceleration, Ramalama/Docker model workflows, and `whisper-cpp` through its Brew selection. Confirm GPU access inside the actual Whisper/embedding containers before making them always-on services.

Run `03-verify-bluefin.sh` and retain its report.

Bluefin is accepted only if Secure Boot, its enrolled key, NVIDIA, the internal display, external display, audio, Wi-Fi, Bluetooth, suspend/resume, thermals, and repeated updates behave correctly.

---

# PHASE 4 — acceptance test before committing secrets

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
- The external backup is readable while connected deliberately and is disconnected when not needed.

Only after acceptance:

- Set your own firmware administrator password and store it in your password manager.
- Confirm Bluefin disk encryption and retain its recovery material outside the laptop.
- Enroll personal accounts, SSH keys, passkeys, API credentials, or private repositories.

If Bluefin fails the hybrid-NVIDIA, suspend, or thermal acceptance tests, replace the Linux installation with Ubuntu Studio/Kubuntu/Ubuntu 26.04 LTS or temporarily reinstall Windows Home. The verified installer media and digital license remain available.

---

# PHASE 5 — optional temporary Windows before the second SSD

The default is to skip this phase. The external drive should remain an archive/backup, not a boot drive.

If Windows is urgently required, first identify the external device:

| External device | Decision |
|---|---|
| USB thumb drive | Do not use for portable Windows |
| Spinning USB hard disk | Do not use for portable Windows |
| External SATA SSD | Possible but second choice |
| External NVMe in USB 3.2 Gen 2/Thunderbolt enclosure | Only reasonable portable-Windows candidate |

Create a **fresh** portable Windows installation from an official Microsoft ISO using reputable tooling on another trusted PC. Do not convert or clone the old installation. Keep it separate from the backup drive. Treat this as an unsupported bridge: do not use it for BIOS/EC updates, live DJ performance, or the only copy of important data.

A Bluefin-hosted Windows virtual machine is acceptable for light Windows-only utilities, but it is not the recommended environment for Rekordbox hardware, low-latency audio, direct NVIDIA use, or firmware flashing.

---

# PHASE 6 — add the future internal Windows SSD

When the second NVMe arrives:

1. Back up Bluefin and shut down.
2. Install the new SSD. Record both drives' manufacturer, model, serial number, and capacity.
3. Temporarily remove/disable the Bluefin SSD so Windows Setup can touch only the new SSD.
4. Boot the official Microsoft USB in UEFI mode with Secure Boot enabled.
5. Clean-install **Windows 11 Home** onto the new SSD's unallocated space.
6. Update Windows, confirm automatic activation, install only exact Razer drivers/firmware when needed, and run `02-verify-clean-windows.ps1`.
7. Enable BitLocker and save the recovery key somewhere other than this laptop.
8. Reconnect/re-enable the Bluefin SSD, place Bluefin first in UEFI boot order, and use the firmware boot menu for Windows.

Do not create an internal shared partition initially. Let each OS own its SSD. Exchange files through an external encrypted SSD, NAS, or synchronized directory. If a shared NTFS volume is designed later, keep containers, Linux home data, databases, model caches, and the sole copy of any music library off it; disable Windows hibernation/Fast Startup before Linux writes to it:

```powershell
powercfg.exe /hibernate off
shutdown.exe /s /t 0
```

## Primary sources

- Bluefin installation, dedicated-drive, NVIDIA-laptop and Secure Boot guidance: <https://docs.projectbluefin.io/installation/>
- Bluefin current downloads: <https://docs.projectbluefin.io/downloads/>
- Bluefin LTS Secure Boot limitation: <https://docs.projectbluefin.io/lts/>
- Bluefin GDX purpose and ISO name: <https://docs.projectbluefin.io/gdx/>
- Bluefin local AI and GPU tooling: <https://docs.projectbluefin.io/ai/>
- Microsoft installation-media instructions: <https://support.microsoft.com/en-us/windows/deployment/install-upgrade/create-installation-media-for-windows>
- Microsoft clean-install instructions: <https://support.microsoft.com/en-us/windows/deployment/install-upgrade/reinstall-windows-with-the-installation-media>
- Microsoft activation and same-device reinstallation: <https://support.microsoft.com/en-us/windows/activation/activate-windows>
- Microsoft removed-features list (Windows To Go removed in version 2004): <https://learn.microsoft.com/en-us/windows/whats-new/removed-features>
- Razer RZ09-0421x support hub: <https://mysupport.razer.com/app/answers/detail/a_id/5900>
- Razer RZ09-0421x BIOS updater: <https://mysupport.razer.com/app/answers/detail/a_id/9729/~/razer-blade-15-%282022%29-bios-updater-%7C-rz09-0421x>
- Microsoft Windows Terminal setup: <https://learn.microsoft.com/windows/terminal/install>

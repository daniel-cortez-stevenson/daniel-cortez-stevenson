# Verify the clean Windows firmware-service installation.
# READ-ONLY: this script does not alter Windows, disks, firmware, TPM, or boot entries.

$ErrorActionPreference = 'Continue'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    throw 'Run this script from PowerShell as Administrator.'
}

$desktop = [Environment]::GetFolderPath('Desktop')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $desktop "razer-clean-windows-verification-$stamp.txt"

function Add-Section {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    Add-Content -LiteralPath $report -Encoding utf8 -Value "`r`n===== $Title ====="
    try {
        $text = (& $Command 2>&1 | Out-String -Width 260).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($text)) { $text = '(no output)' }
        Add-Content -LiteralPath $report -Encoding utf8 -Value $text
    }
    catch {
        Add-Content -LiteralPath $report -Encoding utf8 -Value ("ERROR: " + $_.Exception.Message)
    }
}

Set-Content -LiteralPath $report -Encoding utf8 -Value @(
    'Razer clean-Windows verification (READ-ONLY)'
    "Generated: $(Get-Date -Format o)"
    'Excluded: serial numbers, full product keys, disk unique IDs, device/tenant IDs.'
)

Add-Section 'COMPUTER, WINDOWS, AND ACTIVATION' {
    $computer = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $firmwareType = (Get-ComputerInfo -Property BiosFirmwareType).BiosFirmwareType
    $windowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $license = Get-CimInstance SoftwareLicensingProduct |
        Where-Object { $_.ApplicationID -eq $windowsAppId -and $_.PartialProductKey } |
        Select-Object -First 1
    [pscustomobject]@{
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        SystemSKU = $computer.SystemSKUNumber
        Windows = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        InstallDate = $os.InstallDate
        Activated = ([int]$license.LicenseStatus -eq 1)
        LicenseDescription = $license.Description
        FirmwareType = $firmwareType
    } | Format-List
}

Add-Section 'BIOS' {
    Get-CimInstance Win32_BIOS |
        Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate |
        Format-List
}

Add-Section 'SECURE BOOT' {
    try { [pscustomobject]@{ SecureBootEnabled = [bool](Confirm-SecureBootUEFI) } | Format-List }
    catch { [pscustomobject]@{ SecureBootEnabled = 'Unavailable'; Detail = $_.Exception.Message } | Format-List }
}

Add-Section 'TPM' {
    Get-Tpm |
        Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated,
            AutoProvisioning, LockedOut, ManufacturerIdTxt, ManufacturerVersion |
        Format-List
}

Add-Section 'FIRMWARE DEVICES' {
    Get-PnpDevice -Class Firmware |
        Select-Object Status, FriendlyName |
        Sort-Object FriendlyName |
        Format-Table -AutoSize
}

Add-Section 'DEVICES NOT REPORTING OK' {
    Get-PnpDevice |
        Where-Object Status -ne 'OK' |
        Select-Object Class, FriendlyName, Status |
        Sort-Object Class, FriendlyName |
        Format-Table -AutoSize
}

Add-Section 'DISKS AND PARTITIONS' {
    Get-Disk |
        Select-Object Number, FriendlyName, BusType, PartitionStyle,
            HealthStatus, OperationalStatus,
            @{Name='SizeGiB';Expression={[math]::Round($_.Size / 1GB, 2)}},
            IsBoot, IsSystem |
        Sort-Object Number |
        Format-Table -AutoSize
    Get-Partition |
        Select-Object DiskNumber, PartitionNumber, DriveLetter, Type,
            @{Name='SizeGiB';Expression={[math]::Round($_.Size / 1GB, 2)}} |
        Sort-Object DiskNumber, PartitionNumber |
        Format-Table -AutoSize
}

Add-Section 'BITLOCKER' {
    Get-BitLockerVolume |
        Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus,
            EncryptionMethod, EncryptionPercentage |
        Format-Table -AutoSize
}

Add-Section 'WINDOWS DEFENDER' {
    Get-MpComputerStatus |
        Select-Object AMServiceEnabled, AntivirusEnabled, AntispywareEnabled,
            BehaviorMonitorEnabled, IoavProtectionEnabled, RealTimeProtectionEnabled,
            AntivirusSignatureLastUpdated, AntivirusSignatureVersion |
        Format-List
}

Add-Section 'RECENT WINDOWS UPDATES' {
    Get-HotFix |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 20 HotFixID, Description, InstalledOn |
        Format-Table -AutoSize
}

Add-Section 'WINDOWS RECOVERY ENVIRONMENT' {
    & "$env:SystemRoot\System32\reagentc.exe" /info
}

Add-Section 'HIBERNATION AND AVAILABLE SLEEP STATES' {
    & "$env:SystemRoot\System32\powercfg.exe" /a
    $fastStartup = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue
    "FastStartupRegistryValue: $fastStartup"
}

Add-Section 'ORGANIZATION JOIN STATE (IDS OMITTED)' {
    $joinStatus = & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>&1
    $joinStatus |
        Select-String -Pattern '^\s*(AzureAdJoined|EnterpriseJoined|DomainJoined|WorkplaceJoined|DeviceAuthStatus)\s*:' |
        ForEach-Object { $_.Line.Trim() }
}

$hash = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
Write-Host 'Clean-Windows verification finished.' -ForegroundColor Green
Write-Host "Report: $report"
Write-Host "SHA256: $hash"
Write-Host 'Review the report before installing Bluefin or enabling BitLocker.' -ForegroundColor Yellow

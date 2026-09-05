# Razer Blade pre-wipe audit.
# READ-ONLY: this script does not alter disks, firmware, TPM, boot entries, or Windows.

# Windows 11 is 64-bit, but the legacy "Windows PowerShell (x86)" shortcut starts
# a 32-bit process and redirects System32 to SysWOW64. Relaunch this same script
# in native 64-bit Windows PowerShell so dsregcmd, powercfg, and reagentc resolve
# consistently. This does not elevate privileges or change system state.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Save this as a .ps1 file before running it from 32-bit PowerShell.'
    }

    $nativePowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $nativePowerShell)) {
        throw "Native 64-bit Windows PowerShell was not found at $nativePowerShell"
    }

    & $nativePowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Continue'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    throw 'Run this script from PowerShell as Administrator.'
}

$desktop = [Environment]::GetFolderPath('Desktop')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $desktop "razer-prewipe-report-$stamp.txt"

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
    'Razer secure-rebuild pre-wipe audit (READ-ONLY)'
    "Generated: $(Get-Date -Format o)"
    'Excluded: serial numbers, full product keys, disk unique IDs, device/tenant IDs.'
    "PowerShell process: $([IntPtr]::Size * 8)-bit"
)

Add-Section 'COMPUTER, SKU, CPU, AND MEMORY' {
    $computer = Get-CimInstance Win32_ComputerSystem
    $product = Get-CimInstance Win32_ComputerSystemProduct
    $cpu = Get-CimInstance Win32_Processor
    [pscustomobject]@{
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        SystemFamily = $computer.SystemFamily
        SystemSKU = $computer.SystemSKUNumber
        ProductName = $product.Name
        CPU = ($cpu.Name -join '; ')
        MemoryGiB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    } | Format-List
}

Add-Section 'WINDOWS AND BOOT MODE' {
    $os = Get-CimInstance Win32_OperatingSystem
    $firmwareType = (Get-ComputerInfo -Property BiosFirmwareType).BiosFirmwareType
    [pscustomobject]@{
        Windows = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        InstallDate = $os.InstallDate
        Architecture = $os.OSArchitecture
        FirmwareType = $firmwareType
    } | Format-List
}

Add-Section 'WINDOWS ACTIVATION (NO KEY DISCLOSED)' {
    $windowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $statusNames = @{
        0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'Initial grace'; 3 = 'Additional grace'
        4 = 'Non-genuine grace'; 5 = 'Notification'; 6 = 'Extended grace'
    }
    $license = Get-CimInstance SoftwareLicensingProduct |
        Where-Object { $_.ApplicationID -eq $windowsAppId -and $_.PartialProductKey } |
        Select-Object -First 1
    $firmwareKeyPresent = -not [string]::IsNullOrWhiteSpace(
        (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
    )
    [pscustomobject]@{
        Name = $license.Name
        Description = $license.Description
        LicenseStatus = $statusNames[[int]$license.LicenseStatus]
        FirmwareEmbeddedKeyPresent = $firmwareKeyPresent
    } | Format-List
}

Add-Section 'BIOS AND BASEBOARD' {
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    [pscustomobject]@{
        BIOSManufacturer = $bios.Manufacturer
        BIOSVersion = $bios.SMBIOSBIOSVersion
        BIOSReleaseDate = $bios.ReleaseDate
        SMBIOSVersion = $bios.SMBIOSMajorVersion.ToString() + '.' + $bios.SMBIOSMinorVersion
        BoardManufacturer = $board.Manufacturer
        BoardProduct = $board.Product
    } | Format-List
}

Add-Section 'SECURE BOOT' {
    try {
        [pscustomobject]@{ SecureBootEnabled = [bool](Confirm-SecureBootUEFI) } | Format-List
    }
    catch {
        [pscustomobject]@{ SecureBootEnabled = 'Unavailable'; Detail = $_.Exception.Message } | Format-List
    }
}

Add-Section 'TPM' {
    Get-Tpm |
        Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated,
            AutoProvisioning, LockedOut, ManufacturerIdTxt, ManufacturerVersion |
        Format-List
}

Add-Section 'BATTERY HEALTH (NO SERIAL)' {
    $static = Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop |
        Select-Object -First 1
    $full = Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop |
        Select-Object -First 1
    $cycles = Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryCycleCount -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $designMWh = [double]$static.DesignedCapacity
    $fullMWh = [double]$full.FullChargedCapacity
    $health = if ($designMWh -gt 0) { [math]::Round(($fullMWh / $designMWh) * 100, 1) } else { $null }

    [pscustomobject]@{
        DesignCapacityMWh = $designMWh
        FullChargeCapacityMWh = $fullMWh
        EstimatedHealthPercent = $health
        CycleCount = $cycles.CycleCount
    } | Format-List
}

Add-Section 'CPU VIRTUALIZATION' {
    Get-CimInstance Win32_Processor |
        Select-Object Name, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions |
        Format-List
}

Add-Section 'GRAPHICS' {
    Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, VideoProcessor,
            @{Name='AdapterRAMGiB';Expression={ if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 2) } }} |
        Format-Table -AutoSize
}

Add-Section 'PHYSICAL STORAGE (NO SERIALS OR UNIQUE IDS)' {
    Get-PhysicalDisk |
        Select-Object FriendlyName, MediaType, BusType, FirmwareVersion,
            HealthStatus, OperationalStatus,
            @{Name='SizeGiB';Expression={[math]::Round($_.Size / 1GB, 2)}} |
        Sort-Object FriendlyName |
        Format-Table -AutoSize
}

Add-Section 'WINDOWS DISK NUMBERS' {
    Get-Disk |
        Select-Object Number, FriendlyName, BusType, PartitionStyle,
            OperationalStatus, HealthStatus,
            @{Name='SizeGiB';Expression={[math]::Round($_.Size / 1GB, 2)}},
            IsBoot, IsSystem |
        Sort-Object Number |
        Format-Table -AutoSize
}

Add-Section 'PARTITIONS' {
    Get-Partition |
        Select-Object DiskNumber, PartitionNumber, DriveLetter, Type,
            @{Name='SizeGiB';Expression={[math]::Round($_.Size / 1GB, 2)}} |
        Sort-Object DiskNumber, PartitionNumber |
        Format-Table -AutoSize
}

Add-Section 'STORAGE RELIABILITY COUNTERS' {
    foreach ($disk in Get-PhysicalDisk) {
        "Disk: $($disk.FriendlyName)"
        try {
            Get-StorageReliabilityCounter -PhysicalDisk $disk |
                Select-Object Temperature, TemperatureMax, Wear, PowerOnHours,
                    ReadErrorsTotal, WriteErrorsTotal, ReadErrorsUncorrected,
                    WriteErrorsUncorrected |
                Format-List
        }
        catch {
            "Counters unavailable: $($_.Exception.Message)"
        }
    }
}

Add-Section 'BITLOCKER OR DEVICE ENCRYPTION' {
    Get-BitLockerVolume |
        Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus,
            EncryptionMethod, EncryptionPercentage |
        Format-Table -AutoSize
}

Add-Section 'WINDOWS RECOVERY ENVIRONMENT' {
    & "$env:SystemRoot\System32\reagentc.exe" /info
}

Add-Section 'FIRMWARE DEVICES' {
    Get-PnpDevice -Class Firmware |
        Select-Object Status, FriendlyName, InstanceId |
        ForEach-Object {
            # Instance IDs can contain machine-specific identifiers; omit them from the report.
            [pscustomobject]@{ Status = $_.Status; FriendlyName = $_.FriendlyName }
        } |
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

Add-Section 'ORGANIZATION JOIN STATE (IDS OMITTED)' {
    $joinStatus = & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>&1
    $joinStatus |
        Select-String -Pattern '^\s*(AzureAdJoined|EnterpriseJoined|DomainJoined|WorkplaceJoined|DeviceAuthStatus)\s*:' |
        ForEach-Object { $_.Line.Trim() }
}

Add-Section 'LOCAL AUTOPILOT INDICATORS (NO IDS)' {
    $autopilotPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
    $autopilot = Get-ItemProperty -LiteralPath $autopilotPath -ErrorAction SilentlyContinue
    $computer = Get-CimInstance Win32_ComputerSystem

    [pscustomobject]@{
        PartOfDomain = [bool]$computer.PartOfDomain
        LocalAutopilotDataPresent = Test-Path -LiteralPath $autopilotPath
        TenantAssignmentPresent = [bool]$autopilot.CloudAssignedTenantId
        MdmAssignmentPresent = [bool]$autopilot.CloudAssignedMdmId
    } | Format-List
}

Add-Section 'WINDOWS INSIDER CONFIGURATION' {
    $key = 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability'
    if (Test-Path $key) {
        Get-ItemProperty $key |
            Select-Object BranchName, ContentType, Ring, IsBuildFlightingEnabled |
            Format-List
    }
    else {
        'No Windows Insider applicability key found.'
    }
}

Add-Section 'LANGUAGE AND KEYBOARD' {
    'System locale:'
    Get-WinSystemLocale | Format-List
    'Current user language list:'
    Get-WinUserLanguageList |
        Select-Object LanguageTag, EnglishName, LocalizedName, InputMethodTips |
        Format-List
    'Default input override:'
    $override = Get-WinDefaultInputMethodOverride
    if ($null -eq $override) { '(none)' } else { $override | Format-List }
}

Add-Section 'RAZER/OEM STARTUP REFERENCES' {
    $startup = Get-CimInstance Win32_StartupCommand |
        Where-Object { $_.Command -match 'rzoobe|Recovery\\OEM|Razer' } |
        Select-Object Name, Command, Location
    $tasks = Get-ScheduledTask |
        Where-Object { ($_.Actions | Out-String) -match 'rzoobe|Recovery\\OEM|Razer' } |
        Select-Object TaskPath, TaskName, State,
            @{Name='Action';Expression={$_.Actions | Out-String}}
    @($startup) + @($tasks) | Format-List
}

$hash = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
Write-Host 'Read-only audit finished.' -ForegroundColor Green
Write-Host "Report: $report"
Write-Host "SHA256: $hash"
Write-Host 'STOP: send the report before wiping, sanitizing, resizing, or flashing.' -ForegroundColor Yellow

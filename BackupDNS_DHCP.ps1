<#
.SYNOPSIS
    This PowerShell script by Dario Barbarino automates the backup and maintenance of DNS and DHCP server data on a Windows server. 

.DESCRIPTION
    The script sets up unique directories for each backup session, based on the current date and time. 
    It automatically deletes any backups older than six months, aiding in storage management. 
    The script subsequently creates backups for the DHCP database and DNS zones on the server.
    It also generates log files for each backup operation, recording the success or failure status.

    This tool is invaluable for system administrators, as it helps facilitate regular server configuration backups, 
    ensuring quick recovery in case of data loss or server failure.

.AUTHOR
    Dario Barbarino
#>

 #Requires -RunAsAdministrator, execute it directly from the Domain Controller

# Set backup directory paths
$backupRoot = "C:\BackupDNS_DHCP"
$dhcpBackupFolder = (Get-Date).ToString('dd.MM.yyyy_HHmm')
$dhcpBackupPath = Join-Path -Path $backupRoot -ChildPath "DHCP_$dhcpBackupFolder"
$dnsBackupFolder = (Get-Date).ToString('dd.MM.yyyy_HHmm')
$dnsBackupPath = Join-Path -Path $backupRoot -ChildPath "DNS_$dnsBackupFolder"
$olderThanMonths = 6
$olderThanDate = (Get-Date).AddMonths(-$olderThanMonths)

# Check if backup root exists, if not, create it
if (!(Test-Path -Path $backupRoot)) {
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
}

# Remove backups older than 6 months and log the deletion
$oldDhcpBackups = Get-ChildItem -Path $backupRoot -Filter "DHCP_*" -Directory | Where-Object { $_.CreationTime -lt $olderThanDate }
$oldDnsBackups = Get-ChildItem -Path $backupRoot -Filter "DNS_*" -Directory | Where-Object { $_.CreationTime -lt $olderThanDate }
$deletedBackups = $false

foreach ($backup in $oldDhcpBackups + $oldDnsBackups) {
    Remove-Item -Recurse -Force $backup.FullName
    $deletedBackups = $true
}

# Check if DHCP backup folder exists, if not, create it
if (!(Test-Path -Path $dhcpBackupPath)) {
    New-Item -ItemType Directory -Path $dhcpBackupPath | Out-Null
}

# Check if DNS backup folder exists, if not, create it
if (!(Test-Path -Path $dnsBackupPath)) {
    New-Item -ItemType Directory -Path $dnsBackupPath | Out-Null
}

# Export DHCP database
$dhcpLogFile = "$dhcpBackupPath\DHCP_BackupLog.txt"
try {
    Export-DhcpServer -ComputerName localhost -Leases -File "$dhcpBackupPath\dhcp_backup.xml" -Force -Verbose
    $dhcpLogMessage = (Get-Date).ToString() + " - DHCP backup completed successfully."
    Write-Host $dhcpLogMessage -ForegroundColor Green
} catch {
    $dhcpLogMessage = (Get-Date).ToString() + " - Failed to backup DHCP database. Error: $_"
    Write-Host $dhcpLogMessage -ForegroundColor Red
}
Add-Content -Path $dhcpLogFile -Value $dhcpLogMessage

# Export DNS zones
$dnsLogFile = "$dnsBackupPath\DNS_BackupLog.txt"
try {
    $dnsZones = Get-DnsServerZone -ComputerName localhost

    foreach ($zone in $dnsZones) {
        $sanitizedZoneName = $zone.ZoneName.TrimEnd('.')
        $zoneFile = "$dnsBackupPath\${sanitizedZoneName}.csv"
        $zoneRecords = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName localhost
        $zoneRecords | Export-Csv -Path $zoneFile -NoTypeInformation
    }
    $dnsLogMessage = (Get-Date).ToString() + " - DNS zones backup completed successfully."
    Write-Host $dnsLogMessage -ForegroundColor Green
} catch {
    $dnsLogMessage = (Get-Date).ToString() + " - Failed to backup DNS zones. Error: $_"
    Write-Host $dnsLogMessage -ForegroundColor Red
}
Add-Content -Path $dnsLogFile -Value $dnsLogMessage


# Log the deletion of old backups if any were deleted
if ($deletedBackups) {
$oldBackupsLogMessage = (Get-Date).ToString() + " - Removed backups older than $olderThanMonths months."
Write-Host $oldBackupsLogMessage -ForegroundColor Cyan
Add-Content -Path $dhcpLogFile -Value $oldBackupsLogMessage
Add-Content -Path $dnsLogFile -Value $oldBackupsLogMessage
}

<#
.SYNOPSIS
This script identifies inactive computers in the given Active Directory organizational units (OUs), 
moves them to a separate OU for disabled computers, and then disables them. It also handles any exceptions 
defined for computers that should not be moved or disabled.

.DESCRIPTION
The script performs several key tasks:

1. Identifies inactive computers in the specified OUs that have been inactive for a certain number of days. 
   Inactivity is determined by the "LastLogonTimeStamp" attribute of each computer object in AD.

2. Once these inactive computers are identified, they are moved to a specific OU for disabled computers 
   and then disabled. If there are exceptions defined for certain computers (e.g., "FC0000"), 
   these will be skipped in this process.

3. The script then checks the disabled computers OU to ensure all computers are actually disabled. 
   If there are any enabled computers in this OU, they are disabled.

4. Finally, the script checks the disabled computers OU for any computers that have been disabled for a 
   certain number of days (90) and removes them.
   
   .AUTHOR
Created by Dario Barbarino


#>

# Import the Active Directory module
Import-Module ActiveDirectory

function Get-ScriptPath {
    return $PSScriptRoot
}


function Initialize-LogFile {
    param(
        [string]$LogFilePath
    )

    if (-not (Test-Path $LogFilePath)) {
        New-Item -ItemType File -Path $LogFilePath | Out-Null
    } else {
        if ((Get-Item $LogFilePath).LastWriteTime -lt (Get-Date).AddMonths(-12)) {
            Clear-Content $LogFilePath
        }
    }
}

function Write-Log {
    param(
        [string]$LogFilePath,
        [string]$Message
    )

    $CurrentDateTime = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
    $FormattedMessage = "$CurrentDateTime - $Message"
    
    # Add new logs to the top of the log file
    $content = Get-Content $LogFilePath
    Set-Content -Path $LogFilePath -Value $FormattedMessage
    Add-Content -Path $LogFilePath -Value $content
}

function Get-InactiveComputers {
    param(
        [string[]]$SearchOUs,
        [string]$SearchScope,
        [int]$InactivityDays,
        [string[]]$ExceptionComputers = @() # A list of computers to be ignored, for example [string[]]$ExceptionComputers = @("FC0000", "FC0001", "FC0002")

    )

    $Filter = "(LastLogonTimeStamp -lt $((Get-Date).AddDays(-$InactivityDays).ToFileTime())) -and (Enabled -eq 'true')"

    $Computers = foreach ($OU in $SearchOUs) {
        Get-ADComputer -SearchBase $OU -SearchScope $SearchScope -Filter $Filter -Properties LastLogonTimeStamp,Enabled,DistinguishedName | Where-Object { $ExceptionComputers -notcontains $_.Name }
    }

    return $Computers
}

function Move-Disable-Computers {
    param(
        [object[]]$Computers,
        [string]$DisabledOU,
        [string]$LogFilePath,
        [string[]]$ExceptionComputers = @() # A list of computers to be ignored
    )

    foreach ($Computer in $Computers) {
        $ComputerName = $Computer.Name

        if ($ExceptionComputers -contains $ComputerName) {
            Write-Log -LogFilePath $LogFilePath -Message "User $($env:USERNAME) executed the script. Ignored computer '$ComputerName' due to exception list."
            continue
        }

        $OriginalOU = ($Computer.DistinguishedName -split '(?<=,)',2)[1]
        $LastLogonTimeStamp = [DateTime]::FromFileTime($Computer.LastLogonTimeStamp).ToString('dd.MM.yyyy')

        try {
            Move-ADObject -Identity $Computer -TargetPath $DisabledOU -Confirm:$false
            $NewComputerDN = "CN=$ComputerName,$DisabledOU"
            Disable-ADAccount -Identity $NewComputerDN -Confirm:$false

            $DisabledDate = (Get-Date).ToString('dd.MM.yyyy')
            $DeletionDate = (Get-Date).AddDays(90).ToString('dd.MM.yyyy')
            Set-ADComputer -Identity $NewComputerDN -Description "Object was moved and disabled on: $DisabledDate. It will be definitely deleted on: $DeletionDate"

            $LogMessage = "User $($env:USERNAME) executed the script. Moved computer '$ComputerName' from '$OriginalOU' to '$DisabledOU' and disabled the computer account. Last logon timestamp: $LastLogonTimeStamp."
            Write-Log -LogFilePath $LogFilePath -Message $LogMessage
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $LogMessage = "User $($env:USERNAME) encountered an error while moving computer '$ComputerName' from '$OriginalOU' to '$DisabledOU' and disabling the computer account: $ErrorMessage"
            Write-Log -LogFilePath $LogFilePath -Message $LogMessage
        }
    }
}

function Disable-EnabledComputersInOU {
    param(
        [string]$OU,
        [string]$LogFilePath
    )

    $EnabledComputers = Get-ADComputer -SearchBase $OU -Filter "Enabled -eq 'True'" -Properties Enabled
    $DisabledComputersList = @()

    if ($EnabledComputers) {
        foreach ($EnabledComputer in $EnabledComputers) {
            try {
                Disable-ADAccount -Identity $EnabledComputer -Confirm:$false
                $DisabledComputersList += $EnabledComputer.Name
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                $LogMessage = "User $($env:USERNAME) encountered an error while disabling enabled computer '$($EnabledComputer.Name)' found in the Disabled_Computers OU: $ErrorMessage"
                Write-Log -LogFilePath $LogFilePath -Message $LogMessage
            }
        }

        if ($DisabledComputersList) {
            $DisabledComputersString = ($DisabledComputersList -join ', ')
            $LogMessage = "User $($env:USERNAME) executed the script. Disabling enabled computers found in the Disabled_Computers OU: $DisabledComputersString."
            Write-Log -LogFilePath $LogFilePath -Message $LogMessage
        }
    } else {
        $LogMessage = "User $($env:USERNAME) executed the script. No enabled computers found in the Disabled_Computers OU."
        Write-Log -LogFilePath $LogFilePath -Message $LogMessage
    }
}

function Remove-OldDisabledComputers {
    param(
        [string]$OU,
        [int]$Days,
        [string]$LogFilePath
    )

    $OldDisabledComputers = Get-ADComputer -SearchBase $OU -Filter * -Properties whenChanged, Enabled | Where-Object {$_.Enabled -eq $false}

    if ($OldDisabledComputers) {
        $RemovedComputersList = @()

        foreach ($Computer in $OldDisabledComputers) {
            $whenChanged = $Computer.whenChanged
            $daysDisabled = ((Get-Date) - $whenChanged).Days
            
            if ($daysDisabled -ge $Days) {
                try {
                    # Check for child objects and remove them
                    $ChildObjects = Get-ADObject -Filter * -SearchBase $Computer.DistinguishedName -SearchScope OneLevel
                    if ($ChildObjects) {
                        foreach ($ChildObject in $ChildObjects) {
                            Remove-ADObject -Identity $ChildObject -Recursive -Confirm:$false 
                        }
                    }

                    # Remove the computer object
                    Remove-ADComputer -Identity $Computer -Confirm:$false 
                    $RemovedComputersList += $Computer.Name
                }
                catch {
                    $ErrorMessage = $_.Exception.Message
                    $LogMessage = "User $($env:USERNAME) encountered an error while removing computer '$($Computer.Name)' from the Disabled_Computers OU: $ErrorMessage"
                    Write-Log -LogFilePath $LogFilePath -Message $LogMessage
                }
            }
        }

        if ($RemovedComputersList) {
            $RemovedComputers = $RemovedComputersList -join ", "
            $LogMessage = "User $($env:USERNAME) executed the script. Removed computers '$RemovedComputers' from the Disabled_Computers OU because they were disabled for more than $Days days. The computers were definitely deleted."
            Write-Log -LogFilePath $LogFilePath -Message $LogMessage
        }
    }
}

# Main script
$ScriptPath = Get-ScriptPath
$LogFilePath = Join-Path -Path $ScriptPath -ChildPath "DisabledComputersReport.log"
Initialize-LogFile -LogFilePath $LogFilePath

Write-Log -LogFilePath $LogFilePath -Message "##################################################"
Write-Log -LogFilePath $LogFilePath -Message "Script executed"

$SearchOUs = "ComputersOU01,DC=yourdomain,DC=domain", "ComputersOU02,DC=yourdomain,DC=domain", "ServersOU,DC=yourdomain,DC=domain"
$SearchScope = "Subtree"
$InactivityDays = 90

$Computers = Get-InactiveComputers -SearchOUs $SearchOUs -SearchScope $SearchScope -InactivityDays $InactivityDays
$DisabledOU = "OU=Disabled_ComputersOU,DC=yourdomain,DC=domain"

if ($Computers) {
    Move-Disable-Computers -Computers $Computers -DisabledOU $DisabledOU -LogFilePath $LogFilePath
} else {
    $LogMessage = "User $($env:USERNAME) executed the script. No enabled computers in the specified OUs and their sub-containers have been inactive for at least 90 days. No computers were moved or disabled."
    Write-Log -LogFilePath $LogFilePath -Message $LogMessage
}

Disable-EnabledComputersInOU -OU $DisabledOU -LogFilePath $LogFilePath
Remove-OldDisabledComputers -OU $DisabledOU -Days 90 -LogFilePath $LogFilePath
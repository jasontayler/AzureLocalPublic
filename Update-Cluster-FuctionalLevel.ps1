#Requires -Modules FailoverClusters

<#
.SYNOPSIS
    Validates and updates cluster functional level if required.

.DESCRIPTION
    This script connects to a remote server, checks the cluster functional level,
    and updates it if it doesn't meet the required standards.

.PARAMETER ServerName
    The target server name to connect to. Default: "AZL-NUC-H01.jase.org"

.PARAMETER RequiredFunctionalLevel
    The required functional level for the cluster. Default: 12

.PARAMETER RequiredUpdateVersion
    The required update version. Default: 32774

.EXAMPLE
    .\Update-ClusterFunctionalLevel.ps1 -ServerName "MyServer.domain.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName = "myserver.domain.com",
    
    [Parameter(Mandatory = $false)]
    [int]$RequiredFunctionalLevel = 12,
    
    [Parameter(Mandatory = $false)]
    [int]$RequiredUpdateVersion = 32774
)

function Update-ClusterLevel {
    [CmdletBinding()]
    param(
        [string]$ServerName,
        [int]$RequiredFunctionalLevel,
        [int]$RequiredUpdateVersion
    )
    
    try {
        # Get credentials securely
        Write-Host "Please provide credentials for server: $ServerName" -ForegroundColor Yellow
        $credential = Get-Credential -Message "Enter credentials for $ServerName"
        
        if (-not $credential) {
            throw "No credentials provided. Exiting."
        }
        
        # Establish remote session
        Write-Host "Establishing remote session to $ServerName..." -ForegroundColor Green
        $session = New-PSSession -ComputerName $ServerName -Credential $credential -Authentication CredSSP -ErrorAction Stop
        
        # Execute cluster validation and update in remote session
        $result = Invoke-Command -Session $session -ScriptBlock {
            param($RequiredLevel, $RequiredVersion)
            
            try {
                # Import required module
                Import-Module FailoverClusters -ErrorAction Stop
                
                # Get cluster information
                $cluster = Get-Cluster -ErrorAction Stop
                $clusterName = $cluster.Name
                $currentFunctionalLevel = $cluster.ClusterFunctionalLevel
                $currentUpgradeVersion = $cluster.ClusterUpgradeVersion
                
                # Create result object
                $clusterInfo = [PSCustomObject]@{
                    ClusterName = $clusterName
                    CurrentFunctionalLevel = $currentFunctionalLevel
                    RequiredFunctionalLevel = $RequiredLevel
                    CurrentUpgradeVersion = $currentUpgradeVersion
                    RequiredUpgradeVersion = $RequiredVersion
                    UpdateRequired = $false
                    UpdateAttempted = $false
                    UpdateSuccessful = $false
                    ErrorMessage = $null
                }
                
                # Check if update is required
                if ($currentFunctionalLevel -ne $RequiredLevel -or $currentUpgradeVersion -ne $RequiredVersion) {
                    $clusterInfo.UpdateRequired = $true
                    
                    Write-Output "Cluster '$clusterName' functional level: $currentFunctionalLevel (Required: $RequiredLevel)"
                    Write-Output "Cluster '$clusterName' upgrade version: $currentUpgradeVersion (Required: $RequiredVersion)"
                    Write-Output "Update is required. Attempting to update cluster functional level..."
                    
                    try {
                        Update-ClusterFunctionalLevel -Cluster $clusterName -Force -ErrorAction Stop
                        $clusterInfo.UpdateAttempted = $true
                        $clusterInfo.UpdateSuccessful = $true
                        Write-Output "Cluster functional level updated successfully."
                    }
                    catch {
                        $clusterInfo.UpdateAttempted = $true
                        $clusterInfo.UpdateSuccessful = $false
                        $clusterInfo.ErrorMessage = $_.Exception.Message
                        Write-Error "Failed to update cluster functional level: $($_.Exception.Message)"
                    }
                }
                else {
                    Write-Output "Cluster '$clusterName' functional level and upgrade version are already at required levels."
                    Write-Output "No update required."
                }
                
                return $clusterInfo
            }
            catch {
                throw "Error accessing cluster: $($_.Exception.Message)"
            }
        } -ArgumentList $RequiredFunctionalLevel, $RequiredUpdateVersion
        
        # Display results
        Write-Host "`n=== Cluster Update Results ===" -ForegroundColor Cyan
        Write-Host "Cluster Name: $($result.ClusterName)" -ForegroundColor White
        Write-Host "Current Functional Level: $($result.CurrentFunctionalLevel)" -ForegroundColor White
        Write-Host "Required Functional Level: $($result.RequiredFunctionalLevel)" -ForegroundColor White
        Write-Host "Current Upgrade Version: $($result.CurrentUpgradeVersion)" -ForegroundColor White
        Write-Host "Required Upgrade Version: $($result.RequiredUpgradeVersion)" -ForegroundColor White
        
        if ($result.UpdateRequired) {
            if ($result.UpdateSuccessful) {
                Write-Host "Update Status: SUCCESS" -ForegroundColor Green
            }
            else {
                Write-Host "Update Status: FAILED" -ForegroundColor Red
                if ($result.ErrorMessage) {
                    Write-Host "Error: $($result.ErrorMessage)" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "Update Status: NOT REQUIRED" -ForegroundColor Green
        }
        
        return $result
    }
    catch {
        Write-Error "Script execution failed: $($_.Exception.Message)"
        return $null
    }
    finally {
        # Clean up session
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            Write-Host "Remote session closed." -ForegroundColor Gray
        }
    }
}

# Execute the main function
$result = Update-ClusterLevel -ServerName $ServerName -RequiredFunctionalLevel $RequiredFunctionalLevel -RequiredUpdateVersion $RequiredUpdateVersion

# Exit with appropriate code
if ($result -and (-not $result.UpdateRequired -or $result.UpdateSuccessful)) {
    exit 0
}
else {
    exit 1
}


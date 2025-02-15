# Define mandatory parameters
param (
    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,

    [Parameter(Mandatory=$true)]
    [int]$Days,

    [Parameter(Mandatory=$true)]
    [string]$GroupId,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Disable", "Report")]
    [string]$Mode
)

$SecuredPasswordPassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecuredPasswordPassword

Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome

$FilterDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$allDevices = @()
$nextLink = "https://graph.microsoft.com/beta/devicemanagement/manageddevices?`$filter=lastSyncDateTime lt $FilterDate and operatingSystem eq 'Windows'&`$ConsistencyLevel=eventual"

while (![string]::IsNullOrEmpty($nextLink)) { 
    $response = Invoke-MgGraphRequest -Method GET -Uri "$nextLink"
    $allDevices += $response.value  
    $nextLink = $response.'@odata.nextLink'
    Write-Host "Fetching next page: $nextLink"
}

if ($Mode -eq "report") {
    Write-Warning "Report Mode: Found $($allDevices.Count) stale devices."
    
    # Select specific properties for reporting
    $report = $allDevices | Select-Object id, deviceName, userPrincipalName, lastsyncdatetime
    
    # Output the report
    return $report
}

if ($Mode -eq "disable") {
    Write-Warning "Found $($allDevices.Count) stale devices."
    $count = $alldevices.count
    # Display report before proceeding with disabling
    $report = $allDevices | Select-Object id, deviceName, userPrincipalName, lastsyncdatetime
    $report | ForEach-Object { Write-Host "$($_.id) - $($_.deviceName) - $($_.userPrincipalName) - $($_.lastsyncdatetime)" }
    $host.UI.RawUI.ForegroundColor = "Yellow"

    $confirmation = Read-Host "Do you want to disable these $count devices (yes/no)"
    $host.UI.RawUI.ForegroundColor = "White"
    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled."
        exit
    }

    foreach ($device in $allDevices) {
        $azureaddeviceid = $device.azureADDeviceId
        if (-not $azureaddeviceid) { continue }

        $urientra = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$azureaddeviceid'"
        $request = Invoke-MgGraphRequest -Method GET -Uri $urientra
        $entraobjectid = $request.value.id
        
        if ($entraobjectid) {
            Write-Host "Processing device: $entraobjectid"
            
            $urigroup = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/`$ref"
            $body = @{"@odata.id"="https://graph.microsoft.com/v1.0/directoryObjects/$entraobjectid"}
            Invoke-MgGraphRequest -Method POST -Uri $urigroup -Body $body
            
            $uridisable = "https://graph.microsoft.com/beta/devices/$entraobjectid"
            $bodydisable = @{"accountEnabled"=$false}
            Invoke-MgGraphRequest -Method PATCH -Uri $uridisable -Body $bodydisable
        }
    }
    Write-Host "Disable Mode: Processed $($allDevices.Count) stale devices."
}

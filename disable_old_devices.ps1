# Use an Azure Vault for storing your client secret for a secured usage and avoid plain text secret
$global:tenant = "xxxx-xxxx-xxx-xxxx"
$global:clientId = "xxxx-xxxx-xxx-xxxx"
$global:clientSecret = "xxxx-xxxx-xxx-xxxx"
$SecuredPasswordPassword = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $SecuredPasswordPassword

Connect-MgGraph -TenantId $tenant -ClientSecretCredential $ClientSecretCredential


###################################################################################################################
$filterDate = (Get-Date).AddDays(-180).ToString("yyyy-MM-ddTHH:mm:ssZ")
###################################################################################################################


## create array that will contains managed devices filtered
$allDevices = @()

# create the api uri with the filter, consitancy is needed to handle dates
$nextlink = "https://graph.microsoft.com/beta/devicemanagement/manageddevices?`$filter=lastSyncDateTime lt $filterdate and operatingSystem eq 'Windows'&`$ConsistencyLevel=eventual"

while (![string]::IsNullOrEmpty($nextLink)) { 
    $response = Invoke-MgGraphRequest -Method GET -Uri "$nextLink"
    $allDevices += $response.value  # Add this page's devices
    $nextLink = $response.'@odata.nextLink' # Get the next page's URL
    Write-Host $nextLink
}

# Group ID where you want to put your device
$groupid = "9b7bd32f-7b3c-4ff6-b30d-63e6857fd432"

foreach ($device in $alldevices) {
    # Get Entra Object ID
    $azureaddeviceid=$device.azureADDeviceId
    $urientra = "https://graph.microsoft.com/beta/devices?`$filter=deviceid eq '$azureaddeviceid'"
    $request = Invoke-MgGraphRequest -method GET -uri $urientra
    $entraobjectid = $request.value.id
    # Add the device into the group
    $urigroup="https://graph.microsoft.com/v1.0/groups/$groupid/members/`$ref"
    $body = @{
        "@odata.id"="https://graph.microsoft.com/v1.0/directoryObjects/{$entraobjectid}"
      }
    Invoke-MgGraphRequest -method POST -uri $urigroup -Body $body
    # Disable the device
    $uridisable="https://graph.microsoft.com/beta/devices/$entraobjectid"
    $bodydisable = @{"accountEnabled"="false"}
    Invoke-MgGraphRequest -method POST -uri $uridisable -Body $bodydisable
}

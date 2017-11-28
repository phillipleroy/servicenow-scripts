Param([string]$collection, [string]$device)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_collection) {
  $collection = $env:SNC_collection
  $device     = $env:SNC_device
}

SNCLog-ParameterInfo @("Running AddToDeviceCollection", $collection, $device)

function Add-ToDeviceCollection() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $collection = $args[0]; 
   $device     = $args[1];

   $id = (Get-CMDevice -Name $device).ResourceID
   Add-CMDeviceCollectionDirectMembershipRule -CollectionName $collection -ResourceId $id
}

$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Add-ToDeviceCollection}' -ArgumentList $collection, $device"
    Invoke-Command -Session $session -ScriptBlock ${function:Add-ToDeviceCollection} -ArgumentList $collection, $device
} finally {
    Remove-PSSession -session $session
}
Param([string]$collection, [string]$device)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_collection) {
  $collection = $env:SNC_collection
  $device     = $env:SNC_device
}

SNCLog-ParameterInfo @("Running RemoveFromDeviceCollection", $collection, $device)

function Remove-FromDeviceCollection() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $collection = $args[0];
   $device     = $args[1];

   $id = (Get-CMDevice -Name $device).ResourceID
   Remove-CMDeviceCollectionDirectMembershipRule -CollectionName $collection -ResourceId $id -force
}


$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Remove-FromDeviceCollection}' -ArgumentList $collection, $device"
    Invoke-Command -Session $session -ScriptBlock ${function:Remove-FromDeviceCollection} -ArgumentList $collection, $device
} finally {
    Remove-PSSession -session $session
}
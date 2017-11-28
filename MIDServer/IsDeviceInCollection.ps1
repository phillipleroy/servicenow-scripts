Param([string]$collection, [string]$device)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_collection) {
  $collection = $env:SNC_collection
  $device        = $env:SNC_device
}

SNCLog-ParameterInfo @("Running IsDeviceInCollection", $collection, $device)

function TestDeviceInCollection() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $collectionName = $args[0]; 
   $deviceName        = $args[1];

   $collection = Get-CMDeviceCollection -Name $collectionName;
   If( $collection -eq $null  -or  $collection.CollectionType -ne 2) {   #device collection type is 2
      return $false;
   }
   If($collection.MemberCount -lt 1) {   #don't have any member in the collection
      return $false;
   }
   
   $deviceId = (Get-CMDevice -Name $deviceName).ResourceID;
   If($deviceId -eq $null ) {   
      return $false;
   }

   $devices = Get-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName;
   ForEach($device in $devices) {
       if ($deviceId -eq $device.ResourceID) {
          return $true;
        }
   }
   
   return $false;
}

$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:TestDeviceInCollection}' -ArgumentList $collection, $device"
    Invoke-Command -Session $session -ScriptBlock ${function:TestDeviceInCollection} -ArgumentList $collection, $device
} finally {
    Remove-PSSession -session $session
}
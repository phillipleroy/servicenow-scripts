Param([string]$parameters)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_parameters) {
  $parameters  = $env:SNC_parameters
}

SNCLog-ParameterInfo @("Running GetDeviceCollections", $parameters)

function Get-DeviceCollections() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $resultArray = @()

   $searchFilter =  "Name,CollectionID,CollectionType,LocalMemberCount,MemberCount"
   $searchFilterArray  = $searchFilter -split ","   

   Get-CMDeviceCollection | Select $searchFilterArray | ForEach-Object {
      $collectionInfo = @{}
      $collection = $_
      $collection | Get-Member -MemberType Properties | ForEach-Object {
         $key = $_.name
         $collectionInfo.Add($key, $collection.$key)
      }

      $resultArray += $collectionInfo
   }

   ConvertTo-Json $resultArray
}


$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Get-DeviceCollections}'"
    Invoke-Command -Session $session -ScriptBlock ${function:Get-DeviceCollections}
} finally {
    Remove-PSSession -session $session
}
Param([string]$parameters)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_SCCMServer) {
  $parameters  = $env:SNC_parameters
};

SNCLog-ParameterInfo @("Running GetApplications", $parameters)

function Get-Applications() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $resultArray = @()

   $searchFilter =  "CI_ID,CI_UniqueID,LocalizedDisplayName,Manufacturer,SoftwareVersion,IsDeployable,IsDeployed,NumberOfUsersWithApp,NumberOfDevicesWithApp"
   $searchFilterArray  = $searchFilter -split ","   
   
   Get-CMApplication | Select $searchFilterArray | ForEach-Object {
       $appInfo = @{}
       $app = $_
       $app | Get-Member -MemberType Properties | ForEach-Object {
          $key = $_.name
          $appInfo.Add($key, $app.$key)
      }

      $resultArray += $appInfo
   }

   ConvertTo-Json $resultArray
}


$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Get-Applications}'"
    Invoke-Command -Session $session -ScriptBlock ${function:Get-Applications}
} finally {
    Remove-PSSession -session $session
}
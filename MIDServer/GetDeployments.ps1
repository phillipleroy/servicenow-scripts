Param([string]$parameters)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_parameters) {
  $parameters  = $env:SNC_parameters
}

SNCLog-ParameterInfo @("Running GetDeployments", $parameters)

function Get-Deployments() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $resultArray = @()
   $searchFilter =  "DeploymentID,CI_ID,SoftwareName,CollectionID,CollectionName,DesiredConfigType,DeploymentIntent,NumberSuccess,NumberErrors"
   $searchFilterArray  = $searchFilter -split ","   

   Get-CMDeployment | Select $searchFilterArray | ForEach-Object {
      $deploymentInfo = @{}
      $deployment = $_
      $deployment | Get-Member -MemberType Properties | ForEach-Object {
         $key = $_.name
         $deploymentInfo.Add($key, $deployment.$key)
      }

      $resultArray += $deploymentInfo
   }

   ConvertTo-Json $resultArray
}

$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Get-Deployments}'"
    Invoke-Command -Session $session -ScriptBlock ${function:Get-Deployments}
} finally {
    Remove-PSSession -session $session
}
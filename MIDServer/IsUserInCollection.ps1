Param([string]$collection, [string]$user)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_collection) {
  $collection = $env:SNC_collection
  $user = $env:SNC_user
}

SNCLog-ParameterInfo @("Running IsUserInCollection", $collection, $user)

function TestUserCollection() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $collectionName = $args[0]; 
   $username = "*\" + $args[1] + " *";

   $collection = Get-CMUserCollection -Name $collectionName;
   If($collection -eq $null  -or  $collection.CollectionType -ne 1) {   # user collection type is 1
      return $false;
   }
   If($collection.MemberCount -lt 1) {   #don't have any member in the collection
      return $false;
   }

   $userId = (Get-CMUser -Name $userName).ResourceID;  
   If ($userId -eq $null) {
      return $false;
   }

   $users = Get-CMUserCollectionDirectMembershipRule -CollectionName $collectionName;
   ForEach($user in $users) {
       if ($userId -eq $user.ResourceID) {
          return $true;
        }
   }
   
   return $false;
}

$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:TestUserCollection}' -ArgumentList $collection, $user"
    Invoke-Command -Session $session -ScriptBlock ${function:TestUserCollection} -ArgumentList $collection, $user
} finally {
    Remove-PSSession -session $session
}
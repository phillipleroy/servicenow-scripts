Param([string]$collection, [string]$user)

# Import SCCM module
Import-Module "$executingScriptDirectory\SCCM" -DisableNameChecking

# Copy the environment variables to their parameters
if (test-path env:\SNC_collection) {
   $collection  = $env:SNC_collection
   $user = $env:SNC_user
}
SNCLog-ParameterInfo @("Running RemoveFromUserCollection", $collection, $user)

function Remove-FromUserCollection() {
   Import-Module -Name "$(split-path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
   Set-Location -path "$(Get-PSDrive -PSProvider CMSite):\"

   $collection = $args[0]
   $username = "*\" + $args[1] + " *"

   $id = (Get-CMUser -Name $username).ResourceID
   Remove-CMUserCollectionDirectMembershipRule -CollectionName $collection -ResourceId $id -Force
}

$session = Create-PSSession -sccmServerName $computer -credential $cred
try {
    SNCLog-DebugInfo "`tInvoking Invoke-Command -ScriptBlock `$'{function:Remove-FromUserCollection}' -ArgumentList $collection, $user"
    Invoke-Command -Session $session -ScriptBlock ${function:Remove-FromUserCollection} -ArgumentList $collection, $user
} finally {
    Remove-PSSession -session $session
}
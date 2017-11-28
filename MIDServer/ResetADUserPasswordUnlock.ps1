import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_accountName) {
  $accountName=$env:SNC_accountName;
  $accountPassword=$env:SNC_accountPassword;
};

$hiddenPwd = SNCObfuscate-Value -theString $accountPassword
SNCLog-ParameterInfo @("Running ResetADUserPasswordUnlock", $accountName, $hiddenPwd)

resetActiveDirectoryUserPasswordUnlockOption -domainController $computer -username $accountName -accountPassword $accountPassword -unlock $unlock -forceChange $forceChange -useCred $useCred -credential $cred
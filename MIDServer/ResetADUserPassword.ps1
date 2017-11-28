import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_accountName) {
  $accountName=$env:SNC_accountName;
  $accountPassword=$env:SNC_accountPassword;
};

resetActiveDirectoryUserPassword -domainController $computer -username $accountName -accountPassword $accountPassword -forceEnable $forceEnable -forceChange $forceChange -useCred $useCred -credential $cred
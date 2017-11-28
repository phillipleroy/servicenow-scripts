import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_accountName) {
  $accountName=$env:SNC_accountName;
};

unlockAccount -domainController $computer -username $accountName -useCred $useCred -credential $cred
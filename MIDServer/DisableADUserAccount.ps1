import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_accountName) {
   $accountName=$env:SNC_accountName;
};

disableADUserAccount -domainController $computer -username $accountName -useCred $useCred -credential $cred
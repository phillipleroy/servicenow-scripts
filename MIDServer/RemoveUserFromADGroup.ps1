import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_groupname) {
  $groupname = $env:SNC_groupname;
  $username = $env:SNC_username;
};

removeADUserAccountFromGroup -domainController $computer -username $username -groupname $groupname -useCred $useCred -credential $cred
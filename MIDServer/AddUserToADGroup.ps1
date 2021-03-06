import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_groupname) {
  $groupname = $env:SNC_groupname;
  $username = $env:SNC_username;
};

SNCLog-ParameterInfo @("Running AddUserToADGroup", $groupname, $username)

addADUserAccountToGroup -domainController $computer -username $username -groupname $groupname -useCred $useCred -credential $cred
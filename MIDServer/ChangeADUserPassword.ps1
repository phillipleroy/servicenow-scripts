import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_accountName) {
  $accountName=$env:SNC_accountName;
  $oldPassword=$env:SNC_oldPassword;
  $newPassword=$env:SNC_newPassword;
};

$oldHiddenPwd = SNCObfuscate-Value -theString $oldPassword
$newHiddenPwd = SNCObfuscate-Value -theString $newPassword
SNCLog-ParameterInfo @("Running ChangeADUserPassword", $accountName, $oldHiddenPwd, $newHiddenPwd)

changeActiveDirectoryUserPassword -domainController $computer -username $accountName -oldPassword $oldPassword -newPassword $newPassword -useCred $useCred -credential $cred
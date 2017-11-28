import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_type) {
  $type=$env:SNC_type;
  $objectName=$env:SNC_objectName;
};

removeActiveDirectoryObject -domainController $computer -type $type -objectName $objectName -useCred $useCred -credential $cred
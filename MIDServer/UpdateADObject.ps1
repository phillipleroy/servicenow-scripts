import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_type) {
  $type=$env:SNC_type;
  $objectName=$env:SNC_objectName;
  $objectData=$env:SNC_objectData;
};

updateActiveDirectoryObject -domainController $computer -type $type -objectName $objectName -objectProperties $objectData -useCred $useCred -credential $cred
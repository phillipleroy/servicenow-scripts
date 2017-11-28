import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_type) {
  $type=$env:SNC_type;
  $organizationUnit=$env:SNC_organizationUnit;
  $objectName=$env:SNC_objectName;
  $objectData=$env:SNC_objectData;
};

createActiveDirectoryObject -domainController $computer -type $type -organizationUnit $organizationUnit -objectName $objectName -objectProperties $objectData -useCred $useCred -credential $cred
import-module "$executingScriptDirectory\AD\ActiveDirectory"

if (test-path env:\SNC_searchFilter) {
  $searchFilter=$env:SNC_searchFilter
  $properties=$env:SNC_properties; 
};

queryActiveDirectory -domainController $computer -searchFilter $searchFilter -properties $properties -useCred $useCred -credential $cred
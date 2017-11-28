if (test-path env:\SNC_state) {
  $state=$env:SNC_state;
  $service=$env:SNC_service;
};

$op = $state;
$filter = "name='" + $service +"'";

SNCLog-ParameterInfo @("Running ChangeServiceState", $op, $filter)
SNCLog-DebugInfo "`tInvoking Get-WMiObject cmdlet"

if ($useCred) {
    $serviceObj = gwmi -class Win32_Service -namespace root\cimv2 -computer $computer -credential $cred -impersonation impersonate -authentication packetprivacy -filter $filter;
} else {
    $serviceObj = gwmi -class Win32_Service -namespace root\cimv2 -computer $computer -impersonation impersonate -authentication packetprivacy -filter $filter;
}

if ($serviceObj -eq $null) {
    [Console]::Error.WriteLine("The service " + $service + " could not be found.");
	SNCLog-DebugInfo "`tThe service $service could not be found."
    return;
}

if ((($serviceObj.State -eq "Running") -and ($op -ne "StartService")) -or (($serviceObj.State -eq "Stopped") -and ($op -ne "StopService"))) {
    $result = $serviceObj.invokemethod($op, $null);
    if ($result -ne 0) {
        $error = new-object System.ComponentModel.Win32Exception([Int32]$result); 
        [Console]::Error.WriteLine("The operation failed: " + $error.Message); 
        SNCLog-DebugInfo "`tChange service state failed:  $error.Message"
    }
}
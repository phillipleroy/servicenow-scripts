SNCLog-ParameterInfo @("Running RestartWindowsServer")

$ips = gwmi -query 'select ipaddress from win32_networkadapterconfiguration where ipenabled=true';
SNCLog-DebugInfo "`t`$ips:$ips"

foreach($ip in $ips) {
    if ($computer.equals($ip.ipaddress[0]) -or $computer.equals("127.0.0.1")) {
        SNCLog-DebugInfo "`tThe MID Server is not allowed to be rebooted with this activity"
        [Console]::Error.WriteLine("The MID Server is not allowed to be rebooted with this activity.");
        return;
     }
}

$os = gwmi -class Win32_OperatingSystem -namespace root\cimv2 -computer $computer -credential $cred -impersonation impersonate -authentication packetprivacy;
$os.psbase.Scope.Options.EnablePrivileges = $true;

$result = $os.reboot();
if ($result.ReturnValue -ne 0) {
    SNCLog-DebugInfo "`tThe operation failed with return code: $result.ReturnValuey"
    [Console]::Error.WriteLine("The operation failed with return code" + $result.ReturnValue);
}

SNCLog-DebugInfo "`t`$computer server was restarted"
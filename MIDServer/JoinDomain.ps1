if (test-path env:\SNC_domain) {
  $domain=$env:SNC_domain;
  $domain_user=$env:SNC_domain_user;
  $domain_password=$env:SNC_domain_password;
};

$hiddenPwd = SNCObfuscate-Value -theString $domain_password
SNCLog-ParameterInfo @("Running RestartWindowsServer", $domain, $domain_user, $hiddenPwd)

$server = gwmi -class Win32_ComputerSystem -namespace root\cimv2 -computer $computer -credential $cred -impersonation impersonate -authentication packetprivacy;
$result = $server.JoinDomainOrWorkGroup($domain, $domain_password, $domain_user, $null, 3);

if ($result.ReturnValue -ne 0) {
    $error = new-object System.ComponentModel.Win32Exception([Int32]$result.ReturnValue); 
    SNCLog-DebugInfo "`t $domain_user failed to joined $domain : $error"
    [Console]::Error.WriteLine("The operation failed: " + $error.Message);
}

SNCLog-DebugInfo "`t $domain_user joined $domain"
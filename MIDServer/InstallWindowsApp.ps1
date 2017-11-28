if (test-path env:\SNC_installerpath) {
  $installerpath=$env:SNC_installerpath;
  $installer=$env:SNC_installer;
  $arguments=$env:SNC_arguments;
};

SNCLog-ParameterInfo @("Running InstallWindowsApp", $installerpath, $installer, $arguments)

if ($useCred) {
    $system = Get-WmiObject Win32_ComputerSystem -ComputerName $computer -credential $cred;
    $domain = Get-WmiObject Win32_NTDomain -ComputerName $computer  -credential $cred -Filter "DNSForestName = '$($system.Domain)'";
} else {
    $system = Get-WmiObject Win32_ComputerSystem -ComputerName $computer;
    $domain = Get-WmiObject Win32_NTDomain -ComputerName $computer  -Filter "DNSForestName = '$($system.Domain)'";
}
SNCLog-DebugInfo "`t`$domain: $domain"

$authority="kerberos:$($domain.DomainName)\$($system.Name)";
$fullinstaller = join-path $installerpath $installer;
$errMsg="$fullinstaller could not be installed on $computer.";

if ($system.Name.compareTo($env:COMPUTERNAME) -eq 0) {
    $product = Get-WMIObject Win32_Product -List;
} else {
    $product = Get-WMIObject Win32_Product -List -Authority $authority -Authentication PacketIntegrity -ComputerName $computer -Credential $cred -Impersonation Delegate;
}
SNCLog-DebugInfo "`t`$product: $product"

if (-not $?) {
	SNCLog-DebugInfo "$errMsg"
    throw ($errMsg);
} else {
    $status = $product.Install($fullinstaller, $arguments, $true);
    if ($status.ReturnValue -ne 0) {
        $error = new-object System.ComponentModel.Win32Exception([Int32]$status.ReturnValue);
        SNCLog-DebugInfo "$errMsg : Installer reported status = $status.ReturnValue  $error.Message"
        throw ("$errMsg : Installer reported status = $($status.ReturnValue), $($error.Message). ");
    }
}
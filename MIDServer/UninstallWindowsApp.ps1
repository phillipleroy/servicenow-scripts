SNCLog-DebugInfo "Running UninstallWindowsApp.ps1"

if (test-path env:\SNC_product) {
  $product=$env:SNC_product;
};

SNCLog-ParameterInfo @("Running UninstallWindowsApp", $product)

if ($useCred) {
    $app = gwmi win32_product -computer $computer -credential $cred | where-object {$_.Name.equals($product)};
} else {
    $app = gwmi win32_product -computer $computer | where-object {$_.Name.equals($product)};
}
SNCLog-DebugInfo "`t`$app:$app"

if ($app) {
    $status = $app.Uninstall();
    if ($status.ReturnValue -ne 0) {
        $error = new-object System.ComponentModel.Win32Exception([Int32]$status.ReturnValue);
        SNCLog-DebugInfo "`tFailed to uninstall : $error"
        [Console]::Error.WriteLine("The application could not be uninstalled from:" + $computer + " : " +  $error.Message);
    }
} else {
    [Console]::Error.WriteLine("Failure uninstalling: " + $product);
    SNCLog-DebugInfo "`tFailed to uninstall $product from $computer"
}
SNCLog-DebugInfo "`t$product was uninstalled from $computer"
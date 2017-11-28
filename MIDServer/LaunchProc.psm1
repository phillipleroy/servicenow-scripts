<######################
 #	Launch a process against a target computer.  Write the output of that process to the admin temp share on that machine.
 #  Access to the machine and the admin share is done using the $cred parameter if there is one.  To get information from
 #  the admin temp share, an impersonation context is used for the user of the given credential if there is one.  The default 
 #  time to wait is about 10 seconds before declaring failure.  That can be changed by the calling script in the
 #  parameter $secondsToWait
 ######################>
function launchProcess {
    param([string]$computer, [System.Management.Automation.PSCredential]$cred, [string]$command, [int]$secondsToWait = 10)

    SNCLog-DebugInfo "Running launchProcess"

    $signature = @"
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);
"@;

    $LogOnUser = Add-Type -memberDefinition $signature -name "Win32LogOnUser" -namespace Win32Functions -passThru;

    [IntPtr]$userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token;

    $context = $null
    if ($cred) {
        if ($LogOnUser::LogOnUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 9, 0, [ref]$userToken)) {
           $Identity = new-object security.Principal.WindowsIdentity $userToken
    	   $context = $Identity.Impersonate();
        }
        else {
            $err = "The impersonation of user $($cred.UserName) failed."
            [Console]::Error.WriteLine($err)
            return;
        }
    }

	$guid = [Guid]::NewGuid().ToString()
 	$outputFile = "\\$computer\admin$\temp\psscript_output_$($guid).txt"
    $fullCommand = "cmd /c $command > $outputFile";
    if ($cred) {
	   $processInfo = invoke-wmimethod win32_process -name create -computer $computer -credential $cred -argumentlist $fullCommand -EA "Stop"
    } else {
	   $processInfo = invoke-wmimethod win32_process -name create -computer $computer -argumentlist $fullCommand -EA "Stop"
    }
    SNCLog-DebugInfo "`t`$fullCommand: $fullCommand"

	if ($processInfo.ReturnValue -eq 0) {
		$id = $processInfo.processId
        $proc = getProcess -computer $computer -cred $cred -filter "processId=$id"
    
        $date = get-date
        $enddate = $date.AddSeconds($secondsToWait);

		while ($proc -and ($date -lt $enddate)) {
			sleep(1)
			$proc = getProcess -computer $computer -cred $cred -filter "processId=$id"
            		$date = get-date
		}

        if ([System.IO.File]::Exists($outputFile)) {
            # Maximize console width so StreamGobbler can gobble 
            # more than the 80 character default per line
            mode con lines=1 cols=9999;
            # File output is done with the "type" shell command.
            # it was previously done with Get-Content which added a line-break for any line longer than 80 characters, 
            # and "more" which had problems with output of unicode.
            type $outputFile;
            remove-item $outputFile;
        } else {
            $err = "The result file can't be fetched because it doesn't exist"
            [Console]::Error.WriteLine($err);
            SNCLog-DebugInfo "$err"
            return;
        }
    } else {
        $err = "Failed to launch process $command with error $processInfo"
        [Console]::Error.WriteLine($err)
        SNCLog-DebugInfo "$err"
        return;
   	}
    
    if ($context) {
		$context.Undo();
		$context.Dispose();
    }
    
    return;
}

function getProcess {
    param([string]$computer, [System.Management.Automation.PSCredential]$cred, [string]$filter)

    SNCLog-DebugInfo "Running getProcess"
    
    if ($cred) {
        $proc = gwmi win32_process -computer $computer -credential $cred -filter $filter
    } else {
        $proc = gwmi win32_process -computer $computer -filter $filter
    }
    SNCLog-DebugInfo "`t`$proc: $proc"
    
    return $proc
}
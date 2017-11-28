<######################
 #  Turn user/password into a credential object for use in cmdlets that take a credential
 ######################>
function getCredential {
    if (test-path env:\SNC_password) {
        $passwordSecure = convertto-securestring -string $env:SNC_password -asplaintext -force;
    } else {
        # If no password was supplied, use an empty instance of SecureString
        $passwordSecure = new-object System.Security.SecureString;
    }
    
    $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$env:SNC_username",$passwordSecure;

    return $cred;
}

# Utility function to create a System.Management.Automation.PSCredential object
function getCred {
param([string]$user, [string]$password)

	if ($password) {
		$passwordSecure = convertto-securestring -string $password -asplaintext -force;
	} else {
		# If no password was supplied, use an empty instance of SecureString
		$passwordSecure = new-object System.Security.SecureString;
	}
	
	$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$user",$passwordSecure;

	return $cred;
}

function getDummyCredential {
    param([string]$username, [string]$password)

    $passwordSecure = convertto-securestring -string $password -asplaintext -force;
    $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$username",$passwordSecure;

    return $cred;
}

<######################
 #  Test the given user and password on the given computer using the test-wsman cmdlet.
 ######################>
function testCredentialWinRM {
    $cred = getCredential
    try {
        $results = test-wsman -computer $computer -port $env:SNC_targetPort -credential $cred -authentication default
    } catch [InvalidOperationException] {
        handleExit 1
    }

    return $cred;
}

<######################
 #  Test the given user and password on the given computer using a get-WMIobject 
 #  call to fetch the operating system information.  It uses EA (ErrorAction) Stop to force
 #  the exception handling to handle the error.  This is particularly useful for the error
 #  0x800706BA - The RPC server is unavailable which normally does not get caught in the
 #  exception handling.  If the user and password authenticate successfully against the system,
 #  return a credential object for that user/password
 ######################>
function testCredentialWMI {
    param([boolean]$debug)
    
    $cred = getCredential

    #Just eat the results - mostly concerned with capturing errors
    $results = gwmi win32_operatingsystem -computer $computer -credential $cred -impersonation 3 -authentication 6 -EA "Stop";
    return $cred;
}

<######################
 #  Test the ability to reach a given computer without credentials using a get-WMIobject 
 #  call to fetch the operating system information.  It uses EA (ErrorAction) Stop to force
 #  the exception handling to handle the error.  This is particularly useful for the error
 #  0x800706BA - The RPC server is unavailable which normally does not get caught in the
 #  exception handling.  Bail out of the script if the computer can't be reached.
 ######################>
function testNoCredentialAccessWMI {
    param([boolean]$debug)
    
    try {
        #Just eat the results - mostly concerned with capturing errors
        $results = gwmi win32_operatingsystem -computer $computer -impersonation 3 -authentication 6 -EA "Stop";
    } catch [System.Exception] {
        [Console]::Error.WriteLine("Failed to access target system.  Please check credentials and firewall settings on the target system to ensure accessibility: " + $_.Exception.Message)

        if ($debug) {
            [Console]::Error.WriteLine("`r`n Stack Trace: " + $_.Exception.StackTrace)
        }
        handleExit 3;
    }
}

<######################
 #  Start an impersonation context where script code executed between this call and the EndImpersonate call is executed
 #  in the security context of the given credential
 #
 #  Return: a context that should be passed to EndImpersonation when the security context of the given credential
 #  is not needed anymore
 ######################>
function startImpersonation {
    $context = $null
    
    if ($cred) {
        $signature = "[DllImport(""advapi32.dll"", SetLastError = true)] `
                public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, `
                int dwLogonType, int dwLogonProvider, ref IntPtr phToken);";

        $LogOnUser = Add-Type -memberDefinition $signature -name "Win32LogOnUser" -passThru;

        [IntPtr]$userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token;

        # The 9 means LOGON32_LOGON_NEW_CREDENTIALS: See definition at http://msdn.microsoft.com/en-us/library/aa378184%28VS.85%29.aspx
        if ($LogOnUser::LogOnUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, 
                    $cred.GetNetworkCredential().Password, 9, 0, [ref]$userToken)) {
            $Identity = new-object security.Principal.WindowsIdentity $userToken
            $context = $Identity.Impersonate();
        }
    }

    return $context;
}


<######################
 #  End a given impersontation context that was started with StartImpersonation
 ######################>
function endImpersonation {
    param([System.Security.Principal.WindowsImpersonationContext]$context)

    if ($context) {
        $context.Undo();
        $context.Dispose();
    }
}
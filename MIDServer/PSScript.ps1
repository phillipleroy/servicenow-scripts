Param([string]$computer, [string]$script, [boolean]$useCred, [boolean]$isMid, [boolean]$isDiscovery, [boolean]$debug, [boolean]$logInfo)

$global:AutomaticVariables = Get-Variable
# Copy the environment variables to the params
if(test-path env:\SNCUser) {
  $Private:user=$env:SNCUser
  $Private:password=$env:SNCPass
  $env:SNCUser=''
  $env:SNCPass=''
  $global:encryptedVars=$env:SNCEncryptedVars
}

$executingScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$midScriptDirectory = $executingScriptDirectory -replace "\\[\w]*$", ""
$global:logInfo=$logInfo

import-module "$executingScriptDirectory\Credentials"  -DisableNameChecking
import-module "$executingScriptDirectory\WMIFetch"
import-module "$executingScriptDirectory\XMLUtil"
import-module "$executingScriptDirectory\LaunchProc"
import-module  "$executingScriptDirectory\DiagnosticsUtil" -DisableNameChecking

# Debugging information ...
SNCLog-PowershellVersion
SNCLog-EnvironmentVars
SNCLog-ParameterInfo @("Executing PSScript.ps1", $computer, $script, $useCred, $isMid, $isDiscovery)

# This part exposes any arguments that are in addition to the parameters to the current scope
for ($i = 0; $i -lt $args.count; $i += 2) {
    $value = ''
    if ($i + 1 -lt $args.count) {
        $value = $args[$i + 1]
    }
    if ($value -eq $null) {
        new-variable -name $args[$i] -value $null
    } elseif ($value.getType().Name -eq "Boolean") {
        if ($value) {
            new-variable -name $args[$i] -value $true
        } else {
            new-variable -name $args[$i] -value $false
        }
    } else {
        new-variable -name $args[$i] -value $value
    }

    remove-variable -name value
}

# This part attempts to access the target system, just to see if we have access - if using credentials, it tries to figure out
# the appropriate credential checking mechanism by looking for a $credType in the argument list - if it is not set, assume
# WMI
if($credType -eq $null) {
  if(test-path env:\SNC_credType) {
    $credType=$env:SNC_credType
  }
}

$cred = $null
if ($credType -eq $null) {
    SNCLog-DebugInfo "`t`$credType is undefined, defaulting to WMI"
    $credType = "WMI"
}

$credTestFunc = "testCredential" + $credType
$noCredTestFunc = "testNoCredentialAccess" + $credType

#
# This part checks to see if the target host is the mid and if the usecred variable is set to true.  If both are correct the testCredentialGetCred is called in the 
# credentials.psm1 module.
#
if($isMid -and $useCred) {
	$credType = "GetCred"
	$credTestFunc = "testCredential" + $credType
} 

try {
    if ($useCred) {
        $cred = & $credTestFunc -computer $computer -user $Private:user -password $Private:password -debug $debug
    } else {
        & $noCredTestFunc -computer $computer -debug $debug
    }
} catch [System.Exception] {
	[Console]::Error.WriteLine($_.Exception.Message)
	exit 2;
}

# This part actually sets up to run the real script
# Format the result in XML for the payload parser - if asked for
if (!$isDiscovery) {
    write-host "<powershell>"
    write-host "<output>"
}
    
# We will attempt to capture any available HRESULT
$hresult = $null
# Run the script file passed in and attempt to catch any exception in the script content 
# so the error will be reported on stderr
try {
	 $ErrorActionPreference = 'Stop'
    # Copy ALL the SNC_* environment variables to PowerShell variables, don't burden users with knowing about environment variable magic
    dir env: | ForEach-Object {
        if ($_.name.StartsWith("SNC_")) {
             # Force it so that we do not get the name clash. It won't overwrite any read-only variable (http://technet.microsoft.com/en-us/library/hh849913.aspx)
             New-Variable -name $_.name.Replace("SNC_", "") -value $_.value -Force  
        }
    }

	# Show all the variables available (debugging info)
	SNCLog-Variables

    & $script
} catch [System.UnauthorizedAccessException] {
    # If the credential passed the credential check for logging into the target system, but doesn't have rights to commit
    # the changes (for example: The user can log into AD but cannot create new account), we want to try the next credential. 
    if ($useCred) { 
        exit 1;
    } else {
        exit 3; // MID Server service user
    }
} catch [System.Exception] {
    [Console]::Error.WriteLine($_.Exception.Message)
    if ($_.Exception.ErrorCode) {           # Attempt to read HRESULT provided by an ExternalException
        $hresult = $_.Exception.ErrorCode
    } elseif ($_.Exception.HResult) {      # Attempt to read HRESULT provided by an Exception
        $hresult = $_.Exception.HResult
    }
    if ($debug) {
        [Console]::Error.WriteLine("`r`n Stack Trace: " + $_.Exception.StackTrace)
    }
    if ($isMid) {
         if($useCred) {
         exit 1
        } else {
         exit 4
        }
    } else {
        exit 4
    }
} finally {
    if (!$isDiscovery) {
        write-host "</output>"
        if ($hresult) {
            write-host "<hresult>$hresult</hresult>"
        }
        write-host "</powershell>"
    }
}
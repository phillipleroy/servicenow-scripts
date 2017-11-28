Param([string]$exchangeServer, [string]$domain, [string]$exchangeUser, [string]$parameters)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $exchangeUser=$env:SNC_exchangeUser;
  $parameters=$env:SNC_parameters;
};

SNCLog-ParameterInfo @("Running Exchange-RemoveMailbox", $exchangeServer, $domain, $exchangeUser, $parameters)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Remove-Mailbox switch parameters
# This parameters do NOT require a value...
$switchParams = @{"Arbitration" = "2010,2013";
                              "Confirm" = "2010,2013";
                              "Disconnect" = "2013";
                              "Force" = "2013";
                              "IgnoreDefaultScope" = "2010,2013";
                              "IgnoreLegalHold" = "2010,2013";
                              "KeepWindowsLiveID" = "2010,2013";
                              "PublicFolder" = "2013";
                              "RemoveLastArbitrationMailboxAllowed" = "2010,2013";
                              "WhatIf" = "2010,2013"
                             };

# These parameters are for Microsoft internal use only
$microsoftOnly = @{"Disconnect" = "2013";
                              "ForReconciliation" = "2010,2013"
                             };

# Define hash table
$myParams = @{};

try {
	$myParams.Add("Confirm", $false);
	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters:  $parameters"
		$returnObj = Process-Params -cmd Remove-Mailbox -params $parameters -cmdSwitches $switchParams -internalParams $microsoftOnly -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};
	if ($exchangeUser) {
		$myParams.Add("Identity", $exchangeUser);
	};

	SNCLog-DebugInfo "`tInvoking Remove-Mailbox cmdlet"
	# Call Cmdlet with our defined parameters
	# Note: Remove-Mailbox does not return any data
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Remove-Mailbox $Private:cmdParams"
	Remove-Mailbox @myParams;
	if (-not $?) {
		SNCLog-DebugInfo "`tRemove-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
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

SNCLog-ParameterInfo @("Running Exchange-DisableMailbox", $exchangeServer, $domain, $exchangeUser, $parameters)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Disable-Mailbox switch parameters
# This parameters do NOT require a value...
# Parameter name is the key and the value is just the version that supports the parameter
$switchParams = @{"Arbitration" = "2010,2013";
                              "Archive" = "2010,2013";
                              "Confirm" = "2010,2013";
                              "DisableLastArbitrationMailboxAllowed" = "2010,2013";
                              "IgnoreDefaultScope" = "2010,2013";
                              "IgnoreLegalHold" = "2010,2013";
                              "IncludeSoftDeletedObjects" = "2013";
                              "PreserveEmailAddresses" = "2013";
                              "PreventRecordingPreviousDatabase" = "2013";
                              "PublicFolder" = "2013";
                              "RemoteArchive" = "2013";
                              "WhatIf" = "2010,2013"
                             };

# These parameters are for Microsoft internal use only
# Parameter name is the key and the value is just the version that supports the parameter
$microsoftOnly = @{"IncludeSoftDeletedObjects" = "2013"
                                    "PreserveEmailAddresses" = "2013";
                                    "PreventRecordingPreviousDatabase" = "2013";
                              };

# Define hash table
$myParams = @{};

try {
	if ($exchangeUser) {
		$myParams.Add("Identity", $exchangeUser);
	};
	$myParams.Add("Confirm", $false);

	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters:  $parameters"
		$returnObj = Process-Params -cmd Disable-Mailbox -params $parameters -cmdSwitches $switchParams -internalParams $microsoftOnly -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Disable-Mailbox -Identity $exchangeUser -Confirm:$false
	# Note: Disable-Mailbox does not return any data
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Disable-Mailbox $Private:cmdParams"
	Disable-Mailbox @myParams;
	if (-not $?) {
		SNCLog-DebugInfo "`tDisable-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
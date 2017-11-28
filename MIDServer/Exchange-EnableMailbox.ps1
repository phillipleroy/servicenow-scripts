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

SNCLog-ParameterInfo @("Running Exchange-EnableMailbox", $exchangeServer, $domain, $exchangeUser)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Enable-Mailbox switch parameters
# This parameters do NOT require a value...
# Parameter name is the key and the value is just the version that supports the parameter
$switchParams = @{"Arbitration" = "2010,2013";
                              "Discovery" = "2010,2013";
                              "Equipment" = "2010,2013";
                              "PublicFolder" = "2013";
                              "Room" = "2010,2013";
                              "Shared" = "2010,2013";
                              "Archive" = "2010,2013";
                              "BypassModerationCheck" = "2010,2013";
                              "Confirm" = "2010,2013";
                              "Force" = "2010,2013";
                              "HoldForMigration" = "2013";
                              "IncludeSoftDeletedObjects" = "2013";
                              "ManagedFolderMailboxPolicyAllowed" = "2010,2013";
                              "OverrideRecipientQuotas" = "2013";
                              "RemoteArchive" =  "2010,2013";
                              "TargetAllMDBs" = "2013";
                              "WhatIf" =  "2010,2013"
                             };

# MultiValued parameters
# Parameter name is the key and the value is just the version that supports the parameter
$multiValued = @{"AddOnSKUCapability" = "2013";
                           "ArchiveName" = "2010,2013"
                          };

# These parameters are for Microsoft internal use only
# Parameter name is the key and the value is just the version that supports the parameter
$microsoftOnly = @{"AccountDisabled" = "2010,2013";
                              "AddOnSKUCapability" = "2013";
                              "ArchiveGuid" = "2010,2013";
                              "BypassModerationCheck" = "2010,2013";
                              "IncludeSoftDeletedObjects" = "2013";
                              "Location" = "2013";
                              "MailboxPlan" = "2013";
                              "OverrideRecipientQuotas" = "2013";
                              "SKUAssigned" = "2010,2013";
                              "SKUCapability" = "2010,2013";
                              "TargetAllMDBs" = "2013";
                              "UsageLocation" = "2010,2013"
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
		$returnObj = Process-Params -cmd Enable-Mailbox -params $parameters -cmdSwitches $switchParams -internalParams $microsoftOnly -multiValueParams $multiValued -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Enable-Mailbox -Identity $exchangeUser -Confirm:$false
	# Note: Enable-Mailbox does not return any data
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Enable-Mailbox $Private:cmdParams"
	Enable-Mailbox @myParams;
	if (-not $?) {
		SNCLog-DebugInfo "`tEnable-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
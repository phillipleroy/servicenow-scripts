[CmdletBinding()]
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

SNCLog-ParameterInfo @("Running Exchange-GetMailbox", $exchangeServer, $domain, $exchangeUser)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Get-Mailbox switch parameters
# This parameters do NOT require a value...
# Parameter name is the key and the value is just the version that supports he parameter
$switchParams = @{"Arbitration" = "2010,2013";
                              "Archive" = "2010,2013";
                              "ForReconciliation" = "2010";
                              "IgnoreDefaultScope" = "2010,2013";
                              "InactiveMailboxOnly" = "2013";
                              "IncludeInactiveMailbox" = "2013";
                              "IncludeSoftDeletedMailbox" = "2013";
                              "Monitoring" = "2013";
                              "PublicFolder" = "2013";
                              "ReadFromDomainController" = "2010,2013";
                              "RemoteArchive" = "2010,2013";
                              "SoftDeletedMailbox" = "2013"
                             };

# These parameters are for Microsoft internal use only
# Parameter name is the key and the value is just the version that supports the parameter
$microsoftOnly = @{"AccountPartition" = "2013";
                              "ForReconciliation" = "2010";
                              "IncludeSoftDeletedMailbox" = "2013";
                              "Organization" = "2013";
                              "UsnForReconciliationSearch" = "2013"
                              };

# Define hash table
$myParams = @{};

try {
	if ($exchangeUser) {
		$myParams.Add("Identity", $exchangeUser);
	}

	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters: $parameters"
		$returnObj = Process-Params -cmd Get-Mailbox -params $parameters -cmdSwitches $switchParams -cmdSecurity $securityParmas -multiValueParams $multiValued -internalParams $microsoftOnly  -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Get-Mailbox -Anr Ale -ResultSize 5 | ConvertTo-XML -As Stream -Depth 4 -NoTypeInformation;
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Get-Mailbox $Private:cmdParams"
	Get-Mailbox @myParams | ConvertTo-XML -As String -Depth 4 -NoTypeInformation;
	if (-not $?) {
		SNCLog-DebugInfo "`tGet-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
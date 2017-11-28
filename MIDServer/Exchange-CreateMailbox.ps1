Param([string]$exchangeServer, [string]$domain, [string]$firstName, [string]$middleInitial, [string]$lastName, [string]$alias, [string]$accountPassword, [string]$parameters)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $accountPassword=$env:SNC_accountPassword;
  $firstName=$env:SNC_firstName;
  $middleInitial=$env:SNC_middleInitial;
  $lastName=$env:SNC_lastName;
  $alias=$env:SNC_alias;
  $parameters=$env:SNC_parameters;
};
$hiddenPwd = SNCObfuscate-Value -theString $accountPassword
SNCLog-ParameterInfo @("Running Exchange-CreateMailbox", $exchangeServer, $domain, $hiddenPwd, $firstName, $middleInitial, $lastName, $alias)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# New-Mailbox switch parameters
# This parameters do NOT require a value...
# Parameter name is the key and the value is just the version that supports the parameter
$switchParams = @{"AccountDisabled" = "2010,2013";
                              "Arbitration" = "2010,2013";
                              "Discovery" = "2010,2013";
                              "Equipment" = "2010,2013";
                              "ImportLiveId" = "2010,2013";
                              "PublicFolder" = "2013";
                              "Room" = "2010,2013";
                              "Shared" = "2010,2013";
                              "UseExistingLiveId" = "2010,2013";
                              "Archive" = "2010,2013";
                              "BypassLiveId" = "2010,2013";
                              "Confirm" = "2010,2013";
                              "EvictLiveId" = "2010,2013";
                              "Force" = "2010,2013";
                              "HoldForMigration" = "2013";
                              "ManagedFolderMailboxPolicyAllowed" = "2010,2013";
                              "OverrideRecipientQuotas" = "2010,2013";
                              "RemoteArchive" = "2010,2013";
                              "WhatIf" = "2010,2013"
                             };

# MultiValued parameters
# Parameter name is the key and the value is just the version that supports the parameter
$multiValued = @{"AddOnSKUCapability" = "2013";
                           "ModeratedBy" = "2010,2013"
                          };

# These parameters are security string type
$securityParams = @{"RoomMailboxPassword" = "2010,2013"
                                         };

# These parameters are for Microsoft internal use only
# Parameter name is the key and the value is just the version that supports the parameter
$microsoftOnly = @{"AddOnSKUCapability" = "2013";
                              "BypassLiveId" = "2010,2013";
                              "ExternalDirectoryObjectId" = "2010,2013";
                              "Location" = "2013";
                              "NetID" = "2010,2013";
                              "Organization" = "2013";
                              "OriginalNetID" = "2013";
                              "OverrideRecipientQuotas" = "2013";
                              "PartnerObjectId" = "2010";
                              "QueryBaseDNRestrictionEnabled" = "2013";
                              "RemoteAccountPolicy" = "2010,2013";
                              "RemovedMailbox" = "2010,2013";
                              "SKUAssigned" = "2010,2013";
                              "SKUCapability" = "2010,2013";
                              "TargetAllMDBs" = "2013";
                              "UsageLocation" = "2010,2013"
                             };

# Define hash table
$myParams = @{};

try {
	$theName = $null;
	$thePassword = $null;

	if ($accountPassword) {
		$thePassword = $accountPassword | ConvertTo-SecureString -AsPlainText -Force;
		if ($thePassword) {
			$myParams.Add("Password", $thePassword);
		}
	};
	if ($middleInitial) {
		$theName = $firstName + '  ' + $middleInitial + '. ' + $lastName;
		$myParams.Add("Initials", $middleInitial);
	} else {
		$theName = $firstName + ' ' + $lastName;
	};
	if ($exchangeUser) {
		$myParams.Add("Identity", $exchangeUser);
	};
	if ($firstName) {
		$myParams.Add("FirstName", $firstName);
	};
	if ($lastName) {
		$myParams.Add("LastName", $lastName);
	};
	if ($alias) {
		$myParams.Add("Alias", $alias);
	};

	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters:  $parameters"
		$returnObj = Process-Params -cmd New-Mailbox -params $parameters -cmdSwitches $switchParams -cmdSecurity $securityParams -multiValueParams $multiValued -internalParams $microsoftOnly -inputParams $myParams;

		# retrieve the returned data
		$myParams = $returnObj;
	};

	if ($myParams) {
		# User did not specified 'Name', generate one;
		if (! $myParams.ContainsKey("Name")) {
			$myParams.Add("Name", $theName);
		};
		# User did not specified 'UserPrincipalName', generate one;
		if (! $myParams.ContainsKey("UserPrincipalName")) {
			$principalName = $theName + '@' + $domain;
			# If alias was provided, use it
			if ($alias) {
				$principalName = $alias + '@' + $domain;
			}
			$myParams.Add("UserPrincipalName", $principalName);
		};
	};

	# Call Cmdlet with our defined parameters
	# e.g.: New-Mailbox -UserPrincipalName $principalName -Alias $alias -Name $name -FirstName $firstName -LastName $lastName -Password $thePassword -ResetPasswordOnNextLogon $true;

	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking New-Mailbox $Private:cmdParams"
	New-Mailbox @myParams | ConvertTo-XML -As Stream -Depth 4 -NoTypeInformation;
	if (-not $?) {
		SNCLog-DebugInfo "`tNew-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
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

SNCLog-ParameterInfo @("Running Exchange-SetMailbox", $exchangeServer, $domain, $exchangeUser, $parameters)
$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Set-Mailbox switch parameters
# This parameters do NOT require a value...
$switchParams = @{"ApplyMandatoryProperties" = "2010,2013";
                               "Arbitration" = "2010,2013";
                              "BypassLiveId" = "2010,2013";
                              "Confirm" = "2010,2013";
                              "EvictLiveId" = "2010,2013";
                              "Force" = "2010,2013";
                              "IgnoreDefaultScope" = "2010,2013";
                              "ManagedFolderMailboxPolicyAllowed" = "2010,2013";
                              "PublicFolder" = "2013";
                              "RemoveManagedFolderAndPolicy" = "2010,2013";
                              "RemovePicture" = "2010,2013";
                              "RemoveSpokenName" = "2010,2013";
                              "WhatIf" = ""
                             };

# MultiValued parameters
$multiValued = @{"AcceptMessagesOnlyFrom" = "2010,2013";
                                  "AcceptMessagesOnlyFromDLMembers" = "2010,2013";
                                  "AcceptMessagesOnlyFromSendersOrMembers" = "2010,2013";
                                  "AddOnSKUCapability" = "2013";
                                  "ArchiveName" = "2010,2013";
                                  "AuditAdmin" = "2010,2013";
                                  "AuditDelegate" = "2010,2013";
                                  "AuditOwner" = "2010,2013";
                                  "BypassModerationFromSendersOrMembers" = "2010,2013";
                                  "ExtensionCustomAttribute1" = "2010,2013";
                                  "ExtensionCustomAttribute2" = "2010,2013";
                                  "ExtensionCustomAttribute3" = "2010,2013";
                                  "ExtensionCustomAttribute4" = "2010,2013";
                                  "ExtensionCustomAttribute5" = "2010,2013";
                                  "GrantSendOnBehalfTo" = "2010,2013";
                                  "Languages" = "2010,2013";
                                  "MailTipTranslations" = "2010,2013";
                                  "ModeratedBy" = "2010,2013";
                                  "RejectMessagesFrom" = "2010,2013";
                                  "RejectMessagesFromDLMembers" = "2010,2013";
                                  "RejectMessagesFromSendersOrMembers" = "2010,2013";
                                  "ResourceCustom" = "2010,2013";
                                  "UMDtmfMap" = "2010,2013";
                                  "UserCertificate" = "2010,2013";
                                  "UserSMimeCertificate" = "2010,2013"
                                };

# These parameters are security string type
$securityParmas = @{"Password" = "2010,2013";
                                         "NewPassword" = "2013";
                                         "OldPassword" = "2013";
                                         "RoomMailboxPassword" = "2013"
                                         };

# These parameters are for Microsoft internal use only
$microsoftOnly = @{"AddOnSKUCapability" = "2013";
                              "ArchiveStatus" = "2010,2013";
                              "BypassLiveId" = "2010,2013";
                              "EvictLiveId" = "2010,2013";
                              "MailboxPlan" = "2010,2013";
                              "MailRouting" = "2013";
                              "NetID" = "2010,2013";
                              "OriginalNetID" = "2013";
                              "PstProvider" = "2013";
                              "QueryBaseDNRestrictionEnabled" = "2010,2013";
                              "RemoteAccountPolicy" = "2010,2013";
                              "RemoteRecipientType" = "2010,2013";
                              "RequireSecretQA" = "2010,2013";
                              "SKUAssigned" = "2010,2013";
                              "SKUCapability" = "2010,2013";
                              "SuiteServiceStorage" = "2013";
                              "TenantUpgrade" = "2013";
                              "UsageLocation" = "2010,2013"
                             };

# Define hash table
$myParams = @{};

try {
	if ($exchangeUser) {
		$myParams.Add("Identity", $exchangeUser);
	};

	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters:  $parameters"
		$returnObj = Process-Params -cmd Set-Mailbox -params $parameters -cmdSwitches $switchParams -cmdSecurity $securityParmas -multiValueParams $multiValued -internalParams $microsoftOnly -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};

	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Set-Mailbox $Private:cmdParams"
	# Call Cmdlet with our defined parameters
	# Note: Set-Mailbox does not return any data
	Set-Mailbox @myParams;
	if (-not $?) {
		SNCLog-DebugInfo "`tSet-Mailbox failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
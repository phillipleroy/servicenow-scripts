Param([string]$exchangeServer, [string]$domain, [string]$identity, [string]$domainController,  [string]$recursive, [string]$whatIf)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $identity=$env:SNC_identity;
  $domainController=$env:SNC_domainController;
  $recursive=$env:SNC_recursive;
  $whatIf=$env:SNC_whatIf;
};

SNCLog-ParameterInfo @("Running Exchange-RemoveAddressList", $exchangeServer, $domain, $identity, $domainController, $recursive, $whatIf)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Define hash table
$myParams = @{};

try {
	if ($identity) {
		$myParams.Add("Identity", $identity);
	};
	if ($domainController) {
		$myParams.Add("DomainController", $domainController);
	};
	if ($recursive -ieq "True") {
		$myParams.Add("Recursive", [System.Convert]::ToBoolean($recursive));
	};
	if ($whatIf -ieq "True") {
		$myParams.Add("WhatIf", [System.Convert]::ToBoolean($whatIf));
	};
	
	# Call Cmdlet with our defined parameters
	# e.g.: Remove-AddressList -identity $name;
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Remove-AddressList $Private:cmdParams"
	Remove-AddressList @myParams -Confirm:$False | ConvertTo-XML -As Stream -Depth 4 -NoTypeInformation;
	if (-not $?) {
		SNCLog-DebugInfo "`tRemove-AddressList failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
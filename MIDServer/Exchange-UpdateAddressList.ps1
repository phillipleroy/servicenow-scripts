Param([string]$exchangeServer, [string]$domain, [string]$identity, [string]$domainController, [string]$whatIf)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $identity=$env:SNC_identity;
  $domainController=$env:SNC_domainController;
  $whatIf=$env:SNC_whatIf;
};

SNCLog-ParameterInfo @("Running Exchange-UpdateAddressList", $exchangeServer, $domain, $identity, $domainController, $whatIf)

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
	if ($whatIf -ieq "True") {
		$value = [System.Convert]::ToBoolean($whatIf);
		$myParams.Add("WhatIf", $value);
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Update-AddressList -identity $name;
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Update-AddressList $Private:cmdParams"
	Update-AddressList @myParams -Confirm:$False;
	if (-not $?) {
		SNCLog-DebugInfo "`tUpdate-AddressList failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
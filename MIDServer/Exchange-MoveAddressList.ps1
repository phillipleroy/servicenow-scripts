Param([string]$exchangeServer, [string]$domain, [string]$identity,  [string]$target,  [string]$domainController,  [string]$whatIf)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $identity=$env:SNC_identity;
  $target=$env:SNC_target;
  $domainController=$env:SNC_domainController;
  $whatIf=$env:SNC_whatIf;
};

SNCLog-ParameterInfo @("Running Exchange-MoveAddressList", $exchangeServer, $domain, $identity, $target, $domainController, $whatIf)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Define hash table
$myParams = @{};

try {
	if ($identity) {
		$myParams.Add("Identity", $identity);
	};
	if ($target) {
		$myParams.Add("Target", $target);
	};
	if ($domainController) {
		$myParams.Add("DomainController", $domainController);
	};
	if ($whatIf -ieq "True") {
		$value = [System.Convert]::ToBoolean($whatIf);
		$myParams.Add("WhatIf", $value);
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Move-AddressList -identity $name;
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Move-AddressList $Private:cmdParams"
	Move-AddressList @myParams -Confirm:$False;	
	if (-not $?) {
		SNCLog-DebugInfo "`tMove-AddressList failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
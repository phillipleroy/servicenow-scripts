Param([string]$exchangeServer, [string]$domain, [string]$container,  [string]$domainController,  [string]$identity,  [string]$organization,  [string]$searchText)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $container=$env:SNC_container;
  $domainController=$env:SNC_domainController;
  $identity=$env:SNC_identity;
  $organization=$env:SNC_organization
  $searchText=$env:SNC_searchText;
};

SNCLog-ParameterInfo @("Running Exchange-GetAddressList", $exchangeServer, $domain, $container, $domainController, $identity, $organization, $searchText)

# Import Exchange module
Import-Module "$executingScriptDirectory\Exchange"

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session;

# Define hash table
$myParams = @{};

try {
	if ($container) {
		$myParams.Add("Container", $container);
	};
	if ($domainController) {
		$myParams.Add("DomainController", $domainController);
	};
	if ($identity) {
		$myParams.Add("Identity", $identity);
	};
	if ($organization) {
		$myParams.Add("Organization", $organization);
	};
	if ($searchText) {
		$myParams.Add("SearchText", $searchText);
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Get-AddressList -Identity $name;

	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Update-AddressList $Private:cmdParams"
	Get-AddressList @myParams | ConvertTo-XML -As String -Depth 4 -NoTypeInformation;
	if (-not $?) {
		SNCLog-DebugInfo "`tGet-AddressList failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
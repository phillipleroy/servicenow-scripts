Param([string]$exchangeServer, [string]$domain, [string]$identity, [string]$parameters)

# Import Exchange module
Import-Module -DisableNameChecking "$executingScriptDirectory\Exchange";

# Copy the environment variables to their parameters
if (test-path env:\SNC_exchangeServer) {
  $exchangeServer=$env:SNC_exchangeServer;
  $domain=$env:SNC_domain;
  $identity=$env:SNC_identity;
  $parameters=$env:SNC_parameters;
};

SNCLog-ParameterInfo @("Running Exchange-SetAddressList", $exchangeServer, $domain, $identity, $parameters)

$session = Create-PSSession -exchangeServerName $exchangeServer -credential $cred;
Import-PSSession $session -DisableNameChecking

# Set-AddressList switch parameters
# This parameters do NOT require a value...
$switchParams = @{"Confirm" = "2010,2013";
                              "ForceUpgrade" = "2010,2013";
                              "WhatIf" = "2010,2013"
                             };

# MultiValued parameters
$multiValued = @{"ConditionalCompany" = "2010,2013";
                                  "ConditionalCustomAttribute1" = "2010,2013";
                                  "ConditionalCustomAttribute2" = "2010,2013";
                                  "ConditionalCustomAttribute3" = "2010,2013";
                                  "ConditionalCustomAttribute4" = "2010,2013";
                                  "ConditionalCustomAttribute5" = "2010,2013";
                                  "ConditionalCustomAttribute6" = "2010,2013";
                                  "ConditionalCustomAttribute7" = "2010,2013";
                                  "ConditionalCustomAttribute8" = "2010,2013";
                                  "ConditionalCustomAttribute9" = "2010,2013";
                                  "ConditionalCustomAttribute10" = "2010,2013";
                                  "ConditionalCustomAttribute11" = "2010,2013";
                                  "ConditionalCustomAttribute12" = "2010,2013";
                                  "ConditionalCustomAttribute13" = "2010,2013";
                                  "ConditionalCustomAttribute14" = "2010,2013";
                                  "ConditionalCustomAttribute15" = "2010,2013";
                                  "ConditionalDepartment" = "2010,2013";
                                  "ConditionalStateOrProvince" = "2010,2013"
                                };

# These parameters are for Microsoft internal use only
$microsoftOnly = @{
                           };

# Define hash table
$myParams = @{};

try {
	if ($identity) {
		$myParams.Add("Identity", $identity);
	};

	if ($parameters) {
		SNCLog-DebugInfo "`tProcessing parameters:  $parameters"
		$returnObj = Process-Params -cmd Set-AddressList -params $parameters -cmdSwitches $switchParams -internalParams $microsoftOnly -multiValueParams $multiValued -inputParams $myParams;
		# retrieve the returned data
		$myParams = $returnObj;
	};

	# Call Cmdlet with our defined parameters
	# e.g.: Set-AddressList -Identity $name;
	$Private:cmdParams = SNCGet-CmdParams $myParams
	SNCLog-DebugInfo "`tInvoking Set-AddressList $Private:cmdParams"
	Set-AddressList @myParams | ConvertTo-XML -As Stream -Depth 4 -NoTypeInformation;
	if (-not $?) {
		SNCLog-DebugInfo "`tSet-AddressList failed, $error"
	}
} finally {
	# Disconnect the session
	Remove-PSSession $session;
}
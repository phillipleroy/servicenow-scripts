<# 
 .Synopsis
 Exchange Module

 .Description
  Contains common PowerShell functions for Exchange support

 .Author
  SERVICE-NOW\arturo.ma

 Requires -Version 2.0
#>

<# 
 .Synopsis
  Create PowerShell session.

 .Description
  Returns the created PowerShell session object to be used.

 .Parameter exchangeServerName
  The hostname of the Exchange server.

 .Parameter credential
  The credential object used to access the server.

 .Example
   # Create a powershell session.
   Create-PSSession -exchangeServerName $theServer -credential $userCredential;

 Requires -Version 2.0
#>
function Create-PSSession {
	param(
		[Parameter(Mandatory=$true)] [string]$exchangeServerName,
		[Parameter(Mandatory=$true)] $credential
	);

	$uri = "http://" + $exchangeServerName + "/powershell";
	$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $uri -Credential $credential;

	# Return the created session
	$session;
}

<# 
 .Synopsis
  Converts the input string into an array of tokens broken up at the indicated delimiter

 .Description
  Returns an array of tokens.

 .Parameter theString
  The string to parse into tokens.

 .Example
   # Parse the "+(first.name@company.com, xxx@company.com)".
   Process-Set -theString;

 Requires -Version 2.0
#>
function Process-Set {
	param([Parameter(Mandatory=$true)] [string]$theString,
		[Parameter(Mandatory=$true)] [string]$tokenDelimiter,
		[Parameter(Mandatory=$false)] [bool]$includeDelimiter);

	$tokens = @();
	$theString = $theString.trim();

	if ($theString -match "(^\-[\s]*\()") {
		if ($includeDelimiter) {
			$tokens += "-(";
		}
		$theString = $theString.Substring(1).trim();		# Remove the - char
		if ($theString.StartsWith("(")) {
			$theString = $theString.Substring(1).trim();	# Remove the ( char
		}
	} elseif ($theString -match "(^\+[\s]*\()") {
		if ($includeDelimiter) {
			$tokens += "+(";
		}
		$theString = $theString.Substring(1).trim();		# Remove the + char
		if ($theString.StartsWith("(")) {
			$theString = $theString.Substring(1).trim();	# Remove the ( char
		}
	} elseif ($theString  -match "(^\()") {
		if ($includeDelimiter) {
			$tokens += "(";
		}
		$theString = $theString.Substring(1).trim();		# Remove the ( char
	}

	if ($theString -match "(\)$)") {
		$theString = $theString -replace ".$";			# Remove the ) char (last char)
	}

	$delimitedTokens += $theString.Split($tokenDelimiter);
	# Cycle through the tokens to trim all the blank spaces from the token
	foreach ($token in $delimitedTokens) {
		$tokens += $token.trim();
	}
	if ($includeDelimiter) {
		# Add enclosing ")"
		$tokens += ")";
	}

	# Return all the tokens
	$tokens;
}

function Process-NestedTokens {
	param([Parameter(Mandatory=$true)] [string]$theString,
		[Parameter(Mandatory=$true)] [string]$setDelimiter,
		[Parameter(Mandatory=$true)] [string]$tokenDelimiter);
	$tokens = @();
	$theString = $theString.trim();

	if ($theString -match "(^\(|^\+|^\-[\s]*)") {
		$sets = $theString.Split($setDelimiter);
		foreach ($set in $sets) {
			$setTokens = @();
			$set = $set.trim();
			$setTokens = Process-Set -theString $set -tokenDelimiter $tokenDelimiter -includeDelimiter $true;
			$tokens += $setTokens;
		}
	}

	# Return the tokens
	$tokens;
}

function ConvertTo-Tokens {
	param([Parameter(Mandatory=$true)] [string]$theString,
	[Parameter(Mandatory=$true)] [string]$delimiter);

	[int] $strLen = $theString.Length;

	# Clean up the string, eg. -(''+5'', ''+6'');+(''+7'', ''+8''),  after cleanup we have  -('+5', '+6');+('+7', '+8')
	$theString= $theString.Replace("''", "'").trim();
	$strLen = $theString.Length;

	$tokens = $theString.Split("[']");
	[int] $curr = 0;
	[bool]$matched = $tokens[0] -match "[^\']*";

	foreach ($token in $tokens) {
		$token = $token.trim();
		if (-not $matched)  {
			$tokens[$curr] = $tokens[$curr] + " " + $token.trim();
		}

		if ($tokens[$curr] -match "(\'[^\']*\'|[^\']*)") {
			$matched = $true;
		} else {
			$matched = $false;
		}

		if ($tokens[$curr] -match "\'[^\']*\'") {
			$tokens[$curr] = $tokens[$curr].Substring(1, $tokens[$curr].length - 1).trim();
		}

		if ($tokens[$curr].length -ne 0) {
			$curr++;
		}

		if ($token.Equals($theString)) {
			$newTokens = Process-NestedTokens -theString $token.trim() -setDelimiter ";" -tokenDelimiter ",";
			$tokens += $newTokens;
		}
	}

	# Return the tokens
	$tokens;
};

<# 
 .Synopsis
  Populates a hash table with valid parameters from the user input parameters ($parameters)
  and a concatenated string with valid switch parameter values (Switch parameters are parameters
  that do not require a value).

 .Description
  Returns the created PowerShell session object to be used.

 .Parameter parameters
 The user entered parameters

 .Parameter cmdSwitches
  The hash table containing the Cmdlet switch parameters.

 .Parameter internalParams
 The hash table containing the Cmdlet parameters that are for Microsoft internal use

 .Parameter inputHash
 The hash table containing the user entered parameters

 .Example:
   Process-Params -cmd $cmd -params $parameters -cmdSwitches $switchParams -internalParams $microsoftOnly -multiValueParams $multiValued -inputParams $myParams

  Requires -Version 2.0
#>
function Process-Params {
	param(
		[Parameter(Mandatory=$true)] $cmd,
		[Parameter(Mandatory=$true)] $params,
		[Parameter(Mandatory=$true)] [Hashtable]$cmdSwitches,
		[Parameter(Mandatory=$true)] [Hashtable]$internalParams,
		[Parameter(Mandatory=$false)] [Hashtable]$multiValueParams,
		[Parameter(Mandatory=$false)] [Hashtable]$cmdSecurity,
		[Parameter(Mandatory=$true)] [Hashtable]$inputParams
	);
	[Hashtable]$hashtable = $inputParams;
	$type = $hashtable.GetType();

	if ($params) {
		# NOTE:  Leave following two lines as is, the <CR> is required for code to work...
		$userParams = ConvertFrom-StringData -StringData $params.replace("``n", "
");

		foreach ($property in $userParams.Keys) {

			if ($internalParams.ContainsKey($property)) {
				# Skipping Microsoft internal parameters...
			} elseif ($cmdSwitches.ContainsKey($property)) {
				$value = $userParams[$property];
				if ($value -eq "" -or $value -ieq "True" -or $value -ieq "On" -or $value -eq "1") {
					$value = [System.Convert]::ToBoolean($value);
					$hashtable.Add($property, $value);
				} elseif ($value -ieq "False" -or $value -ieq "Off" -or $value -eq "0") {
					# False value, we don't need to add anything, by default is false/off
				} else {
					Write-Host ">>>>>>>>>>> Invalid value provided for $property switch parameter";
				}
			} elseif ($multiValueParams -and $multiValueParams.ContainsKey($property)) {
				$mValueParams = @();
				$value = $userParams[$property].trim();

				$action = "";
				$queuedAction = "";
				$addValues = @();
				$removeValues = @();
				$replaceValues = @();
				$updateHash = @{};

				$tokens = ConvertTo-Tokens -theString $value -delimiter "'";

				foreach ($token in $tokens) {
					$token = $token.trim();

					if ($token.Length -eq 0 -or $token -match "(^\,)") {
						continue;
					}
					if ($queuedAction -ne "") {
						$action = $queuedAction;
						$queuedAction = "";
					}

					if ($token -match "(^\-[\s]*\()") {
						$action = "Remove";
					} elseif ($token -match "(^\+[\s]*\()") {
						$action = "Add";
					} elseif ($token -match "(^\()") {
						$action = "Replace";
					} elseif ($token -match "(^\)[\s]*\;[\s]*\+[\s]*\()") {
						$queuedAction = "Add";
					} elseif ($token -match "(^\)[\s]*\;[\s]*\-[\s]*\( )") {
						$queuedAction = "Remove";
					} elseif ($token -match "(^\))") {

					} else {
						# Add the token to the appropriate array
						switch ($action) {
							"Add" {
								$addValues += $token.trim();
							};
							"Remove" {
								$removeValues += $token.trim();
							};
							"Replace" {
								$replaceValues += $token.trim();
							};
						}
					}
				}

				if ($cmd.contains("New")) {
					if ($replaceValues.Count -gt 0) {
						$hashtable.Add($property, $replaceValues);
						$replaceValues = @();
					} elseif ($addValues.Count -gt 0) {
						$hashtable.Add($property, $addValues);
						$addValues = @();
					} 
					$removeValues = @();
				} else {
					# value format:  +(val1, val2, val3); -(val4, val5)  or (val1, val2, val3)
					# where "+" indicates to add the values and "-" indicates to remove the values.
					# where values with NO "+" or "-" prefix indicates to replace the values.
					if ($addValues.Count -eq 0 -and $removeValues.Count -eq 0 -and $replaceValues.Count -gt 0) {
						$hashtable.Add($property, $replaceValues);
						$replaceValues = @();
					} else {
						if ($addValues.Count -gt 0) {
							$updateHash.Add("Add", $addValues);
							$addValues = @();
						}
						if ($removeValues.Count -gt 0) {
							$updateHash.Add("Remove", $removeValues);
							$removeValues = @();
						}
						$hashtable.Add($property, $updateHash);
					}
				};
			} elseif ($cmdSecurity -and $cmdSecurity.ContainsKey($property)) {
				# Need to convert value to a secure password
				$value = $userParams[$property];
				$value = ConvertTo-SecureString -String $value -AsPlainText -Force;
				$hashtable.Add($property, $value);
			} else {
				$value = $userParams[$property];
				if ($value -ieq "true" -or $value -ieq "false") {
					$value = [System.Convert]::ToBoolean($value);
				}
				$hashtable.Add($property, $value);
			};
		};
	};

	# Returns a hashtable of valid parameters
	$hashtable;
}
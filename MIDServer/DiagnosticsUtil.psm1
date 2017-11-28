# Global variables
$global:SncLogPrefix = "<SNC_LOG>"
$global:SncLogSuffix = "</SNC_LOG>"

<# 
 .Synopsis
  SNCLog-DebugInfo.

 .Description
 Log message

 .Parameter message
  message to log

 .Example
   # Log a debug message
  SNCLog-DebugInfo -Message "My debug message"

 Requires -Version 2.0
#>
function SNCLog-DebugInfo {
	param(
		[Parameter(Mandatory=$false)] [String]$message = ''
	);

	if ($global:logInfo -eq $False) {
		return
	}

	if ([string]::IsNullOrEmpty($message)) {
		return
	}

	$timeStamp = SNCGet-TimeStamp
	$outputMsg = "{0}{1} {2}{3}" -f $global:SncLogPrefix, $timeStamp, $message, $global:SncLogSuffix
	Write-Host "$outputMsg"
}

<# 
 .Synopsis
  SNCLog-ParameterInfo.

 .Description
 Log script/function parameters

 .Example
  SNCLog-ParameterInfo @("Running Exchange-RemoveMailbox", $exchangeServer, $domain, $parameters)

 Requires -Version 2.0
#>
function SNCLog-ParameterInfo {
	if ($global:logInfo -eq $False) {
		return
	}

	$paramInfo = ""
	foreach ($arg in $args) {
			if ($paramInfo.length -gt 0) {
				$paramInfo += "`t"
			}
			$paramInfo += $arg ;
	}
	SNCLog-DebugInfo "$paramInfo"
}

<# 
 .Synopsis
  SNCObfuscate-Value

 .Description
  Hides the true value by replacing it with '***'

 .Parameter theString
  String to obfuscate

 .Parameter position
  The position to start to obfuscate the string

 .Example
  SNCObfuscate-Value myPassword will return ***
#>
function SNCObfuscate-Value {
	param(
		[Parameter(Mandatory = $false)][String]$theString = '',

		[Parameter(Mandatory=$false)][int]$position = 0
	);

	if ([string]::IsNullOrEmpty($theString)) {
		SNCLog-DebugInfo "Received a null or empty string"
		return "";
	}

	if ($position -gt 0 -and $position -lt $theString.length) {
		$firstPart = $theString.Substring(0, $position)
		$secondPart = $theString.Substring($position)
		$hidden = $secondPart  -replace "\w", '*'
		$hidden = $hidden  -replace "\W", '*'
		$starred =  $firstPart + $hidden
	} else {
		$starred = "***"
	}
	return $starred
}

<# 
 .Synopsis
  SNCGet-TimeMillis

 .Description
  Returns the current Unix epoch time in msecs

 .Example
  SNCGet-TimeMillis
#>
function SNCGet-TimeMillis {

	$currTimeInMs = [long]([double](Get-Date -uFormat %s)*1000)
	return $currTimeInMs
}

function SNCGet-TimeStamp {
	$dateStr = Get-Date -format "yyyy-MM-dd HH:mm:ss"
	return $dateStr
}

function SNCLog-EnvironmentVars {
	if ($global:logInfo -eq $False) {
		return
	}

	$evars = @("Env vars:")
	foreach ($var in ( Get-ChildItem -Path Env:SNC* | Sort-Object Name)) {
		$name = $var.name
		$value = $var.value
		if ($name -NotMatch "SNCEncryptedVars" -and $name -NotMatch "SNC_JVM_ARCH") {
			if ($global:encryptedVars -and $global:encryptedVars.length -gt 0)  {
				if ($global:encryptedVars -Match $name) {
					$value = SNCObfuscate-Value -theString $var.value
				}
			}
			$var = "`$env:" + $name.toString() + ":" + $value.toString()
			$evars += $var
		}
	}
	$separator = "`t"
	$vars = [string]::Join($separator, $evars)
	SNCLog-DebugInfo "$vars`r`n"
}

function SNCLog-Variables {
	if ($global:logInfo -eq $False) {
		return
	}

	$vars = @("`tVars:")
	Compare-Object (Get-Variable) $global:AutomaticVariables -Property Name -PassThru `
		| Where-Object {$_.name -ne "AutomaticVariables"} `
		| ForEach-Object { `
			$name = $_.name;  $val = $_.value; `
			if (-Not($_.name.startswith("SncLog")) -and $_.name -ne "logInfo" -and `
					$_.name -ne "EncryptedVars" -and $_.name -ne "vars") { `
				if ($global:encryptedVars -and $global:encryptedVars.length -gt 0) { `
					if ($global:encryptedVars -like $name) { `
						$val = SNCObfuscate-Value -theString $val `
					} `
				} `
				$vars += "`$$name : $val" `
			} `
		}
	$separator = "`t"
	$theVars = [string]::Join($separator, $vars)
	SNCLog-DebugInfo "$theVars`r`n"
}

<# 
 .Synopsis
  SNCGet-CmdParams

 .Description
  Returns a string representation of the command parameters that are stored
  in the hashtable parameter

 .Parameter paramHTable
  Hashtable which contains all the cmdlet parameters

 .Example
  SNCGet-CmdParams $cmdParameters
#>
function SNCGet-CmdParams {
	param(
		[Parameter(Mandatory=$true)] [hashtable]$paramHTable
	);

	if ($paramHTable -ne $null -and $paramHTable.count -gt 0) {
		$cmdParams = ($paramHTable.GetEnumerator() | % { "-$($_.Key) $($_.Value)" }) -join ' '
		return $cmdParams
	}
	return ""
}

<# 
 .Synopsis
  SNCLog-PowershellVersion

 .Description
  Logs the PowerShell version

 .Example
  SNCLog-PowershellVersion
#>
function SNCLog-PowershellVersion {
	$PsVersion = $PSVersionTable.PSVersion -as "String"
	SNCLog-DebugInfo "PowerShell Version: $PsVersion"
}
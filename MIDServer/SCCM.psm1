<# 
 .Synopsis
 SCCM Module

 .Description
  Contains common PowerShell functions for SCCM support

 .Author
  SERVICE-NOW\jun.zhou

 Requires -Version 3.0
#>

<# 
 .Synopsis
  Create SCCM session.

 .Description
  Returns the created PowerShell session object to be used.

 .Parameter SCCM Server Name
  The hostname of the SCCM server.

 .Parameter credential
  The credential object used to access the server.

 .Example
   # Create a powershell session.
   Create-PSSession -sccmServerName $theServer -credential $userCredential;

 Requires -Version 3.0
#>
function Create-PSSession {
	param(
		[Parameter(Mandatory=$true)] [string]$sccmServerName,
		[Parameter(Mandatory=$true)] $credential
	);

        SNCLog-ParameterInfo @("Running Create-PSSession", $sccmServerName, $credential)

        $session = New-PSSession -ComputerName $sccmServerName -ConfigurationName Microsoft.PowerShell32 -Credential $credential;

	# Return the created session
	$session;
}
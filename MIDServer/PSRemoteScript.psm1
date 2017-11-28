<# 
 .Synopsis
  Create PowerShell session.

 .Description
  Returns the created PowerShell session object to be used.
  Uses env vars to get the hostname and credential

 .Example
   # Create a powershell session.
   Create-PSSession

 Requires -Version 2.0
#>
function Create-PSSession {
	$uri = "http://" + $computer + ":" + $env:SNC_targetPort + "/wsman";
	$session = New-PSSession -ConnectionUri $uri -Credential $cred;

	# Return the created session
	return $session;
}
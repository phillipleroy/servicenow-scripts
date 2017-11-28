<######################
 #    Fetch a DirectoryEntry object.  This is the base object used to manage AD objects.
 #    
 ######################>
function getDirectoryEntryObject {
	param([string]$path, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running getDirectoryEntryObject", $path)
       
	if ($useCred) {
               $Private:user = $credential.UserName
               $Private:password = $credential.GetNetworkCredential().Password
		$hiddenPwd = SNCObfuscate-Value -theString $Private:password
		SNCLog-DebugInfo "`tInvoking New-Object for DirectoryEntry with $path $Private:user $hiddenPwd"
		$directoryEntry = New-Object System.DirectoryServices.DirectoryEntry $path, $Private:user, $Private:password;
	} else {
		SNCLog-DebugInfo "`tInvoking New-Object for DirectoryEntry with $path"
		$directoryEntry = New-Object System.DirectoryServices.DirectoryEntry $path;
	}

	SNCLog-DebugInfo "`t`$directoryEntry:$directoryEntry"
	return $directoryEntry;
}

<######################
 #    Given a name and a type, figure out the sAMAccountName.  For Computers, Microsoft documentation states the computer's sAMAccountName must end with $
 #    
 ######################>
function getSAMAccountName {
	param([string]$name, [string]$type)

	SNCLog-ParameterInfo @("Running getSAMAccountName", $name, $type)

	$sAMAccountName = $name;

	if ($type -eq "Computer") {
		$sAMAccountName = $name + "$";
	}
	return $sAMAccountName;
}

<######################
 #    Apply properties to an AD object
 #    
 ######################>
function applyProperties {
	param([System.DirectoryServices.DirectoryEntry]$object, [string]$properties)

	if (!$properties) {
		$properties = "" ;
	}

	SNCLog-ParameterInfo @("Running applyProperties", $object, $properties)

	$objectData = ConvertFrom-StringData -StringData $properties.replace("``n", "
    ");

	foreach ($property in $objectData.Keys) { 
		$parts = $property.split(":");
		if ($parts.length -eq 2) {
			if ($parts[0] -eq "clear" -and $objectData[$property] -eq "") {
				$object.Properties[$parts[1]].Clear();
			} elseif ($parts[0] -eq "true" -and $objectData[$property] -eq "") {
				$object.Properties[$parts[1]].Value = $true;
			} elseif ($parts[0] -eq "false" -and $objectData[$property] -eq "") {
				$object.Properties[$parts[1]].Value = $false;
			} else {
				# does follow required form for clearing or boolean, so handle it literally
				$object.Properties[$property].Value=$objectData[$property] ;
			}
		} else {
			$object.Properties[$property].Value=$objectData[$property] ;
		}
	};
}

<######################
 #    Fetch an existing AD object by name
 #    
 ######################>
function getADObject {
	param([string]$domainController, [string]$type, [string]$objectName, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running getADObject", $domainController, $type, $objectName)

	$rootEntry = getDirectoryEntryObject -path "LDAP://$domainController" -useCred $useCred -credential $credential

	$search = New-Object System.DirectoryServices.DirectorySearcher $rootEntry;
	$sAMAccountName = getSAMAccountName -name $objectName -type $type
	SNCLog-DebugInfo "`t`$sAMAccountName:$sAMAccountName"
	$search.Filter = "(&(objectClass=$type)(samaccountname=$sAMAccountName))";
	$result = $search.FindOne();

	if ($result -eq $null) {
		SNCLog-DebugInfo "`tUnable to find the AD object"
		throw New-Object System.ArgumentException($search.Filter + " could not be found");
	}

	$object = $result.GetDirectoryEntry();

	if ($object -eq $null) {
		SNCLog-DebugInfo "`tUnable to retrieve the object from AD"
		throw New-Object System.ArgumentException("The object could not be retrieved from: " + $search.Filter);
	}
	return $object;
}

<######################
 #    Create an object in Active Directory.
 #    
 ######################>
function createActiveDirectoryObject {
	param([string]$domainController, [string]$type, [string]$organizationUnit, [string]$objectName, [string]$objectProperties, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running createActiveDirectoryObject", $domainController, $type, $organizationUnit, $objectName, $objectProperties)

	$rootEntry = getDirectoryEntryObject -path "LDAP://$domainController" -useCred $useCred -credential $credential;
	$parentPath = $rootEntry.Path + "/" + $organizationUnit + "," + $rootEntry.Properties["distinguishedName"];
	$parent = getDirectoryEntryObject -path $parentPath -useCred $useCred -credential $credential;

	SNCLog-DebugInfo "`t`$parentPath: $parentPath"
	SNCLog-DebugInfo "`t`$parent: $parent"

	if ($parent -eq $null -or $parent.Children -eq $null) {
		SNCLog-DebugInfo "`tUnable to continue, parent is null or parent has no children"
		throw New-Object System.ArgumentException("$parentPath could not be found");
	}

	$adObject = $parent.Children.Add("CN=$objectName", $type);

	if ($adObject -eq $null) {
		SNCLog-DebugInfo "`tUnable to add new object"
		throw New-Object System.ArgumentException("Unable to add new object (check AD permissions)");
	}

	$adObject.Properties["sAMAccountName"].Value = getSAMAccountName -name $objectName -type $type
	$adObject.Properties["name"].Value = $objectName;

	applyProperties -object $adObject -properties $objectProperties
	$adObject.CommitChanges();    
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to create AD object, $error"
	}
}

<######################
 #    Remove an object from Active Directory
 #    
 ######################>
function removeActiveDirectoryObject {
	param([string]$domainController, [string]$type, [string]$objectName, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running removeActiveDirectoryObject", $domainController, $type, $objectName)

	$object = getADObject -domainController $domainController -type $type -objectName $objectName -useCred $useCred -credential $credential
	$object.DeleteTree();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to delete AD object, $error"
	}
}

<######################
 #    Update an object in Active Directory
 #    
 ######################>
function updateActiveDirectoryObject {
	param([string]$domainController, [string]$type, [string]$objectName, [string]$objectProperties, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running updateActiveDirectoryObject", $domainController, $type, $objectName, $objectProperties)

	$object = getADObject -domainController $domainController -type $type -objectName $objectName -useCred $useCred -credential $credential
	applyProperties -object $object -properties $objectProperties
	$object.CommitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to update AD object, $error"
	}
}

<######################
 #    Query Active Directory for properties
 #    
 ######################>
function queryActiveDirectory {
	param([string]$domainController, [string]$searchFilter, [string]$properties, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running queryActiveDirectory", $domainController, $searchFilter, $properties)

	$rootEntry = getDirectoryEntryObject -path "LDAP://$domainController" -useCred $useCred -credential $credential

	$search= New-Object System.DirectoryServices.DirectorySearcher $rootEntry;
	if ($properties) {
		foreach ($property in [regex]::split($properties, ", ?")) {
			[void]$search.PropertiesToLoad.Add($property); 
		}
	}

	$search.Filter = $searchFilter;
	$searchResults = $search.FindAll();
	$json="";

	foreach ($searchResult in $searchResults) { 
		$json += "{";
		foreach ($propertyName in $searchResult.Properties.PropertyNames) {
			$json += '"' + $propertyName + '":"' + $searchResult.Properties[$propertyName] + '",'
		}
		$json += '"path":"' + $searchResult.Path + '"},'; 
	}

	if ($json.EndsWith(",")) { 
		$json=$json.substring(0, $json.length -1) 
	}

	Write-Host -NoNewline "<![CDATA[[$json]]]>";
}

<######################
 #    Reset Active Directory user password with unlock option
 #    
 ######################>
function resetActiveDirectoryUserPasswordUnlockOption {
	param([string]$domainController, [string]$username, [string]$accountPassword, [boolean]$forceChange, [boolean]$unlock, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	$hiddenPwd = SNCObfuscate-Value -theString $accountPassword
	SNCLog-ParameterInfo @("Running queryActiveDirectory", $domainController, $username, $hiddenPwd, $forceChange, $unlock)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$userObject.invoke("setpassword", $accountPassword);

	if ($forceChange) {
		SNCLog-DebugInfo "`tForce password change"
		$userObject.Properties['pwdLastSet'].Value = 0;
	}

	if ($unlock) {
		SNCLog-DebugInfo "`tUnlock account"
		unlockAccount -domainController $domainController -username $username -useCred $useCred -credential $credential
	}

	$userObject.commitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to reset user password, $error"
	}
}

<######################
 #    Reset Active Directory user password
 #    This version lives to work with the deprecated original version of the activity that enabled the account
 ######################>
function resetActiveDirectoryUserPassword {
	param([string]$domainController, [string]$username, [string]$accountPassword, [boolean]$forceEnable, [boolean]$forceChange, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	$hiddenPwd = SNCObfuscate-Value -theString $accountPassword
	SNCLog-ParameterInfo @("Running resetActiveDirectoryUserPassword", $domainController, $username, $hiddenPwd, $forceEnable, $forceChange)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$userObject.invoke("setpassword", $accountPassword);

	if ($forceEnable) {
		SNCLog-DebugInfo "`tForce enable"
		$userObject.Properties["lockoutTime"].Value = 0;
		$flags = [int]$userObject.Properties["userAccountControl"].Value;
		$userObject.Properties['userAccountControl'].Value = $flags -band (-bnot 2);
	}

	if ($forceChange) {
		SNCLog-DebugInfo "`tForce password change"
		$userObject.Properties['pwdLastSet'].Value = 0;
	}

	$userObject.commitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to reset $username password, $error"
	}
}


<######################
 #    Change Active Directory user password
 #    
 ######################>
function changeActiveDirectoryUserPassword {
	param([string]$domainController, [string]$username, [string]$oldPassword, [string]$newPassword, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	$oldHiddenPwd = SNCObfuscate-Value -theString $oldPassword
	$newHiddenPwd = SNCObfuscate-Value -theString $newPassword
	SNCLog-ParameterInfo @("Running changeActiveDirectoryUserPassword", $domainController, $username, $oldHiddenPwd, $newHiddenPwd)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$userObject.invoke("changepassword", $oldPassword, $newPassword);

	$userObject.commitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to change $username password, $error"
	}
}

<######################
 #    Checks if account is locked
 #    
 ######################>
function isAccountLocked {
	param([string]$domainController, [string]$username, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running isAccountLocked", $domainController, $username)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$locked = $userObject.invokeGet("IsAccountLocked");
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to check if $username account is locked, $error"
	}

	return $locked
}


<######################
 #    Unlock account
 #    
 ######################>
function unlockAccount {
    param([string]$domainController, [string]$username, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running unlockAccount", $domainController, $username)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$isLocked = isAccountLocked -domainController $domainController -username $username -useCred $useCred -credential $credential

	if ($isLocked) {
		$userObject.Properties["lockoutTime"].Value = 0 ;
		$userObject.commitChanges();
		if (-not $?) {
			SNCLog-DebugInfo "`tFailed to unlock $username account, $error"
		}
	} else {
		SNCLog-DebugInfo "`t$username account was already unlocked"
	}
}

<######################
 #    Enable AD user account
 #    
 ######################>
function enableADUserAccount {
	param([string]$domainController, [string]$username, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running enableADUserAccount", $domainController, $username)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$userObject.Properties["lockoutTime"].Value = 0;
	$userObject.Properties['userAccountControl'].Value = 512;
	$userObject.commitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to enable $username account, $error"
	}
}

<######################
 #    Disable AD user account
 #    
 ######################>
function disableADUserAccount {
	param([string]$domainController, [string]$username, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running disableADUserAccount", $domainController, $username)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$userObject.Properties['userAccountControl'].Value = 514;
	$userObject.commitChanges();
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to disable $username account, $error"
	}
}

######################
 #  Add AD user account to Group
 #
 ######################>
function addADUserAccountToGroup {
	param([string]$domainController, [string]$username, [string]$groupname, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running addADUserAccountToGroup", $domainController, $username, $groupname)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$groupObject = getADObject -domainController $domainController -type "Group" -objectName $groupname -useCred $useCred -credential $credential

	$groupObject.add("LDAP://"+$userObject.distinguishedName);
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to add $username account to $groupname group, $error"
	}
}

###################################
 #  Remove AD user account from Group
 ###################################>
function removeADUserAccountFromGroup {
	param([string]$domainController, [string]$username, [string]$groupname, [boolean]$useCred, [System.Management.Automation.PSCredential]$credential)

	SNCLog-ParameterInfo @("Running removeADUserAccountFromGroup", $domainController, $username, $groupname)

	$userObject = getADObject -domainController $domainController -type "User" -objectName $username -useCred $useCred -credential $credential
	$groupObject = getADObject -domainController $domainController -type "Group" -objectName $groupname -useCred $useCred -credential $credential

	$groupObject.remove("LDAP://"+$userObject.distinguishedName);
	if (-not $?) {
		SNCLog-DebugInfo "`tFailed to remove $username account from $groupname group, $error"
	}
}
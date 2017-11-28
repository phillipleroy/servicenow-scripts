$fetchListType = [system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, system.collections.generic.list[string]]]];
$fetchedWMIEntriesType = [system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, system.collections.generic.list[system.collections.generic.dictionary[string, object]]]]];
$fetchedRegistryEntriesType = [system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, string]]]];

$wmiEntriesToFetch = $null
$fetchedWMIEntries = $null
$registryEntriesToFetch = $null
$fetchedRegistryEntries = $null
[System.Xml.XmlDocument]$xmlDocument = $null;
[System.Xml.XmlElement]$xmlResult = $null;

$registryHives = @{"HKEY_CLASSES_ROOT" = 0x80000000; "HKEY_CURRENT_USER" = 0x80000001; "HKEY_LOCAL_MACHINE" = 2147483650; "HKEY_USERS" = 0x80000003; "HKEY_CURRENT_CONFIG" = 0x80000005; "HKEY_DYN_DATA" = 0x80000006}

#####
# Add the given path to the fetch entries.  The paths may take one of two forms, either:
#     HKEY_<registry key path>
# or
#     [<namespace>\]<class>.property
# The first form fetches a registry key value; the second a WMI class property.
#####
function addFetch {
    param([string]$entry)
       
    $parser = [regex]"^(HKCR|HKCU|HKLM|HKU|HKEY_CLASSES_ROOT|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE|HKEY_USERS)[\\\/].*$";
    $parts = $parser.match($entry);

    if ($parts.Success) {
        addRegistryFetch($entry);
    } else {
        addWMIFetch($entry);
    }
}

#####
# Adds WMI fetch entries with a path of the following form: 
#     [<namespace>\]<class>.property
# If the optional namespace is missing, the default (root\cimv2) is used.  All namespaces MUST begin with "root\".
# 
# path: the path to be fetched, in the form specified above.
#####
function addWMIFetch {
    param([string]$entry)

    if (!$script:wmiEntriesToFetch) {
        # Dictionary for namespace and collection of tables which is dictionary for table name and list of fields
        $script:wmiEntriesToFetch = new-object $fetchListType;
    }
       
    $namespace = "root\cimv2";
    $tableName = "";
    $fieldName = "";
    $parser = [regex]"^(?:(root\\(?:.*))\\)?([^\\]*)[\.\\\/](.*)$";
    $parts = $parser.match($entry);

    if (!$parts.Success) {
        return;
    }
       
    if ($parts.Groups[1].Value.Length -gt 0) {
        $namespace = $parts.Groups[1].Value;
    }
   
    $tableName = [string]$parts.Groups[2].Value;
    $tableName = $tableName.Trim();
    $fieldName = [string]$parts.Groups[3].Value;
    $fieldName = $fieldName.Trim();
       
    if (!$script:wmiEntriesToFetch.ContainsKey($namespace)) {
        [system.collections.generic.dictionary[string, system.collections.generic.list[string]]]$ns = 
            new-object "system.collections.generic.dictionary[string, system.collections.generic.list[string]]";
        $script:wmiEntriesToFetch.Add($namespace, $ns);
    }
    
    if (!$script:wmiEntriesToFetch[$namespace].ContainsKey($tableName)) {
        [system.collections.generic.list[string]]$fields = new-object "system.collections.generic.list[string]";
        $script:wmiEntriesToFetch[$namespace].Add($tableName, $fields);
    } 

    $script:wmiEntriesToFetch[$namespace][$tableName].Add($fieldName);    
}

function fetch {
	param([string]$computer, [System.Management.Automation.PSCredential]$cred)

    $script:xmlDocument = createXmlDocument;
    $script:xmlResult = createElement -xmlDocument $script:xmlDocument -name "wmi"
    appendChild -parent $script:xmlDocument -child $script:xmlResult
    fetchWMI -computer $computer -cred $cred
    fetchRegistry -computer $computer -cred $cred
    outputFetchedItems
}

function fetchWMI {
	param([string]$computer, [System.Management.Automation.PSCredential]$cred)

    if (!$script:wmiEntriesToFetch) {
        return;
    }
        
    if (!$script:fetchedWMIEntries) {
        $script:fetchedWMIEntries = new-object $fetchedWMIEntriesType;
    }
    
    foreach ($namespace in $script:wmiEntriesToFetch.Keys) {
        [system.collections.generic.dictionary[string, system.collections.generic.list[system.collections.generic.dictionary[string, object]]]]$ns = 
            new-object "system.collections.generic.dictionary[string, system.collections.generic.list[system.collections.generic.dictionary[string, object]]]";
        $script:fetchedWMIEntries.Add($namespace, $ns);
    
        foreach ($table in $script:wmiEntriesToFetch[$namespace].Keys) {
            [system.collections.generic.list[system.collections.generic.dictionary[string, object]]]$fetchedTableList = 
                new-object "system.collections.generic.list[system.collections.generic.dictionary[string, object]]";
            $script:fetchedWMIEntries[$namespace].Add($table, $fetchedTableList);

            try {
                if ($cred) {
                    $wmiClass = gwmi -namespace $namespace -class $table -computer $computer -credential $cred -impersonation impersonate -authentication packetprivacy  -EA "Stop"
                } else {
                    $wmiClass = gwmi -namespace $namespace -class $table -computer $computer -impersonation impersonate -authentication packetprivacy -EA "Stop"                    
                }
                
                if (!$wmiClass) {
                    continue;
                }
            
                if ($wmiClass -is [array]) {
                    foreach ($obj in $wmiClass) {
                        [system.collections.generic.dictionary[string, object]]$fetchedTable = new-object "system.collections.generic.dictionary[string, object]";
                        foreach ($entry in $script:wmiEntriesToFetch[$namespace][$table]) {
                            $value = $obj[$entry];
                            if ($entry.equals("CommandLine") -and $value -and $value.indexOf("-password") -gt -1) {
                                $value = "*** Command contains password - removed ***";
                            }
                            $fetchedTable.Add($entry, $value);
                        }
                        $script:fetchedWMIEntries[$namespace][$table].Add($fetchedTable);                        
                    }
                } else {
                    [system.collections.generic.dictionary[string, object]]$fetchedTable = new-object "system.collections.generic.dictionary[string, object]";
                    foreach ($entry in $script:wmiEntriesToFetch[$namespace][$table]) {
                        $fetchedTable.Add($entry, $wmiClass[$entry]);
                    }
                    $script:fetchedWMIEntries[$namespace][$table].Add($fetchedTable);
                }
            } catch [System.UnauthorizedAccessException] {
                continue;
            } catch [System.Exception] {
                # 0x800706D9 is an endpoint mapper exception we'll skip because it is most likely from requesting cluster info from 
                # a machine that is not part of a cluster
                if ($_.Exception -is [System.Runtime.InteropServices.COMException] -and $_.Exception.ErrorCode -eq 0x800706D9) {
                    continue;
                }

                # since we are targeting namespaces and classes that may not always exist, we shouldn't throw a warning
                if ($_.Exception.Message -like "Invalid Namespace*" -or $_.Exception.Message -like "Invalid Class*") {
                    continue;
                }

                addWarning($_.Exception.Message);
            }
        }
    }
}

function outputFetchedItems {
    outputFetchedWMIItems
    outputFetchedRegistryItems
    $outputStr = getXmlString($script:xmlDocument)
    write-host $outputStr
}

function outputFetchedWMIItems {
    if ($script:fetchedWMIEntries) {
        foreach ($namespace in $script:fetchedWMIEntries.Keys) {
            foreach ($table in $script:fetchedWMIEntries[$namespace].Keys) {
                $tableObj = $script:fetchedWMIEntries[$namespace][$table];
                if ($tableObj -and $tableObj.Count -gt 0) {
                    foreach ($listEntry in $script:fetchedWMIEntries[$namespace][$table]) {
                        $tableElement = createElement -xmlDocument $script:xmlDocument -name $table
                        appendChild -parent $script:xmlResult -child $tableElement
                        foreach ($entry in $listEntry.Keys) {
                            $value = $listEntry[$entry]
                            
                            if ($value -ne $null) {
                                # handle SecureBinding and ServerBinding fields from IIsWebServerSettting class
                                if ($value -is [System.Management.ManagementBaseObject]) {
                                    $value = getManagementBaseObjectString -srcObject $value;
                                } elseif ($value -is [System.Management.ManagementBaseObject[]]) {
                                   if ($value.count -eq 0) {
                                      $value = "";
                                   } else {
                                      $newValue = "";
                                      foreach ($element in $value) {
                                         $string = getManagementBaseObjectString -srcObject $element;
                                         $newValue = $newValue + "," + $string;
                                      }
                                      # remove leading comma and save
                                      $value = $newValue.SubString(1);
                                   }
                                } elseif ($value -is [Array]) {
                                    $value = getArrayString -srcArray $value;
                                } else {
                                    $value = $value.ToString();
                                }
                            } else {
                                $value = "";
                            }
                                
                            $valueElement = createElement -xmlDocument $script:xmlDocument -name $entry -value $value
                            appendChild -parent $tableElement -child $valueElement
                        }
                    }
                }
            }
        }
    }
}

function nextXmlNode {
    param([System.Xml.XmlNode]$currentElement, [string]$name)
    
    $previousElement = $currentElement;
    $currentElement = getChildWithNameAndAttribute -xmlNode $currentElement -name "entry" -attributeName "key" -attributeValue $name
    if (!$currentElement) {
        $newElement = createElementWithAttribute -xmlDocument $script:xmlDocument -name "entry" -attributeName "key" -attributeValue $name
        appendChild -parent $previousElement -child $newElement
        $currentElement = $newElement;       
    }
    
    return $currentElement;
}

function getManagementBaseObjectString {
    param([System.Management.ManagementBaseObject]$srcObject)
    
    $props = @{};
    foreach ($property in $srcObject.Properties) {
        $value = $srcObject.GetPropertyValue($property.Name);
        if ($value -eq $null) {
            continue;
        }

        if ($value -is [array]) {
            $value = getArrayString -srcArray $value
        }

        if ($value.ToString().Length -gt 0) {
            $props.Add($property.Name, $value);
        }
    }
    
    $outputStr = getHashtableString -srcHashtable $props;
    return $outputStr;
}

function getHashtableString {
    param([HashTable]$srcHashtable)
    
    if ($srcHashtable.Count -eq 0) {
        return "";
    }
        
    $outputStr = "";
    $index = 0;
    foreach($key in $srcHashtable.Keys) {
        if ($index -ne 0) {
            $outputStr += ",";
        }
        
        $outputStr += $key + "=" + $srcHashtable[$key];
        $index++;
    }
    
    return $outputStr;
}

function getArrayString {
    param([array]$srcArray)

    return [string]::Join(",", $srcArray);
}

function addWarning {
    param([string]$warningStr)
    
    $warningElement = createElement -xmlDocument $script:xmlDocument -name 'Warning' -value $warningStr
    appendChild -parent $script:xmlResult -child $warningElement
}


#################################
# REGISTRY FUNCTIONS
#################################
function addRegistryFetch {
    param([string]$entry)

    if (!$script:registryEntriesToFetch) {
        $script:registryEntriesToFetch = new-object 'system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, system.collections.generic.list[string]]]';
    }
    
    $parser = [regex]"^(HKCR|HKCU|HKLM|HKU|HKEY_CLASSES_ROOT|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE|HKEY_USERS)[\\\/](.*)[\\\/](.*)$";
    $parts = $parser.match($entry);

    if (!$parts.Success) {
        return;
    }
    
    $hive = getHiveString($parts.Groups[1].Value); 
    
    if (!$script:registryEntriesToFetch.ContainsKey($hive)) {
        $registryKeys = new-object 'system.collections.generic.dictionary[string, system.collections.generic.list[string]]';
        $script:registryEntriesToFetch.Add($hive, $registryKeys);
    }
    
    if (!$script:registryEntriesToFetch[$hive].ContainsKey($parts.Groups[2].Value)) {
        $registryValues = new-object 'system.collections.generic.list[string]';
        $script:registryEntriesToFetch[$hive].Add($parts.Groups[2].Value, $registryValues);
    }

    $script:registryEntriesToFetch[$hive][$parts.Groups[2].Value].Add($parts.Groups[3].Value);
}

function getHiveString() {
    param([string]$hive)
    
    $hiveStr = $null;
    
    if ($parts.Groups[1].Value -eq "HKCR" -or $parts.Groups[1].Value -eq "HKEY_CLASSES_ROOT") {
        $hiveStr = "HKEY_CLASSES_ROOT";
    }

    if ($parts.Groups[1].Value -eq "HKCU" -or $parts.Groups[1].Value -eq "HKEY_CURRENT_USER") {
        $hiveStr = "HKEY_CURRENT_USER";
    }
    
    if ($parts.Groups[1].Value -eq "HKLM" -or $parts.Groups[1].Value -eq "HKEY_LOCAL_MACHINE") {
        $hiveStr = "HKEY_LOCAL_MACHINE";
    }
    
    if ($parts.Groups[1].Value -eq "HKU" -or $parts.Groups[1].Value -eq "HKEY_USERS") {
        $hiveStr = "HKEY_USERS";
    }
    
    return $hiveStr;
}

# Get the StdRegProv object, and use it to fetch requested registry entries.  Call EnumValues to figure out the type of value - the function to call to fetch the value is based on the type.
function fetchRegistry {
    param([string]$computer, [System.Management.Automation.PSCredential]$cred)
    
    if (!$script:registryEntriesToFetch) {
        return;
    }
        
    if (!$script:fetchedRegistryEntries) {
        $script:fetchedRegistryEntries = new-object $fetchedRegistryEntriesType;
    }
    
    foreach ($hiveStr in $script:registryEntriesToFetch.Keys) {
        $fetchedKeys = new-object "system.collections.generic.dictionary[string, system.collections.generic.dictionary[string, string]]";
        $script:fetchedRegistryEntries.Add($hiveStr, $fetchedKeys);
 
        if ($cred) {
            $reg = gwmi -list -computer $computer -credential $cred -namespace root\default | where-object {$_.Name -eq "StdRegProv"}
        } else {
            $reg = gwmi -list -computer $computer -namespace root\default | where-object {$_.Name -eq "StdRegProv"}        
        }
 
        $hive = $script:registryHives[$hiveStr];
     
        foreach ($key in $script:registryEntriesToFetch[$hiveStr].Keys) {
            $keysToFetch = new-object 'system.collections.generic.list[string]';
            # Replace forward slashes with backslashes - forward slashes cause the opening of the key to fail
            $r = [regex]"/";
            $updatedKey = $r.Replace($key, "\");
            expandRegistryKey -computer $computer -reg $reg -hive $hive -key $updatedkey -expandedKeys $keysToFetch;
       
            foreach ($keyToFetch in $keysToFetch) {
                $fetchedValues = new-object "system.collections.generic.dictionary[string, string]";
                $script:fetchedRegistryEntries[$hiveStr].Add($keyToFetch, $fetchedValues);
                
                $names = $reg.EnumValues($hive, $keyToFetch);
                if ($names.ReturnValue -ne 0) {
                    continue;
                }
                
                $types = new-object "system.collections.generic.dictionary[string, Int32]";
                
                for ($i = 0; $i -lt $names.sNames.Length; $i++) {
                    $types.Add($names.sNames[$i], $names.Types[$i]);
                }

                foreach ($value in $script:registryEntriesToFetch[$hiveStr][$key]) {
                    if ($types[$value] -eq 1) {
                        $fetchedValue = getStringValue -reg $reg -hive $hive -key $keyToFetch -value $value
                    } elseif ($types[$value] -eq 2) {
                        $fetchedValue = getExpandedStringValue -reg $reg -hive $hive -key $keyToFetch -value $value
                    } elseif ($types[$value] -eq 3) {
                        $fetchedValue = getBinaryValue -reg $reg -hive $hive -key $keyToFetch -value $value
                    } elseif ($types[$value] -eq 4) {
                        $fetchedValue = getDWORDValue -reg $reg -hive $hive -key $keyToFetch -value $value
                    } else {
                        $fetchedValue = getMultiStringValue -reg $reg -hive $hive -key $keyToFetch -value $value
                    }

                    $script:fetchedRegistryEntries[$hiveStr][$keyToFetch].Add($value, $fetchedValue);
                }
            }
        }
    }
}

function expandRegistryKey {
    param([string]$computer, $reg, [Int64]$hive, [string]$key, [system.collections.generic.list[string]]$expandedKeys)
          
    $star = $key.indexOf("*");
    if ($star -eq -1) {
        $expandedkeys.Add($key);
        return;
    }
       
    $subkey = $key.SubString(0, $star);
    $openRegKey = $reg.EnumKey($hive, $subkey);

    if ($openRegKey.ReturnValue -ne 0 ) {
        return;
    }
    
    foreach ($expandedKey in $openRegKey.sNames) {
        $newKey = $key.SubString(0, $star) + $expandedKey + $key.SubString($star + 1);

        $s = $newKey.indexOf("*");
        if ($s -ne -1) {
            expandRegistryKey -computer $computer -reg $reg -hive $hive -key $newKey -expandedKeys $expandedKeys;
        } else {
            $expandedkeys.Add($newKey);
        }
    }
}

# Getter functions for each of the registry value types
function getStringValue {
    param($reg, [Int64]$hive, [string]$key, [string]$value)

    $fetchedValue = $reg.GetStringValue($hive, $key, $value);
    if ($fetchedValue.ReturnValue -ne 0) {
        return "";
    }

    return $fetchedValue.GetPropertyValue("sValue");
}

function getExpandedStringValue {
    param($reg, [Int64]$hive, [string]$key, [string]$value)
    
    $fetchedValue = $reg.GetExpandedStringValue($hive, $key, $value);
    if ($fetchedValue.ReturnValue -ne 0) {
        return "";
    }
    return $fetchedValue.GetPropertyValue("sValue");
}

function getMultiStringValue {
    param($reg, [Int64]$hive, [string]$key, [string]$value)
    
    $fetchedValue = $reg.GetMultiStringValue($hive, $key, $value);
    if ($fetchedValue.ReturnValue -ne 0) {
        return "";
    }
    $strs = $fetchedValue.GetPropertyValue("sValue");
    return [string]::Join(",", $strs);
}

function getBinaryValue {
    param($reg, [Int64]$hive, [string]$key, [string]$value)
    
    $fetchedValue = $reg.GetBinaryValue($hive, $key, $value);
    if ($fetchedValue.ReturnValue -ne 0) {
        return "";
    }
    
    $bytes = $fetchedValue.GetPropertyValue("uValue");
    return [string]::Join(",", $bytes);
}

function getDWORDValue {
    param($reg, [Int64]$hive, [string]$key, [string]$value)
    
    $fetchedValue = $reg.GetDWORDValue($hive, $key, $value);
    if ($fetchedValue.ReturnValue -ne 0) {
        return "";
    }
    return $fetchedValue.GetPropertyValue("uValue");
}

function outputFetchedRegistryItems {
    if ($script:fetchedRegistryEntries) {
        foreach ($hive in $script:fetchedRegistryEntries.Keys) {
            foreach ($key in $script:fetchedRegistryEntries[$hive].Keys) {
                $createdKey = $false;
                
                foreach ($property in $script:fetchedRegistryEntries[$hive][$key].Keys) {
                    $value = $script:fetchedRegistryEntries[$hive][$key][$property]
                    if (![string]::IsNullOrEmpty($value)) {
                        if (!$createdKey) {
                            $current = outputRegistryKey -hive $hive -key $key
                            $createdKey = $true;
                        }
                        outputRegistryValue -node $current -name $property -value $value
                    }
                }
            }
        }
    }  
}

function outputRegistryKey {
    param([string]$hive, [string]$key)

    $xmlRegistry = getChild -xmlNode $script:xmlResult -name "Registry"
    if (!$xmlRegistry) {
        $xmlRegistry = createElement -xmlDocument $script:xmlDocument -name "Registry"
        appendChild -parent $script:xmlResult -child $xmlRegistry
    }

    $hiveElement = getChildWithNameAndAttribute -xmlNode $xmlRegistry -name "entry" -attributeName "key" -attributeValue $hive
    if (!$hiveElement) {
        $hiveElement = createElementWithAttribute -xmlDocument $xmlDocument -name "entry" -attributeName "key" -attributeValue $hive
        appendChild -parent $xmlRegistry -child $hiveElement
    }
    
    $currentElement = $hiveElement;
    $lastIndex = 0;
    $index = $key.IndexOf("\");
    while ($index -ne -1) {
        $part = $key.SubString($lastIndex, $index - $lastIndex);
        $currentElement = nextXmlNode -currentElement $currentElement -name $part
        
        $lastIndex = $index + 1;
        $index = $key.IndexOf("\", $index + 1);
    }
    $part = $key.SubString($lastIndex);
    $currentElement = nextXmlNode -currentElement $currentElement -name $part
    
    return $currentElement
}

function outputRegistryValue {
    param([System.Xml.XmlNode]$node, [string]$name, [string]$value)
    if (![string]::IsNullOrEmpty($value)) {
        $keyElement = createElementWithAttribute -xmlDocument $script:xmlDocument -name "entry" -attributeName "key" -attributeValue $name
        appendChild -parent $node -child $keyElement

        $valueElement = createElement -xmlDocument $script:xmlDocument -name "value" -value $value
        appendChild -parent $keyElement -child $valueElement
    }
}
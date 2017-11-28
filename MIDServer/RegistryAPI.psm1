function Get-RegistryDataPS {
    param
    (
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $keys = Get-RegistryKeysPS $RegistryKey
    $values = Get-RegistryValuesPS $RegistryKey

    $data = @()
    
    if (($keys | Group-Object Collection -NoElement).Count -gt 0) {
        $data += $keys
    }

    if (($values | Group-Object Collection -NoElement).Count -gt 0) {
        $data += $values
    }

    if (test-path env:\SNC_remoteShell) {
        return $data | format-list
    }

    return $data
}

function Get-RegistryValuesPS {
    param
    (
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $data = @()

    # lookup table to translate from given to actual reg types
    $lt = @{
        "System.String"                 = "REG_SZ";
        "System.Int32"                  = "REG_DWORD";
        "System.Int64"                  = "REG_QWORD";
        "System.Byte[]"                 = "REG_BINARY";
        "Deserialized.System.String[]"  = "REG_MULTI_SZ";
    }

    #get the properties of the given key
    $key = Get-ItemProperty "Registry::$RegistryKey"
    foreach($pr in $key.psobject.properties) {
        if (!$pr.Name) {
            continue
        }

        if ($pr.Name -eq "PSPath" -Or 
            $pr.Name -eq "PSProvider" -Or 
            $pr.Name -eq "PSParentPath" -Or 
            $pr.Name -eq "PSChildName" -Or 
            $pr.Name -eq "PSComputerName" -Or 
            $pr.Name -eq "PSShowComputerName" -Or 
            $pr.Name -eq "RunspaceId") {
            continue
        }
        
        $rv = 1 | Select-Object -Property Name, Type, Value
        $rv.Name = $pr.Name
        $rv.Type = $lt[$pr.TypeNameOfValue]
        $rv.Value = [String]$pr.Value

        $data += $rv
    }

    return $data
}

function Get-RegistryKeysPS {
    param
    (
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $data = @()

    #get the keys under the given key
    $key = Get-ChildItem "Registry::$RegistryKey"
    forEach ($pr in $key) {
        if (!$pr.Name) {
            continue
        }

        $tmp = 1 | Select-Object -Property Name, Type, Value
        $tmp.Name = $pr.Name.split("\")[-1]
        $tmp.Type = "KEY"

        $data += $tmp
    }

    return $data
}




function Get-RegistryDataWMI {
    param
    (
        [Parameter(Mandatory=$true)] $RegistryHive,
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $wmi = Get-WmiObject -List "StdRegProv" -Namespace "root\default" -ComputerName $computer -Credential $cred

    $keys = Get-RegistryKeysWMI $wmi $RegistryHive $RegistryKey
    $values = Get-RegistryValuesWMI $wmi $RegistryHive $RegistryKey

    $data = @()

    if (($keys | Group-Object Collection -NoElement).Count -gt 0) {
        $data += $keys
    }

    if (($values | Group-Object Collection -NoElement).Count -gt 0) {
        $data += $values
    }

    return $data | format-list
}

function Get-RegistryValuesWMI {
    param
    (
        [Parameter(Mandatory=$true)] $WmiHandle,
        [Parameter(Mandatory=$true)] $RegistryHive,
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $data = @()

    $reg = $WmiHandle.EnumValues($RegistryHive, $RegistryKey)
    for ($i = 0; $i -lt $reg.sNames.Length; $i++) {
        $rv = 1 | Select-Object -Property Name, Type, Value
        $rv.Name = $reg.sNames[$i]
        $rv.Value = Get-RegistryValueWMI $WmiHandle $RegistryHive $RegistryKey $rv.Name (Get-RegistryValueTypeWMI $reg.Types[$i])
        $rv.Type = Get-RegistryValueTypeWMI $reg.Types[$i] $true

        $data += $rv
    }

    return $data
}

function Get-RegistryValueWMI {
    param
    (
        [Parameter(Mandatory=$true)] $WmiHandle,
        [Parameter(Mandatory=$true)] $RegistryHive,
        [Parameter(Mandatory=$true)] $RegistryKey,
        [Parameter(Mandatory=$true)] $ValueName,
        [Parameter(Mandatory=$true)] $Type
    )

    switch ($Type) {
        REG_SZ { $tmp = $WmiHandle.getStringValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty sValue; break; }
        REG_EXPAND_SZ { $tmp = $WmiHandle.getExpandedStringValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty sValue; break; }
        REG_MULTI_SZ { $tmp = $WmiHandle.getMultiStringValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty sValue; break; }
        REG_BINARY { $tmp = $WmiHandle.getBinaryValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty uValue; break; }
        REG_DWORD { $tmp = $WmiHandle.getDwordValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty uValue; break; }
        REG_QWORD { $tmp = $WmiHandle.getQwordValue($RegistryHive, $RegistryKey, $ValueName) | Select-Object -ExpandProperty uValue; break; }
    }

    return [String]$tmp
}

Add-Type -TypeDefinition @"
   public enum RegistryValueType
   {
        REG_SZ = 1,
        REG_EXPAND_SZ = 2,
        REG_BINARY = 3,
        REG_DWORD = 4,
        REG_MULTI_SZ = 7,
        REG_QWORD = 11
   }
"@

function Get-RegistryValueTypeWMI {
    param
    (
        [Parameter(Mandatory=$true)] $IntType,
        [Parameter(Mandatory=$false)] $ResolveToBasicType = $true
    )

    $regType = ""

    foreach ($rvt in [System.Enum]::GetValues([RegistryValueType])) {
        if ($rvt -eq $IntType) {
            $regType = [String]$rvt
            break
        }
    }

    if (!$ResolveToBasicType) {
        return $regType
    }

    $basicRegTypes = @{
        "REG_SZ"        = "REG_SZ";
        "REG_EXPAND_SZ" = "REG_SZ";
        "REG_BINARY"    = "REG_BINARY";
        "REG_DWORD"     = "REG_DWORD";
        "REG_MULTI_SZ"  = "REG_MULTI_SZ";
        "REG_QWORD"     = "REG_QWORD"
    }

    return [String]$basicRegTypes[$regType]
}

function Get-RegistryKeysWMI {
    param
    (
        [Parameter(Mandatory=$true)] $WmiHandle,
        [Parameter(Mandatory=$true)] $RegistryHive,
        [Parameter(Mandatory=$true)] $RegistryKey
    )

    $data = @()

    $reg = $WmiHandle.EnumKey($RegistryHive, $RegistryKey)
    for ($i = 0; $i -lt $reg.sNames.Length; $i++) {
        $rv = 1 | Select-Object -Property Name, Type, Value
        $rv.Name = $reg.sNames[$i]
        $rv.Type = "KEY"

        $data += $rv
    }

    return $data
}
$tmpDriveName = ""
$remoteDriveLetter = "C"

function launchProcess {
    param([string]$computer, [System.Management.Automation.PSCredential]$cred, [string]$command)
    $command = 'cmd /c "' + $command +'"'
    invoke-rexpression $command
}

function handleExit {
    param([int]$exitCode)

    $output = ""

    if ($exitCode -ne 0) {
        $output = "$env:SNC_cmdFail $exitCode"
    } else {
        $output = "$env:SNC_cmdCmpl $exitCode"
    }

    write-host $output
}

function getFileProperties {
    param([string]$path, [string]$method)

    if ($method -eq "wmi") {
        getFilePropertiesWmi $path
    } else {
        getFilePropertiesWinRM $path
    }
}

function getFileContent {
    param([string]$path, [string]$method)

    if ($method -eq "wmi") {
        getFileContentWmi $path
    } else {
        getFileContentWinRM $path
    }
}

function getFileContentWinRM {
    param([string]$path)

    Get-Content "FileSystem::$path"
}

function getFilePropertiesWinRM {
    param([string]$path)

    Get-ItemProperty "FileSystem::$path" | select *
}

function getFileContentWmi {
    param([string]$path)
    $tmpDriveName = [guid]::NewGuid().toString("N")

    $path = convertPathToUnc $path
    mapDrive

    Get-Content "FileSystem::$path"

    removeDrive
}

function getFilePropertiesWmi {
    param([string]$path)
    $tmpDriveName = [guid]::NewGuid().toString("N")

    $path = convertPathToUnc $path
    mapDrive

    Get-ItemProperty "FileSystem::$path" | select *

    removeDrive
}

function convertPathToUnc {
    param([string]$path)

    $pathArr = $path.split(':')
    $remoteDriveLetter = $pathArr[0]
    $tmp = $path -replace ':', '$'

    return '\\' + $computer + '\' + $tmp
}

function mapDrive {
    #New-PSDrive -Name $tmpDriveName -PSProvider FileSystem -Root "\\$computer\$remoteDriveLetter`$" -Scope global >$null

    # this workaround is necessary because net use doesn't know how to handle
    # usernames such as .\<username> for workgroup credentials.
    # use just <username> instead.
    $un = $env:SNC_username
    $unSp = $un.split('\')
    if ($unSp[0] -eq '.') {
        $un = $unSp[1]
    }

    net use \\$computer\$remoteDriveLetter$ $env:SNC_password /user:$un >$null
}

function removeDrive {
    #Remove-PSDrive -Name $tmpDriveName >$null
    net use /delete \\$computer\$remoteDriveLetter$ >$null
}

function getTrustedHostsAuthority {
    $xml = Get-WSManInstance -ResourceURI winrm/config/client | select -expandproperty OuterXml
    $ns = @{cfg="http://schemas.microsoft.com/wbem/wsman/1/config/client"}
    $n = select-xml -XPath '/cfg:Client/cfg:TrustedHosts' -Content $xml -Namespace $ns
    $out = 'GPO'
    if ([string]::isNullOrEmpty($n.node.source)) {
        $out = 'HOST'
    }

    return $out
}

function getTrustedHosts {
    $xml = Get-WSManInstance -ResourceURI winrm/config/client | select -expandproperty OuterXml
    $ns = @{cfg="http://schemas.microsoft.com/wbem/wsman/1/config/client"}
    $n = select-xml -XPath '/cfg:Client/cfg:TrustedHosts' -Content $xml -Namespace $ns

    return $n.node.'#text'
}

function hostInDomain {
    if ((Get-WmiObject win32_computersystem).partofdomain) {
        write-host true
    } else {
        write-host false
    }
}

function testRemoteHostRunningWinRM {
    test-wsman -computer $computer -port $env:SNC_targetPort -authentication none
}

function testRemoteHostConnection {
    $dummyCred = getDummyCredential "TestUser" "TestPassword"
    test-wsman -computer $computer -port $env:SNC_targetPort -credential $dummyCred -authentication default
}
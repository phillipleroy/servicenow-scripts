Param(
    [string]$operation,
    [string]$nmap_root_path,
    [string]$nmap_self_installer,
    [string]$nmap_command,
    [string]$nmap_uninstall_command,
    [System.Version]$nmap_npcap_version,
    [string]$nmap_safe_scripts
)

# PowerShell seems to have a lot of delay in when the installed files are actually accessible.
# These variables control the number of retries and delay while waiting for them.
$retries = 60
$retryDelay = 2;

# Remove the Nmap directory and its contents. 
# In the case that Nmap was installed it uninstalls Nmap first.
Function clean-nmap-folder {
    Write-Host "Checking for existing Nmap installation at $nmap_root_path"
    if (Test-Path -Path $nmap_root_path) {
        Write-Host "...found existing Nmap installation at $nmap_root_path"
        Write-Host "Checking for existing Nmap uninstaller $nmap_uninstall_command"
        if (Test-Path -Path $nmap_uninstall_command) {
            Write-Host "...found existing Nmap uninstaller, executing uninstaller"
            & $nmap_uninstall_command /S > $null 
        }

        delete-nmap-folder

    } else {
        Write-Host "...$nmap_root_path not found"
    }
 }

# Delete the Nmap directory and its contents. 
# In the case that Nmap was installed it uninstalls Nmap first.
Function delete-nmap-folder {
    Write-Host "Deleting Nmap directory $nmap_root_path"
    for ($i=0; $i -le $retries; $i++) {
        try {   
            Remove-Item -Recurse -Force $nmap_root_path
            if ($?) {
                Write-Host "Nmap directory $nmap_root_path deleted"
                return
            }
        } catch {
            Write-Host "Error removing $nmap_root_path, $_"
        }

        Write-Host "Unable to remove $nmap_root_path, waiting $retryDelay seconds..."
        Start-Sleep -s $retryDelay
    }

    Write-Host "Unable to delete $nmap_root_path"
 }

Function install-nmap { 
    Write-Host "Checking free space on $(get-location).Drive.Name"
    $free_size = $($(get-psdrive $(get-location).Drive.Name).Free)/1MB
    if ($free_size -le 10) {
        Write-Error  "Unable to install Nmap: Not enough disk space to install Nmap with $free_size MB remaining"
        clean-nmap-folder
        Exit 4
    }
    Write-Host "...enough disk space to install Nmap"

    $nmap_installer_params = "/S /REGISTERPATH=NO /ZENMAP=NO"
    # Checks if a higher version of Npcap is installed on the machine then adds NPCAP=NO to prevent re-installing Npcap
    $def_version = [System.Version] "0.0"
    if ($nmap_npcap_version -ne $def_version) {
        if (npcap-was-installed) {
             $nmap_installer_params = "$nmap_installer_params  /NPCAP=NO"
         }
     }
    # Install Nmap in the silent mode&
    $installer_cmd = "& `"$nmap_self_installer`" $nmap_installer_params /D=$nmap_root_path"

    Write-Host "Installing Nmap: $installer_cmd"

    Invoke-Expression $installer_cmd
    if (-Not $?) {
        Write-Error "Unable to install Nmap: $Error[0].ToString()"
        clean-nmap-folder
        Exit 4
    }

    # Verify Nmap installation
    $nv = verify-nmap

    # Select safe scripts
    provide-safe-db

    Write-Host "Nmap $nv was installed successfully "
}

#Check if a higher version of npcap was installed on the machine
Function npcap-was-installed {
    $registery_path = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\NpcapInst"
    
    # Verify if Npcap was installed
    if (-Not (Test-Path -Path $registery_path)) {
        return $false
    }
    # Verify if a higher verion of Npcap is available 
    $npcap_version = [System.Version](Get-ItemProperty $registery_path -Name "DisplayVersion")."DisplayVersion"
    if ($npcap_version -ge $nmap_npcap_version) {
        Write-Host "Npcap$nmap_npcap_version is not installed: Npcap$npcap_version was already installed"
        return $true
    }

    return $false

}

Function verify-nmap {
    # Because of directory caching, the Nmap executable may not appear yet so wait for it
    for ($i=0; $i -le $retries; $i++) {
        if (Test-Path "$nmap_command") {
            Write-Host "$nmap_command ready"
            break
        }
        Write-Host "$nmap_command does not exist yet, waiting $retryDelay seconds..."
        Start-Sleep -s $retryDelay
    }

    # Verify Nmap version
    Write-Host "Verifying Nmap installation"
    for ($i=0; $i -le $retries; $i++) {
        $version_info = & "$nmap_command" --version
        if ($?) {
            #Success, return version
            Write-Host $version_info
            return $version_info[1].split()[2]
        }

        Write-Host "Unable to verify Nmap installed version, waiting $retryDelay seconds..."
    }

    # If we got here, it failed after all retries
    Write-Error "Timeout: Unable to verify Nmap installed version"
    clean-nmap-folder
    Exit 4
}


Function provide-safe-db {
    $script_path = $nmap_root_path + "\scripts\*"
    $safe_script_path = $nmap_root_path + "\safeScripts"

    $safe_db = delete-unsafe-scripts $script_path

    $lastStatus = $false 
    for ($i=0; $i -le $retries; $i++) {
        & $nmap_command --script-updatedb > $null
        $lastStatus = $?
        if ($lastStatus) {
            Write-Host  "Nmap safe scripts DB updated"
            break
        }

        Write-Host "Unable to update the script database with safe scripts, waiting $retryDelay seconds..."
        Start-Sleep -s $retryDelay
    }

    if (-Not $lastStatus) {
            Write-Error  "Timeout: Unable to update the script database with safe scripts: $Error[0].ToString()"
            clean-nmap-folder
            Exit 4
    }

    try {
        New-Item -ItemType directory -Path $safe_script_path > $null
    } catch {
        Write-Error  "Unable to create nmap directory under agent directory for this MID Server. $_"
        clean-nmap-folder         
        Exit 4
    }

    Copy-Item -Path "$script_path" -Destination "$safe_script_path"
    Write-Host "Safe scripts compiled to $safe_script_path"
}



Function delete-unsafe-scripts ($db_scripts_path) {
    $safe_script_names = $nmap_safe_scripts.split(", ")
    $scripts = Get-ChildItem -Path "$db_scripts_path" -Filter *.nse

    for ($i=0 ; $i -le $retries; $i++) {
        foreach ($file in $scripts) {
            if (-Not ($safe_script_names -contains $file.Name)) {
                Remove-Item -Path "$file"
            }
        }
        $scripts = Get-ChildItem -Path "$db_scripts_path" -Filter *.nse
        if (unsafe-db $safe_script_names $scripts) {
            Write-Host "Unable to delete all unsafe scripts from database, waiting $retryDelay seconds..."
            Start-Sleep -s $retryDelay
        } else {
            return $true; 
        }
    }
    # If we got here, it failed after all retries
    Write-Error "Timeout: Unable to delete all unsafe scripts"
    clean-nmap-folder
    Exit 4

}

Function unsafe-db ($script_names, $scripts) {
    foreach ($file in $scripts) {
        if (-not ($script_names -contains $file.Name)) {
             return $true
        }
    }
    return $false
}

# Uninstall Nmap in the silent mode and remove the Nmap folder in the agent folder. 
Function uninstall-nmap {
    Write-Host "Checking for existing Nmap installation at $nmap_root_path"
    if (-Not (Test-Path -Path "$nmap_root_path")) {
        Write-Error "Unable to uninstall Nmap. $nmap_root_path does not exist"
        Exit 4
    }

    Write-Host "Checking for existing Nmap uninstaller $nmap_uninstall_command"
    if (-Not (Test-Path -Path "$nmap_uninstall_command")) {
        Write-Error "Unable to uninstall Nmap. $nmap_uninstall_command does not exist"
        Exit 4
    }

    Write-Host "Executing Nmap uninstaller $nmap_uninstall_command"
    & $nmap_uninstall_command /S
    if (-Not $?) {
        Write-Error "Unable to uninstall Nmap: $Error[0].ToString()"
        Exit 4
    }

    delete-nmap-folder
}

switch ($operation) {
    "clean" { clean-nmap-folder }
    "install" { install-nmap }
    "uninstall" { uninstall-nmap }
}
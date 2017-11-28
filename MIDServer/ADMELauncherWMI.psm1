function getConfigurableParm {
   param([string]$variable, [string]$defaultValue)
   $value = [Environment]::GetEnvironmentVariable($variable)
   if (-not $value) {
        $value = $defaultValue;
    }
    return $value;
}

function launchADME {
   # customizable probe parameters
   $targetBaseDir  = getConfigurableParm -variable "SNC_base_dir" -defaultvalue "admin$\temp"
   $samplingInterval = getConfigurableParm -variable "SNC_sampling_interval" -defaultvalue 60
   $rollingWindowSize = 168  #1 week
   $mode = getConfigurableParm -variable "SNC_mode" -defaultvalue "INSTALL"
   $maxTotalSamples = getConfigurableParm -variable "SNC_max_total_samples" -defaultvalue 100
   
   # validate parameters
   if (([convert]::ToInt32($samplingInterval,10)) -lt 5) {
       write-error "Invalid probe parameter: The sampling interval must be at least 5 sec"
       return
   }

   if (($mode -ne "INSTALL") -and ($mode -ne "UNINSTALL")) {
       write-error "Invalid probe parameter: Unrecognized mode for Windows ADME probe: $mode"
       return
   }

   $MAX_TOTAL_SAMPLES_UPPER_LIMIT = 3000
   $mtsNum = [convert]::ToInt32($maxTotalSamples,10)
   if ($mtsNum -lt 0) {
       write-error "Invalid probe parameter: max_total_samples $maxTotalSamples must be greater than 0"
       return
   }

   if ($mtsNum -gt $MAX_TOTAL_SAMPLES_UPPER_LIMIT) {
       write-error "Invalid probe parameter: max_total_samples $maxTotalSamples cannot exceed upper limit $MAX_TOTAL_SAMPLES_UPPER_LIMIT"
       return
   }
   
   # other required parameters
   $sourceScript = ".\scripts\PowerShell\ADMEnhanced\CollectConnectionsAndProcessesInfo.ps1"
   $instanceName = getConfigurableParm -variable "SNC_instance" -defaultvalue "unregistered"
   
   $targetBaseDir = "\\$computer\$targetBaseDir"
   $targetHomeDir = "$targetBaseDir\$instanceName"
   $targetScript = "$targetHomeDir\admeScript.ps1"
   $targetDataPath = "$targetHomeDir\com.service_now.adme"
   $targetDataFile = "$targetDataPath\processesAndConnections.json"
   $firstTime = "false"
   $isLocal = getConfigurableParm -variable "SNC_local" -defaultvalue "false"

   $guid = [System.Guid]::NewGuid()
   
   try {
      $psVersion = [convert]::ToInt32($PSVersionTable.PSVersion.Major, 10)

      if ($psVersion -lt 3) {
          throw "Windows ADME requires PowerShell 3.0"
      }

      # Network drive mapping commands do not like credential usernames that start with ".\".
      # Need to replace local username prefix of ".\" with "WORKGROUP\".
      if ($cred -and $cred.Username.StartsWith(".\")) {
          $credCopy = New-Object -Typename System.Management.Automation.PSCredential -Argumentlist $cred.UserName.Replace(".\", "WORKGROUP\"), $cred.Password
      } else {
          $credCopy = $cred
     }

      # if the target is the local MID host, then credentials are not used
      if ($isLocal -eq "true") {
          New-PSDrive -Name $guid -PSProvider FileSystem -Root $targetBaseDir > $null
      } else {
          New-PSDrive -Name $guid -PSProvider FileSystem -Root $targetBaseDir -Credential $credCopy > $null
      }

      $drive = Get-PSDrive -Name $guid  -ErrorAction SilentlyContinue
      if ($drive -eq $null) {
         throw "Could not map network share: $targetBaseDir."
      }

      if (!(test-path -path $targetHomeDir )){
         if ($mode -eq "UNINSTALL") {
            write-host "Workspace $targetHomeDir does not exist to continue.  Aborting uninstall."
            return;
         }
         New-Item -ItemType directory -Path $targetHomeDir > $null
         $firstTime = "true"
      }

      copy-item $sourceScript $targetScript

      if ($? -ne $true) {
         throw "Could not copy script $sourceScript to target $targetScript"
      }
      
      $output = "{}"
      if ($firstTime -eq "false") {
         #grab the existing data file
         if (test-path $targetDataFile) {
            # check if it is under the payload size limit (default 4MB)
            $maxPayloadSize = getConfigurableParm -variable "SNC_max_result_payload_size" -defaultvalue 4153344
            $actualSize = (get-item $targetDataFile).length
            if ($actualSize -gt $maxPayloadSize) {
               throw "Declining to fetch result due to size limitation. Actual size: $actualSize Max allowed: $maxPayloadSize"
            }
            $output = get-content $targetDataFile
         } else {
            $output =  '{"log": "Data file not yet available"}'
         }
      }
      
      #spawn a new process
      $arguments = '"{0}" {1} {2} {3} "{4}" "{5}" {6}' -f $targetScript, $samplingInterval, $samplingInterval, $rollingWindowSize, $targetHomeDir, $mode, $maxTotalSamples
      $command = 'powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File ' + $arguments
      if ($isLocal -eq "true") {
         $result = invoke-wmimethod win32_process -name create -computer $computer -argumentlist $command
      } else {
         $result = invoke-wmimethod win32_process -name create -computer $computer -credential $credCopy -argumentlist $command
      }

      if ($? -ne $true) {
         throw "Error launching process: $log"
      }

      $dataHeader = '{{"collector_info":{{"workspace": "{0}", "pid": "{1}", "first_time": "{2}"}}' -f $targetHomeDir.ToString().Replace('\','\\').Replace('"','\"'), $result.ProcessId, $firstTime
      if (($firstTime -eq "true") -or ($output -eq "{}")) {
         $output = $dataHeader + "}"
      } elseif ($mode -eq "UNINSTALL") {
         $output =  '{"log": "workspace was cleaned"}'
      } else {
         $output = "$dataHeader, " + $output.trimStart("{")
     }
     write-host $output
   } catch {
      write-error $_.Exception.Message
   } finally {
      #remove the mounted share drive if it exists
      $drive = Get-PSDrive -Name $guid -ErrorAction SilentlyContinue
      if ($drive -ne $null) {
          Remove-PSDrive -Name $guid
      }
   }
}
function getConfigurableParm {
   param([string]$variable, [string]$defaultValue)
   $value = [Environment]::GetEnvironmentVariable($variable)
   if(!$value) {
        $value = $defaultValue;
   }
   return $value;
}

function createDirAndCopyFile {
   $targetDir = $args[0]
   $targetScript = $args[1]
   $contents = $args[2]
   $firstTime = "false";
   if (!(test-path -path $targetDir )){
      New-Item -ItemType directory -Path $targetDir > $null
      $firstTime = "true";
   }
   Set-Content -path $targetScript -value $contents
   return $firstTime
}

function launchProcessWithCommand {
   $command = $args[0]
   invoke-wmimethod win32_process -name create -argumentlist $command
}

function getExistingDataFile {
   $targetDataFile = $args[0]
   $maxPayloadSize = $args[1]
   $output = {}
    
   #grab the existing data file
   if (test-path $targetDataFile) {
      # check if it is under the payload size limit (default 4MB)
      $actualSize = (get-item $targetDataFile).length
      if ($actualSize -gt $maxPayloadSize) {
         throw "Declining to fetch result due to size limitation. Actual size: $actualSize Max allowed: $maxPayloadSize"
      }
      $output = get-content $targetDataFile
   } else {
      $output =  '{"log": "Data file not yet available"}'
   }
   return $output
}

function launchADME {
   $targetBaseDir  = getConfigurableParm -variable "SNC_base_dir" -defaultvalue "admin$\temp"
   $samplingInterval = getConfigurableParm -variable "SNC_sampling_interval" -defaultvalue 60
   $rollingWindowSize = 168   # 1 week
   $mode = getConfigurableParm -variable "SNC_mode" -defaultvalue "INSTALL"
   $maxTotalSamples = getConfigurableParm -variable "SNC_max_total_samples" -defaultvalue 100
   $maxPayloadSize = getConfigurableParm -variable "SNC_max_payload_size" -defaultvalue 4153344

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

   $instanceName = getConfigurableParm -variable "SNC_instance" -defaultvalue "unregistered"
   $targetBaseDir = "\\$computer\$targetBaseDir"
   $targetHomeDir = "$targetBaseDir\$instanceName"
   $targetScript = "$targetHomeDir\admeWinRMScript.ps1"
   $targetDataPath = "$targetHomeDir\com.service_now.adme"
   $targetDataFile = "$targetDataPath\processesAndConnections.json"

   $sourceScript = $MID_HOME + "\scripts\PowerShell\ADMEnhanced\CollectConnectionsAndProcessesInfo.ps1"
   $admeScript  = Get-Content -path $sourceScript

   $arguments = '"{0}" {1} {2} {3} "{4}" "{5}" {6}' -f $targetScript, $samplingInterval, $samplingInterval, $rollingWindowSize, $targetHomeDir, $mode, $maxTotalSamples
   $command = 'powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File ' + $arguments

   $output = "{}"
   if ($isLocal -eq "true") {
      # execute the commands directly (without  a remote session)
      $firstTime = createDirAndCopyFile  $targetHomeDir $targetScript $admeScript
      if ($firstTime -eq "false") {
         $output = getExistingDataFile $targetDataFile $maxPayloadSize
      }
      $result = launchProcessWithCommand $command
   } else {
      # create a session to the target
      $ps = New-PSSession -computer $computer -credential $cred
      #save the script to file
      $firstTime = Invoke-Command -session $ps -scriptblock ${function:createDirAndCopyFile} -argumentlist $targetHomeDir, $targetScript, $admeScript
      if ($firstTime -eq "false") {
         # grab the existing data file
         $output = Invoke-Command -session $ps -scriptblock ${function:getExistingDataFile} -argumentlist $targetDataFile, $maxPayloadSize
      }
      #create a new process with the command
      $result = Invoke-Command -session $ps -scriptblock ${function:launchProcessWithCommand} -argumentlist $command
   }
  
   if ($? -ne $true) {
        throw "Error launching process"
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
}
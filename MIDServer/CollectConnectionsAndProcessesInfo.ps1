[CmdletBinding()]
Param(
    [Parameter(Position=1)]
    [ValidateScript({
    $pollingIntervalAsInt = [Int]$_
       
    If ($pollingIntervalAsInt -ge 5) {
        $True
    }
    Else{
        Throw "SamplingInterval parameter needs to be at least 5 seconds."
    }
    })]
    [Long]$SamplingInterval = 60,
               
    [Parameter(Position=2)]
    [ValidateScript({
    $chunkAggregationIntervalAsInt = [Int]$_
       
    If ($chunkAggregationIntervalAsInt -ge 5) {
       
        If (($chunkAggregationIntervalAsInt % $SamplingInterval) -Eq 0){
            $True
        }
        Else{
            Throw "ChunkAggregationInterval parameter needs to be a multiple of SamplingInterval."
        }
    }
    Else{
        Throw "ChunkAggregationInterval parameter needs to be at least 5 seconds."
    }
    })]
    [Int]$ChunkAggregationInterval = 60,
 
    [Parameter(Position=3)]
    [ValidateScript({
    $rollingWindowSizeAsInt = [Int]$_
   
    If ($rollingWindowSizeAsInt -gt 0){
        $True
    }
    })]
    [Int]$RollingWindowSize = 168,
 
                [Parameter(Position=4)]
    [String]$BaseDir = $null,
   
    [Parameter(Position=5)]
    [String]$Mode = "INSTALL",
   
    [Parameter(Position=6)]
    [ValidateScript({
    $maxTotalSamplesAsInt = [Int]$_
   
    If($maxTotalSamplesAsInt -gt 0){
        $True
    }
    })]
    [Int]$MaxTotalSamples = 100
)
 
    Set-Variable LISTENING_STATE -Value "LISTENING" -Option Constant
    Set-Variable ALL_ADDRESSES -Value "0.0.0.0" -Option Constant
    Set-Variable LOCALHOST -Value "127.0.0.1" -Option Constant
    Set-Variable NETSTAT_TCP_RECORD_PATTERN -Value "\s+TCP" -Option Constant
    Set-Variable LOG_FILE -Value "adme_log.log" -Option Constant
    Set-Variable OUTPUT_FILE -Value "processesAndConnections.json" -Option Constant
    Set-Variable ADME_WORKSPACE_NAME -Value "com.service_now.adme" -Option Constant
   
    $processes = @{}
    $connections = New-Object System.Collections.Generic.List[PSCustomObject]
    $localIPv4Addresses = @()
    $samplesPerChunk = 0
    $currentSampleIndex = 0
    $currentChunkIndex = 0
    $totalSamplesTaken = 0
    $isCurrentChunkWasReset = $False
    $shouldContinueRunning = $False
    $logsBeforeBaseDirIsDetermined = ""
    $logFile = ""
    $outputFile = ""
    $isFirstTime = $True

    Function Log (){
      Param(
        [Parameter(Mandatory=$False, ValueFromPipeline=$True, Position=0)]
        [String]$message
      )
     
      If ($message.length){
        $message = "$([System.DateTime]::Now): $message"
      }
     
      Add-Content $logFile "$message"
    }
 
    Function Get-All-IPv4-Addresses (){
                $ipv4Addresses = @($LOCALHOST)
               
        Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IpEnabled = 'True'" | Select-Object IpAddress `
            | ForEach-Object {
                                $ipv4Addresses += $_.IpAddress -notlike "*:*"
                }
               
                Return $ipv4Addresses
    }
 
    Function Get-Netstat-Output (){
        Return netstat -anop TCP
    }
 
    Function Get-Parameters ($process){
        If (($process.CommandLine -ne $Null) -and ($process.CommandLine -ne '')){
            Return $process.CommandLine.Trim()
        }
               
        Return ''
    }
 
    Function Get-CommandLine($process){
        If (($process.ExecutablePath -ne $Null) -and ($process.ExecutablePath -ne '')){
            Return $process.ExecutablePath.Trim()
        }
               
        Return $process.Name
    }
 
    Function Collect-And-Update-Process-Information{
        Log "Collecting processes data..."
                $wmiObjProcesses = Get-WmiObject Win32_Process | Select-Object CommandLine,ParentProcessId,ProcessId,Name,ExecutablePath,@{N='CreationDate'; E={$_.ConvertToDateTime($_.CreationDate)}} | Where-Object {$_.ProcessId -ne $PID}
        $processIdAsString = ""
 
        ForEach ($wmiObjProcess In $wmiObjProcesses){
            $processIdAsString = $wmiObjProcess.ProcessId.ToString()

            If ($wmiObjProcess.Name -eq "System Idle Process"){
                $wmiObjProcess.ParentProcessId = "99999" + $wmiObjProcess.ParentProcessId
            }
           
            If ($processes.ContainsKey($processIdAsString)){
               $processes.Item($processIdAsString).Counters[$currentChunkIndex]++
            }
            Else{
                Add-Member -InputObject $wmiObjProcess -MemberType NoteProperty -Name Parameters `
                    -Value (Get-Parameters -Process $wmiObjProcess)
                Add-Member -InputObject $wmiObjProcess -MemberType NoteProperty -Name IncomingConnections -Value @{}
                Add-Member -InputObject $wmiObjProcess -MemberType NoteProperty -Name OutgoingConnections -Value @{}
                Add-Member -InputObject $wmiObjProcess -MemberType NoteProperty -Name Counters -Value (@(0) * $RollingWindowSize)
                Add-Member -InputObject $wmiObjProcess -MemberType NoteProperty -Name Count -Value 0
                $wmiObjProcess.CommandLine = Get-CommandLine -Process $wmiObjProcess
                $wmiObjProcess.Counters[$currentChunkIndex]++
                $processes.Add($processIdAsString, $wmiObjProcess)
            }
        }
        Log "Processes data collection finished"
    }
 
    Function Set-Connection-ID ([PSObject]$connection){
                $connection.ConnectionID = $connection.Type +":"+ $connection.PID +":"+ $connection.IP +":"+ $connection.Port
    }
 
    Function Parse-Connection ($netstatConnectionLine){
                $properties = 'Protocol','LocalAddress','LocalPort','RemoteAddress','RemotePort','State',`
                        'ConnectionID','PID','Type','Count'
                $item = $netstatConnectionLine.line.split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)
                      
        $localAddress = $item[1].split(':')[0]
        $localPort = $item[1].split(':')[-1]
                $remoteAddress = $item[2].split(':')[0]
        $remotePort = $item[2].split(':')[-1]                        
        $proto = $item[0]
                $status  = $item[3] 
        $procId = "-1"
       
        If ($item.Length -Eq 5){
            $procId = $item[-1]
        }         
                                   
                $connection = New-Object -TypeName PSObject -Property @{
                                PID = $procId
            ConnectionID = ""
            Protocol = $proto
            LocalAddress = $localAddress
            LocalPort = $localPort
            RemoteAddress = $remoteAddress
            RemotePort = $remotePort
            State = $status
            Type = ""
            Counters = (@(0) * $RollingWindowSize)
            Count = 0;
        }
        $connection.Counters[$currentChunkIndex]++
               
                Return $connection
    }
 
    Function Is-Listening-To-All-Addresses ($connection){
                Return (($connection.State -eq $LISTENING_STATE) -And $connection.LocalAddress -eq $ALL_ADDRESSES)
    }
 
    Function Clone-Custom-Object ($objectToClone){
                $clonedObject = New-Object PsObject
       
                $objectToClone.PsObject.Properties | ForEach-Object {
                                $clonedObject | Add-Member -MemberType $_.MemberType -Name $_.Name -Value $_.Value
                }
               
                Return $clonedObject
    }
 
    Function Create-Connection-ForEach-IPv4 ($connection){
                $allIpsConnections = @()
               
                $localIPv4Addresses | ForEach-Object{
                                $clonedObject = Clone-Custom-Object -ObjectToClone $connection
                                $clonedObject.LocalAddress = $_
                                $allIpsConnections += $clonedObject
                }
                               
                Return $allIpsConnections
    }
 
    Function Is-Listening-To-All-Addresses ($connection){
                Return (($connection.State -eq $LISTENING_STATE) -and $connection.LocalAddress -eq $ALL_ADDRESSES)
    }
 
    Function Is-Incoming-Connection ($listeningRecordObjects, $connection){
        Return (($listeningRecordObjects | Where-Object {$_.Port -eq $connection.Local_Port}) -ne $Null)
    }
 
    Function Find-TCP-Connections-For-Processes (){
        Log "Collecting connections data..."
                $netstatOutput = Get-Netstat-Output        
                $netstatListeningStateRecords = $netstatOutput | Select-String -Pattern $LISTENING_STATE `
                                        | Select-String -Pattern $NETSTAT_TCP_RECORD_PATTERN
                $netstatNotListeningStateRecords = $netstatOutput | Select-String -Pattern $LISTENING_STATE -NotMatch `
                                           | Select-String -Pattern $NETSTAT_TCP_RECORD_PATTERN
                $listeningRecordObjects = @()
                                               
                $netstatListeningStateRecords | ForEach-Object {
                                $connectionObject = Parse-Connection -NetstatConnectionLine $_
                                
                                If ($connectionObject.PID -eq 0){
                                    Return;
                                }
            $connectionObject.Type = "on"
                                $matchedProcess = $processes.Item($connectionObject.PID)
                                $connectionsToAdd = @()
                                                                               
                                If (Is-Listening-To-All-Addresses -Connection $connectionObject){
                                   $connectionsToAdd = Create-Connection-ForEach-IPv4 -Connection $connectionObject
                                }
                                Else{
                $connectionsToAdd += $connectionObject
                                }              
            $connectionsToAdd = $connectionsToAdd | Select-Object ConnectionID,Count,Counters,Type,PID,@{N="IP";E={$_.LocalAddress}},@{N="Port";E={$_.LocalPort}},@{N="Local_IP";E={"undefined"}},@{N="Local_Port";E={"undefined"}}
                 
            $connectionsToAdd | ForEach-Object {
                Set-Connection-ID -Connection ($_)
               
                                                If ($matchedProcess -ne $Null){
               
                                                                If (-not $matchedProcess.IncomingConnections.ContainsKey($_.ConnectionID)){
                                                                                $matchedProcess.IncomingConnections.Add($_.ConnectionID, $_)
                                                                }
                                                                Else{
                                                                                $matchedProcess.IncomingConnections.Item($_.ConnectionID).Counters[$currentChunkIndex]++
                                                                }
                }
                $listeningRecordObjects += $_
                                }
                }
                               
                $netstatNotListeningStateRecords | ForEach-Object {
                                $connectionObject = (Parse-Connection -NetstatConnectionLine $_) | Select-Object ConnectionID,Count,Counters,Type,PID,@{N="IP";E={$_.RemoteAddress}},@{N="Port";E={$_.RemotePort}},@{N="Local_IP";E={$_.LocalAddress}},@{N="Local_Port";E={$_.LocalPort}} 
            If ($connectionObject.PID -eq 0){
                Return;
            }
            $matchedProcess = $processes.Item($connectionObject.PID)
                                               
                                If (-not (Is-Incoming-Connection -ListeningRecordObjects $listeningRecordObjects `
                                             -Connection $connectionObject)){
                $connectionObject.Type = "to"
                Set-Connection-ID -Connection ($connectionObject)
           
                If (($matchedProcess -ne $Null) -and `
                    (-not $matchedProcess.OutgoingConnections.ContainsKey($connectionObject.ConnectionID))){
                    $matchedProcess.OutgoingConnections.Add($connectionObject.ConnectionID, $connectionObject)
                }
                Else{
                    $matchedProcess.OutgoingConnections.Item($connectionObject.ConnectionID).Counters[$currentChunkIndex]++
                }
                                }
                }              
        Log "Connections data collection finished"
    }
 
    Function Detect-Cycle ($process, $visitedProcessesId ,$processesInCycle, $ppidsToReplace){
        $cycleStart = -1
       
        For ($i = 0; $i -lt $visitedProcessesId.Length; $i++){
           
            If ($process.ProcessId -eq $visitedProcessesId[$i]){
                $cycleStart = $i
                Break
            }
        }
       
        If ($cycleStart -gt -1){
            $smallestCreationDate = $process.CreationDate
            $eldestProcessId = $process.ProcessId
           
            For ($i = $cycleStart; $i -lt $visitedProcessesId.Length; $i++){
                $processId = $visitedProcessesId[$i]
                $processesInCycle[$processId] = $True
                $creationDate = $processes[$processId.toString()].CreationDate
               
                If ((-not $creationDate) -or ([datetime]$creationDate) -lt ([datetime]$smallestCreationDate)){
                   $smallestCreationDate = $creationDate
                   $eldestProcessId = $processId
                }
            }
            
            Log "Cycle detected at process $($processes.Item([string]$eldestProcessId).ParentProcessId)"
            $ppidsToReplace.Add($processes.Item([string]$eldestProcessId).ParentProcessId,$True)
            Return
        }
       
        $parentProcess = $processes[[string]($process.ParentProcessId)]
       
        If ($parentProcess){
           
            If ($processesInCycle.ContainsKey($process.ProcessId)){
                Return
            }
           
            $visitedProcessesId += $process.ProcessId
            Detect-Cycle -Process $parentProcess -VisitedProcesses $visitedProcessesId `
                         -ProcessesInCycle $processesInCycle -PPIDsToReplace $ppidsToReplace
        }
    }
 
    Function Replace-ParentProcessId ($ppidsToReplace){
        Log "Starting breaking PIDs cycles"
       
        $processes.Keys | ForEach-Object {
            $process = $processes.Item($_)
           
            If ($ppidsToReplace.ContainsKey($process.ParentProcessId)){
                $process.ParentProcessId = [Int]("99999" + $process.ParentProcessId)
            }
        }
        Log "Finished breaking PIDs cycles"
    }
 
    Function Handle-ProcessId-Reuse (){
        $ppidsToReplace = @{}
        $processesInCycle = @{}
        Log "Searching for PIDs cycles"
       
        $processes.Keys | ForEach-Object {
           
            If ($processesInCycle.ContainsKey($_)){
                Return
            }
            Detect-Cycle -Process $processes.Item($_) -VisitedProcesses @() `
                            -ProcessesInCycle $processesInCycle -PPIDsToReplace $ppidsToReplace
        }
       
        Replace-ParentProcessId -PPIDsToReplace $ppidsToReplace
    }
 
    Function Escape-JSONString($str){
               
        If ($str -eq $null) {Return ""}
                $str = $str.ToString().Replace('\','\\').Replace('"','\"')
                Return $str
    }
 
    #https://gist.github.com/mdnmdn/6936714
    Function ConvertTo-JSON($maxDepth = 4,$forceArray = $false) {
                Begin {
                                $data = @()
                }
       
                Process{
                                $data += $_
                }
               
                End{
               
                                If ($data.length -eq 1 -and $forceArray -eq $false) {
                                                $value = $data[0]
                                }
            Else {         
                                                $value = $data
                                }
 
                                If ($value -eq $null) {
                                                return "null"
                                }
 
                               
 
                                $dataType = $value.GetType().Name
                               
                                Switch -regex ($dataType) {
                            'String'  {
                                                                                return  "`"{0}`"" -f (Escape-JSONString $value)
                                                                }
                            '(System\.)?DateTime'  {Return  "`"{0:yyyy-MM-dd}T{0:HH:mm:ss}`"" -f $value}
                            'Int32|Double' {return  "`"{0}`"" -f  $value}
                                                                'Boolean' {Return  "$value".ToLower()}
                            '(System\.)?Object\[\]' { # array
                                                                              
                                                                                If ($maxDepth -le 0){Return "`"$value`""}
                                                                               
                                                                                $jsonResult = ''
                       
                                                                                ForEach($elem in $value){
 
                                                                                                If ($jsonResult.Length -gt 0) {$jsonResult +=', '}                                                         
                                                                                                $jsonResult += ($elem | ConvertTo-JSON -maxDepth ($maxDepth -1))
                                                                                }
                                                                                Return "[" + $jsonResult + "]"
                            }
                                                                '(System\.)?Hashtable' { # hashtable
                                                                                $jsonResult = ''
                                                                               
                        ForEach($key in $value.Keys){
                                                                                               
                            If ($jsonResult.Length -gt 0) {$jsonResult +=', '}
                                                                                                $jsonResult +=
@"
                "{0}": {1}
"@ -f $key.ToLower() , ($value[$key] | ConvertTo-JSON -maxDepth ($maxDepth -1) )
                                                                                }
                                                                                Return "{" + $jsonResult + "}"
                                                                }
                            Default { #object
                                                                                If ($maxDepth -le 0){Return  "`"{0}`"" -f (Escape-JSONString $value)}
                                                                               
                                                                                Return "{" +
                                                                                                (($value | Get-Member -MemberType *property | % {
@"
                "{0}": {1}
"@ -f $_.Name.ToLower() , ($value.($_.Name) | ConvertTo-JSON -maxDepth ($maxDepth -1) )                                
                                                                               
                                                                                }) -join ', ') + "}"
                                                }
                                }
                }
   }
 
    Function Create-Data-Json-File{
        $finalOutput = '{'
   
        $processesJson = $processes.Values | Select-Object @{N="Command";E={$_.CommandLine}},`
                                    @{N='PPID';E={$_.ParentProcessId}},@{N='PID';E={$_.ProcessId}},Name,Parameters,Count | ConvertTo-JSON
       
        $processes.Values | Select-Object IncomingConnections,OutgoingConnections | ForEach-Object {
       
            If ($_.IncomingConnections.Values -ne $Null){
                $connections.Add(($_.IncomingConnections.Values | Select-Object -Property * -ExcludeProperty ConnectionID,Counters))
            }
           
            If ($_.OutgoingConnections.Values -ne $Null){
                $connections.Add(($_.OutgoingConnections.Values | Select-Object -Property * -ExcludeProperty ConnectionID,Counters))
            }
        }
       
        $connectionsJson = $connections | ConvertTo-JSON
       
        If (($processes.Count -gt 0) -or ($connections.Count -gt 0)){
            $finalOutput += '"related_data": {"processes":' + $processesJson + ', "connections": ' + $connectionsJson + '}'
        }
       
        $finalOutput += '}'
        $finalOutput | Set-Content -Path $outputFile
        Log "Data has been written to $outputFile"
        $connections.Clear()
    }
 
    Function Reset-Chunk-Counters ($chunkIndex){
        $processes.Values | ForEach-Object {
            $_.Counters[$chunkIndex] = 0;
           
            If ($_.IncomingConnections.Values -ne $Null){
                $_.IncomingConnections.Values | ForEach-Object {
                    $_.Counters[$chunkIndex] = 0; 
                }
            }
           
            If ($_.OutgoingConnections.Values -ne $Null){
                $_.OutgoingConnections.Values | ForEach-Object {
                    $_.Counters[$chunkIndex] = 0;   
                }
            }
        }
    }
 
    Function Aggregate-Data{
       Log "Aggregating data..."
   
        $processes.Values | ForEach-Object {
            $_.Count = ($_.Counters | Measure-Object -sum).Sum
           
            If ($_.IncomingConnections.Values -ne $Null){
           
                $_.IncomingConnections.Values | ForEach-Object {
                    $_.Count = ($_.Counters | Measure-Object -sum).Sum  
                }
            }
           
            If ($_.OutgoingConnections.Values -ne $Null){
           
                $_.OutgoingConnections.Values | ForEach-Object {
                    $_.Count = ($_.Counters | Measure-Object -sum).Sum   
                }
            }
        }
        Log "Data aggregation finished"
    }
 
    Function Remove-Old-Processes (){
        $processesToDelete = @()
      
        $processes.Values | ForEach-Object {
           
            If ($_.Count -eq 0){
                $processesToDelete += [string]$_.ProcessId
            }
        }
       
        ForEach ($processId in $processesToDelete) {
            $processes.Remove($processId)
        }
        Log "Old data has been removed"
    }
 
    Function Create-PID-Locking-File (){
                $PID | Set-Content -Path "$HomeDir\$PID.pid"
        Log "$HomeDir\$PID.pid was created"
   }
   
    Function Create-Directory-If-Does-Not-Exist ($directory){                                 
        
        If (-not (Test-Path $directory)) {
            $Null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
        }
    }
 
    Function Validate-And-Create-HomeDir-If-Needed (){
       
        Try{
            Create-Directory-If-Does-Not-Exist -Directory $HomeDir
        }
        Catch{
            $script:logsBeforeBaseDirIsDetermined += "$([System.DateTime]::Now): $($_.Exception.Message)`r`n"
        }
    }
   
    Function Is-First-Run (){
        If (($HomeDir -ne "") -and (Test-Path $HomeDir)){
            Return $False
        }

        Return $True
    }
   
    Function GetDefaultBaseDir() {
        $pathToTest = "$env:TEMP"
       
        If (Test-Path $pathToTest){
            Return $pathToTest
        }

        $pathToTest = "$env:TMP"
       
        If (Test-Path $pathToTest){
            Return $pathToTest
        }

        Return "."
    }

    Function Clear-HomeDir (){
        If (Test-Path $HomeDir) {
           Remove-Item $HomeDir -Recurse
        }
    }
   
    Function Kill-Current-Process-If-Exists (){
        $processes = Get-Process
 
                Get-ChildItem $HomeDir | Where {$_.Extension -eq ".pid"} | ForEach-Object {
                                $baseName = [Int]$_.BaseName
                                $processRepresentedByFile = $processes | Where-Object {($_.Id -eq $baseName) -and ($_.Name -like "*powershell*")}
 
                                If ($processRepresentedByFile -ne $Null){
                $script:logsBeforeBaseDirIsDetermined += "$([System.DateTime]::Now): Killing Process #$baseName - $($processRepresentedByFile.Name)`r`n"
                                                $processRepresentedByFile.Kill()
                $script:logsBeforeBaseDirIsDetermined += "$([System.DateTime]::Now): Process #$baseName was killed`r`n"
                                }
                                                $_.Delete()
            $script:logsBeforeBaseDirIsDetermined += "$([System.DateTime]::Now): $_ was deleted"
                }
    }
   
    Function Set-Script-Files-And-Directories (){
        $script:logFile = "$HomeDir\$LOG_FILE"
        $script:outputFile = "$HomeDir\$OUTPUT_FILE"
    }
   
    Function Clear-All (){
        If (-not (Is-First-Run)){
            Kill-Current-Process-If-Exists
            Clear-HomeDir
        }
    }
   
    Function Prepare (){
        Clear-All
        Validate-And-Create-HomeDir-If-Needed
        Set-Script-Files-And-Directories
        Add-Content $logFile $logsBeforeBaseDirIsDetermined
        Log "Prepare for data collection..."
        Create-PID-Locking-File
    }
   
    if (($BaseDir -eq "") -or ($BaseDir -eq $null)) {
         $BaseDir = GetDefaultBaseDir
    }    
    $HomeDir = "$BaseDir\$ADME_WORKSPACE_NAME" 

    If ($Mode -eq "UNINSTALL"){
        Clear-All
        Return
    }
   
    Prepare
   
    $localIPv4Addresses = Get-All-IPv4-Addresses
    $samplesPerChunk = $ChunkAggregationInterval / $SamplingInterval
    $shouldContinueRunning = Test-Path "$HomeDir\$PID.pid"
 
    While ($shouldContinueRunning){
        If (-not $isCurrentChunkWasReset){
            Log "Clear data for chunk #$($currentChunkIndex+1)"
            Reset-Chunk-Counters -ChunkIndex $currentChunkIndex
            $isCurrentChunkWasReset = $True
        }
        
        Collect-And-Update-Process-Information
        Handle-ProcessId-Reuse
        Find-TCP-Connections-For-Processes
        $currentSampleIndex++
        $totalSamplesTaken++
        Log "Finished sample #$currentSampleIndex in chunk #$($currentChunkIndex+1)"
       
        If ($totalSamplesTaken -eq $MaxTotalSamples){
            $shouldContinueRunning = $False
            Log "Reached to maximum number of samples configured. Finishing data collection..."
            Continue
        }
       
        If ($currentSampleIndex -eq $samplesPerChunk){
            Aggregate-Data
            Remove-Old-Processes
            Create-Data-Json-File
            $currentSampleIndex = 0;
            $currentChunkIndex++;
            $isCurrentChunkWasReset = $False
           
            If ($currentChunkIndex -eq $RollingWindowSize){
                $currentChunkIndex = 0;
            }
            Log "Finished aggregation of chunk #$currentChunkIndex"
        }
 
                $shouldContinueRunning = Test-Path "$HomeDir\$PID.pid"
               
        #This condition is for skipping the sleep statement in case we need to end the program
                If (-not $shouldContinueRunning){
            Log "$PID.pid was deleted. Exit process"
                                Continue
                }
               
        Start-Sleep -S $SamplingInterval
    }
    Aggregate-Data
    Remove-Old-Processes
    Create-Data-Json-File
    Exit
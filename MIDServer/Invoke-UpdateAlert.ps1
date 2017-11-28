function Invoke-SCOMInitialize {
param(
		 $Path, $Version
	)
	$ErrorActionPreference = 'stop';
	try{
	if ($Version -eq "2012"){
		    $libs = @("Microsoft.EnterpriseManagement.Core.dll",
		    "Microsoft.EnterpriseManagement.OperationsManager.dll", 
		    "Microsoft.EnterpriseManagement.Runtime.dll" );
         }
         else{
               $libs = @("Microsoft.EnterpriseManagement.OperationsManager.Common.dll",
               "Microsoft.EnterpriseManagement.OperationsManager.dll");
        }
        $adminui = $(Join-Path -Path $Path -ChildPath 'extlib');
		$libs | %{
		$(Join-Path -Path $adminui -ChildPath $_)
			$configmgrprov = get-item -Path $(Join-Path -Path $adminui -ChildPath $_)
			
			Add-Type -path $configmgrprov
		}
	}catch {
        $_.Exception.Message
		return $false;
                exit 1;
	}
	
	return $true;
}
function Invoke-UpdateAlert {
param(
		$scomServerUsername, $scomServerPassword, $scomServerIP, $path, $version, $json
	)
     #this call will invoke the command to load the DLL's into memory in order for us to use them in this powershell session
     Invoke-SCOMInitialize $path $version; 
  
    $comment = "";
    $settings = new-object Microsoft.EnterpriseManagement.ManagementGroupConnectionSettings($scomServerIP);
    if($scomServerUsername -ne $null){
        $settings.UserName =$scomServerUsername;
        $Password = $scomServerPassword | ConvertTo-SecureString -AsPlainText -Force
        $settings.Password = $Password
    }
    $mg = [Microsoft.EnterpriseManagement.ManagementGroup]::Connect($settings);
    if(!$mg){
         exit 1;
    }
"JSON $json"
    $JsonObj = $json | ConvertFrom-Json
   foreach($alertObj in $JsonObj){
        $alertGuid = new-object System.Guid($alertObj.id);
	try{
               $alert = $mg.GetMonitoringAlert($alertGuid);   
        }
        catch{
               #Write the message, continue to the next alert (when the alert id is wrong, throws an exception)
               $_.Exception.Message
               continue
         }
       if($alertObj.command -eq "ticket_id"){
             #Change ticket id
             "Changing ticket id "
             $alert.TicketId = $alertObj.ticket_id;
             $comment = "Alert modified by bi-directional script (changing ticket id)"
             $alert.Update($comment);
        }elseif ($alertObj.command -eq "close"){
           #Close the alert
            "Closing "
            $alert.Refresh();
            $alert.ResolutionState = 0xff;
            $comment = "Alert resolved by bi-directional script"
            $alert.Update($comment);
        }elseif ($alertObj.command -eq "open"){
            #Open the alert
           "Opening "
           $alert.Refresh();
           $alert.ResolutionState = 0x00;
           $comment = "Alert re-opened by bi-directional script"
           $alert.Update($comment);
         }
}
    exit 0;
}
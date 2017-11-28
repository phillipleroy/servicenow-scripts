package com.service_now.mid.probe.tpcon.test

import com.glide.collections.StringMap
import com.glide.util.Log
import com.glide.util.ProcessRunner
import com.glide.util.StringUtil
import com.glide.util.XMLUtil
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.OperationStatusType
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event
import org.w3c.dom.Document
import org.w3c.dom.NodeList
import com.service_now.mid.services.FileSystem
import java.text.SimpleDateFormat
import java.lang.Integer
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.text.DateFormatSymbols 


/**
 * @author tal
 */
public class SCOMConnector extends ThirdPartyConnector {


    private static String TEST_CONNECTOR_SIGNATURE = "1";

    private static TimeZone GMT = TimeZone.getTimeZone("GMT");

    public OperationStatus execute() {
      
        Log.debug("in execute()")
        String user = context.getUsername();
        if (StringUtil.nil(user)) {
            writeError("FAILURE: Username not provided")
            return new OperationStatus(OperationStatusType.FAILURE);
        }
        String password = context.getPassword();
        def version = getParamValue(context.parameters.scom_version,"2007");
        
        String sysId = context.parameters.connectorSysId;
        String scom2012 = "SCOMClient2012"  + sysId + ".exe";
        String scom2007 = "SCOMClient"  + sysId + ".exe";

        organizeDllFiles();
        organizeExeFiles(scom2012,  scom2007);
        overrwriteOmDll();

        String signature = context.getLastDiscoverySignature();
        String lastTimeSignature = null;
        String lastEventID = null;

        Log.debug("SCOM signature = " + signature)
        if (signature != null) {
            def dotIdx = signature.indexOf('.')
            if (dotIdx != -1) {
                lastTimeSignature = signature.substring(0, dotIdx)
                lastEventID = signature.substring(dotIdx + 1)
            } else {
                lastTimeSignature = signature
                lastEventID = ""
            }
        }

        String events = getLatestEvents(context.getHost(), user, password, lastTimeSignature, scom2012, scom2007);

        if (StringUtil.notNil(events) && events.trim().startsWith("NEEBULA_ERROR:")) {
            String error = events.substring("NEEBULA_ERROR:".length());
            writeError("SCOM connector failed. " + error);
            return new OperationStatus(OperationStatusType.FAILURE);
        }

        boolean isFirstRun = StringUtil.nil(lastTimeSignature) || "null".equals(lastTimeSignature);
        parseAndProcessEvents(events, isFirstRun, lastEventID, lastTimeSignature);

        return new OperationStatus(OperationStatusType.SUCCESS);
    }

    private String getLatestEvents(String host, String user, String password, String lastTimeSignature, String scom2012, String scom2007) {

        Log.debug("getLatestEvents called")

        ProcessRunner runner = new ProcessRunner();
        def version = getParamValue(context.parameters.scom_version,"2007");
        def commandTosearch = "2012".equals(version) ? scom2012 : scom2007;         

        // Check the last SCOMClient invocation has ended
       if(commandTosearch.length() > 24) // tasklist trancate the command to 25 charecters 
               commandTosearch = commandTosearch.substring(0, 23)
        runner.runCommand("tasklist | findstr " + commandTosearch);
        String res = runner.getOutput();
        if (res.contains("SCOMClient")) {
            writeError("Previous SCOMClient instance is still running. Aborting this cycle ");
            return "NEEBULA_ERROR: " +  "Previous SCOMClient instance is still running. Aborting this cycle ";
        }

        def params  = "500 ${lastTimeSignature}";

        // Write the sql file to the target host
        if (StringUtil.nil(lastTimeSignature) || "null".equals(lastTimeSignature)) {
            def daysToRetrieve = getParamValue(context.parameters.scom_initial_sync_in_days,"7");
            params = "500 0 ${daysToRetrieve}";
        } else if (lastTimeSignature.equals(TEST_CONNECTOR_SIGNATURE)) {
            params = "1";
        }

        def pwd = "\"" + password + "\"";
        def command = "${scomLocation(scom2012, scom2007)} ${host} ${user} ${pwd} " + params;
        def commandDebug = "${scomLocation(scom2012, scom2007)} ${host} ${user} **** " + params;
        Log.debug("SCOM Connector: running command: " + commandDebug)
        int commandRes = runner.runCommand(command);
        String events = runner.getOutput();

        Log.debug("Debug: SCOM client command results is: " + commandRes + ", output is: "  +  runner.getOutput());


        if (runner.error) {
            writeError("Error running SCOM client: " + runner.error);
            return "NEEBULA_ERROR: " +  runner.error;
        }
        
        if (commandRes < 0) {
            writeError("Error running SCOM client, error identifier is " + commandRes + ".");
            return "NEEBULA_ERROR: " + " error identifier is " + commandRes + ".";
        }
        

        return events;
    }

    private scomLocation(String scom2012, String scom2007) {

        // path parameter from connector's definition
        def currentDir = System.getProperty("user.dir")
        def pathPrefix = currentDir + "\\extlib\\"

        // use different exe for SCOM 2012

        def version = getParamValue(context.parameters.scom_version,"2007");
        def path = pathPrefix + ("2012".equals(version) ? scom2012 : scom2007);
        // if there are whitespaces in the path need to wrap with double quotes
        return "\"" + path + "\""
    }

    private void parseAndProcessEvents(String events, boolean isFirstRun, String lastEventID, String lastSignatureTimestamp) {
        def emsSystem = context.name;
        if (StringUtil.nil(events)) {
            Log.debug("Got no events from SCOM client")
            return;
        }

        events = events.trim();

        IEventSender sender = MIDServer.getSingleton(IEventSender.class)

        String[] lines = events.split("NEEBULA_LINE_SEPARATOR");
        if (lines == null || lines.length < 2) {
            return;
        }

        Long maxLastModified;

        int eventsInText = 0;
        int eventsSent = 0
        // Skip the first line
        StringMap params = new StringMap();
        String alertId = null;
        String currentTimestamp;
        for (int lineNum = 1; lineNum < lines.length; lineNum++) {
            String line = lines[lineNum].trim();

            if (line.startsWith("Alert ID:")) {
                eventsInText++;
                if (!params.isEmpty() && alertId != null && currentTimestamp != null) {
                    if (!alertId.equals(lastEventID) || !currentTimestamp.equals(lastSignatureTimestamp)) { 
                        def dateFormat = getParamValue(context.parameters.scom_date_format, "M/d/yyyy h:mm:ss a");
                        if (sendEvent(alertId, params, sender, emsSystem, isFirstRun, dateFormat))
                            eventsSent++;
                    }
                }
                alertId = line.substring(9).trim();
                params = new StringMap();
                continue;
            }

            int colonPos = line.indexOf(':');
            if (colonPos <= 0) {
                continue;
            }

            String fieldName = line.substring(0, colonPos)
            String fieldValue = line.substring(colonPos + 1).trim();
            params.put(fieldName, fieldValue);

            if (fieldName.equals("LastModified")) {
                currentTimestamp = fieldValue; 
                if (maxLastModified == null) {
                    maxLastModified = Long.valueOf(fieldValue);
                } else {
                    Long currentLastModified = Long.valueOf(fieldValue);
                    if (currentLastModified > maxLastModified) {
                        maxLastModified = currentLastModified;
                    }
                }
            }

        } // End of loop over lines

        // Send the last event if needed
        if (!params.isEmpty() && alertId != null && currentTimestamp != null) {
            if (!alertId.equals(lastEventID) || !currentTimestamp.equals(lastSignatureTimestamp)) {
           def dateFormat = getParamValue(context.parameters.scom_date_format, "M/d/yyyy h:mm:ss a");
                if (sendEvent(alertId, params, sender, emsSystem, isFirstRun, dateFormat))
                    eventsSent++;
            }
        }

        if (maxLastModified != null) {
            if (alertId != null) {
                context.setLastDiscoverySignature(maxLastModified.toString() + "." + alertId)
            } else {
                context.setLastDiscoverySignature(maxLastModified.toString());
            }
        }

        Log.debug("SCOM Adapter summary: Events in client reply: " + eventsInText + ". Events sent to server: " + eventsSent);
    }

    private static boolean sendEvent(String alertId, StringMap params, IEventSender sender, String emsSystem, boolean openOnly, String dateFormat) {

        Log.debug("Creating event: alertId: " + alertId);
        Event event = new Event();

        try {
            event.setEmsSystem(emsSystem)
            event.setMessageKey(alertId);
            String hostName = findHost(params);

            if (!StringUtil.nil(hostName)) {
                event.setHostAddress(hostName);
            }

            event.setText(params.get("Name"));
            event.setType(params.get("Name"));

            if (params.containsKey("Description")) {
                if (event.getText() == null) {
                    event.setText(params.get("Description"));
                } else {
                    event.setText(event.getText() + ", Description: " + params.get("Description"))
                }
                params.remove("Description");
            }

            // 0 is New and 255 is closed
            if (StringUtil.notNil(params.get("ResolutionState")) && ("255".equals(params.get("ResolutionState")))) {
                if (openOnly)
                   return false;
                event.setResolutionState("Closing")
            } else {
                event.setResolutionState("New");
            }


            if (params.containsKey("LastModifiedDate")) {
                String timeOfEvent = convertTimeFormat(params.get("LastModifiedDate"), dateFormat);
                event.setTimeOfEvent(timeOfEvent);

            }

            String scomSeverity = params.get("SCOMSeverity");
            if ("Error".equals(scomSeverity)) {
                event.setSeverity("2");
            } else if ("Warning".equals(scomSeverity)) {
                event.setSeverity("4")
            } else if ("Information".equals(scomSeverity)) {
                event.setSeverity("5");
            } else {
                event.setSeverity("3");
            }

            // Truncate the Context since its too large
            String alertContext = params.get("Context");
            if (alertContext != null && alertContext.length() > 512) {
                params.put("Context", alertContext.substring(0, 512))
            }

            if (params.containsKey("MonitoringObjectName")) {
                event.setResource(params.get("MonitoringObjectName"));
            } else if (params.containsKey("MonitoringObjectPath")) {
                event.setResource(params.get("MonitoringObjectPath"));
            }

            if (params.containsKey("MetricName")) {
                event.setMetricName(params.get("MetricName"));
            }

            event.setAdditionalParameters(params);

            event.setSource("SCOM");

            Log.debug("Sending SCOM event: " + event);

            sender.sendEvent(event);
            return true;
        } catch (Exception e) {
            writeError("Failed to send event. " + e + ". " + event);
        }
        return false;
    }

    private static String convertTimeFormat(String dateStr, String dateFormat) {
        // both times are in GMT
       // but need to convert from input format to expected "yyyy-MM-dd HH:mm:ss"

     SimpleDateFormat sdfInput = new SimpleDateFormat(dateFormat);
     // parsing New Zealand time format
     if ( dateStr.contains("a.m.") || dateStr.contains("p.m.")){
           DateFormatSymbols symbols = sdfInput.getDateFormatSymbols(); 
           symbols = (DateFormatSymbols) symbols.clone(); 
           String[] arr= new String[2]; 
           arr[0] = "a.m."; 
           arr[1] = "p.m."; 
           symbols.setAmPmStrings(arr); 
           sdfInput.setDateFormatSymbols(symbols); 
     }
     sdfInput.setTimeZone(GMT);
     Date d  = sdfInput.parse(dateStr);
            
        SimpleDateFormat sdfOutput = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        sdfOutput.setTimeZone(GMT);
        String timeOfEvent = sdfOutput.format(d);

        return timeOfEvent;

    }

    @Override
    OperationStatus testConnection() {
        boolean eventOpStatusSuccess = testEventConnection();
        boolean metricOpStatusSuccess = true;
        if ("true".equals(context.parameters.kpi))
            metricOpStatusSuccess = testMetricConnection();

        if (!eventOpStatusSuccess || !metricOpStatusSuccess) {
            return new OperationStatus(OperationStatusType.FAILURE);
        }

        return OperationStatus.success();
    }

    boolean testEventConnection() {

        Log.debug("testEventConnection called")
        String host = context.host
        String user = context.username
        if (StringUtil.nil(user)) {
            writeError("testEventConnection FAILURE: Username not provided")
            return false;
        }
        String password = context.password
        
        String sysId = context.parameters.connectorSysId;
        String scom2012 = "SCOMClient2012"  + sysId + ".exe";
        String scom2007 = "SCOMClient"  + sysId + ".exe";

        organizeDllFiles();
        organizeExeFiles(scom2012,  scom2007);
        overrwriteOmDll();

        try {
            String events = getLatestEvents(host, user, password, TEST_CONNECTOR_SIGNATURE, scom2012, scom2007);

            if (StringUtil.notNil(events) && events.trim().startsWith("NEEBULA_ERROR:")) {
                String error = events.substring("NEEBULA_ERROR:".length());
                writeError("SCOM Event connector failed. " + error);
                return false;
            }

           // If there are alerts found, there will be 'Alert ID' string. If there are no alerts in SCOM, older implementation had empty
           // return value, new implementation reads something like: 'NEEBULA_LINE_SEPARATORCriteria: LastModified > '1/25/2015 10:13:02 PM'. Max alerts:1'
            if (StringUtil.notNil(events) && !events.contains("Alert ID") && !events.contains("NEEBULA_LINE_SEPARATOR")) {
                writeError("SCOM Event  connector failed, string not empty, and no alert id. Events content: --" + events + "--");
                return false;
            }

        } catch (Exception e) {
            writeError("SCOM test event connection failed" + e)
            return false;
        }

        return true;
    }

    boolean testMetricConnection() {
	       String sqlCommand = " select top 1  DateTime from Perf.vPerfRaw";
		Connection conn = null;
		Statement statement = null;
		ResultSet rs = null;
		String error = null;
                String jdbcURL;
		try {
	                     String databaseUserName = context.getDatabaseUser();
			     String databasePassword = context.getDatabasePassword();
		              String databasePort = context.parameters.database_port;
	                      String host =  context.parameters.database_host;
                              String instanceName =  context.parameters.instanceName;
			      Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");

			        if( StringUtil.notNil(databaseUserName) && StringUtil.notNil(databasePassword) ) {
					Log.debug("TestMetricConnection: connecting with local database user");
					jdbcURL = getJDBCUrl(false, host,  databasePort, instanceName);
					conn = DriverManager.getConnection(jdbcURL, databaseUserName, databasePassword);
				} else {
					Log.debug("TestMetricConnection: connecting with Windows Authentication");
					jdbcURL = getJDBCUrl(true, host,  databasePort, instanceName);
					conn = DriverManager.getConnection(jdbcURL);
				}
     
            	              statement = conn.createStatement();
            	              statement.setFetchSize(1);
            	              rs = statement.executeQuery(sqlCommand);
		} catch (Exception e) {
			error = e.getMessage();
		} finally {
			try { if (conn != null) conn.close(); } catch (Exception e) {};
			 try { if (rs != null) rs.close(); } catch (Exception e) {};
			 try { if (statement != null) statement.close(); } catch (Exception e) {};
		}

       if (StringUtil.notNil(error)) {
                Log.error("TestMetricConnection: " + error);
                String errorMessage = "\n\nCollect metrics (Test Connector):\n"
                 if(StringUtil.notNil(jdbcURL))
                     errorMessage = errorMessage + "Using JDBC URL: " + jdbcURL + "\n";
                 errorMessage = errorMessage + error;
                writeError(errorMessage);
                return false;
       }
       Log.debug("TestMetricConnection: SCOM metric test connection: success");
       return true;
    }

  private String getJDBCUrl  (boolean useWindowsAuthentication, String host,  String databasePort, String instanceName) {
            String jdbcURL;

            if(useWindowsAuthentication)
                   jdbcURL = "jdbc:sqlserver://" + host + ";DatabaseName=OperationsManagerDW;integratedSecurity=true";
            else
                   jdbcURL = "jdbc:sqlserver://" + host + ";DatabaseName=OperationsManagerDW";
            if(StringUtil.notNil(instanceName))
	              jdbcURL = jdbcURL + ";instanceName=" + instanceName;
             else
                     jdbcURL = jdbcURL + ";port=" + databasePort;
             Log.debug("TestMetricConnection: JDBC URL: " + jdbcURL);

            return jdbcURL;
   }

   private String checkForPowershellVersion  () {
       String retString = null;
       ProcessRunner runner = new ProcessRunner();
       runner.setCloseOutputToStart(true);
       runner.runCommand("powershell (Get-Host).Version.major");
       String powershellVersionStr = runner.getOutput();
       if(StringUtil.notNil(powershellVersionStr)) {
           int powershellVersion = 0;
           try{
                powershellVersion = Integer .parseInt(powershellVersionStr);
            } catch (NumberFormatException e) {
            
            }
           
            if(powershellVersion > 0 && powershellVersion <= 2) {
               Log.debug("Collect metrics: ERROR PowerShell version (" + powershellVersion + ") is not supported. The supported version is > 2 .");
               retString = "\nCollect metrics :\nERROR PowerShell version (" + powershellVersion + ") is not supported. The supported version is > 2 .";
            }
        }
    }

    private static String findHost(Map<String, String> params) {

        // First try PrincipalName
        String hostName = params.get("PrincipalName");
        if (StringUtil.notNil(hostName))
            return hostName;

        String alertContext = params.get("Context");
        if (StringUtil.notNil(alertContext)) {

            Document doc = XMLUtil.parse(alertContext);
            if (doc != null) {
                NodeList nodeList = doc.getElementsByTagName("HostName");
                if (nodeList != null && nodeList.length > 0) {
                    hostName = XMLUtil.getAllText(nodeList.item(0));
                    if (StringUtil.notNil(hostName)) {
                        return hostName;
                    }
                }

                nodeList = doc.getElementsByTagName("LoggingComputer");
                if (nodeList != null && nodeList.length > 0) {
                    hostName = XMLUtil.getAllText(nodeList.item(0));
                    if (StringUtil.notNil(hostName)) {
                        return hostName;
                    }
                }
            }
        }

        hostName = params.get("NetbiosComputerName");
        if (StringUtil.nil(hostName))
             hostName = params.get("MonitoringObjectPath");

        return hostName;
    }

   // if there is a file called Microsoft.EnterpriseManagement.OperationsManager.dll.'version-name', and the connector is the same version
  // overwrite the Microsoft.EnterpriseManagement.OperationsManager.dll file.
    private void overrwriteOmDll(){
        def scomVersion = getParamValue(context.parameters.scom_version, "2007");
        def currentDir = System.getProperty("user.dir");
        def extlibPath = currentDir + "\\extlib\\";
        def dllOm = extlibPath+"Microsoft.EnterpriseManagement.OperationsManager.dll";
        def dllOmWithVersion = dllOm + "." + scomVersion;
        def sourceFile = new File("$dllOmWithVersion");
        if (sourceFile.exists()) {
               copyFile(dllOmWithVersion, dllOm, false);
         }
     }


     private void organizeExeFiles(String scom2012, String scom2007) {
        def currentDir = System.getProperty("user.dir")

        def scom07Build = currentDir + "\\bin\\sw_wmi\\bin\\scom2007\\SCOMClient.exe"
        def scom07BuildConfig = currentDir + "\\bin\\sw_wmi\\bin\\scom2007\\SCOMClient.exe.config"
        def scom12Build = currentDir + "\\bin\\sw_wmi\\bin\\scom2012\\SCOMClient2012.exe"
        def scom12BuildConfig = currentDir + "\\bin\\sw_wmi\\bin\\scom2012\\SCOMClient2012.exe.config"
        
        def destPath07 = currentDir + "\\extlib\\" + "\\" + scom2007;
        def destPath07Config = currentDir + "\\extlib\\" + "\\" + scom2007 + ".config"
        def destPath12 = currentDir + "\\extlib\\" + "\\" + scom2012;
        def destPath12Config = currentDir + "\\extlib\\" + "\\" + scom2012 + ".config"
       

        copyFile(scom07Build, destPath07);
        copyFile(scom07BuildConfig, destPath07Config);
        copyFile(scom12Build, destPath12);
        copyFile(scom12BuildConfig, destPath12Config);

    }

    private static void organizeDllFiles() {
        def currentDir = System.getProperty("user.dir")

        def etcPath = currentDir + "\\etc\\"
        def extlibPath = currentDir + "\\extlib\\"

        def dll_1 = "Microsoft.EnterpriseManagement.Core.dll"
        def dll_2 = "Microsoft.EnterpriseManagement.OperationsManager.dll"
        def dll_3 = "Microsoft.EnterpriseManagement.Runtime.dll"

        def dll_4 = "Microsoft.EnterpriseManagement.OperationsManager.Common.dll"
        def dll_5 = "Microsoft.EnterpriseManagement.OperationsManager.dll"

        copyFile(etcPath + dll_1, extlibPath + dll_1);
        copyFile(etcPath + dll_2, extlibPath + dll_2);
        copyFile(etcPath + dll_3, extlibPath + dll_3);
        copyFile(etcPath + dll_4, extlibPath + dll_4);
        copyFile(etcPath + dll_5, extlibPath + dll_5);

    }
     private static void copyFile(sourcePath, destPath) {
          copyFile(sourcePath, destPath,  true);
     }
     
     private static void copyFile(sourcePath, destPath, greaterThan) {
        def shouldCopy = true

        def updateTimeSource
        def updateTimeDest

        def sourceFile = new File("$sourcePath");
        if (sourceFile.exists()) {
            updateTimeSource = sourceFile.lastModified()
        }
        else {
            shouldCopy = false;
        }

        def destFile = new File("$destPath");
        if (destFile.exists()) {
            updateTimeDest = destFile.lastModified()
            if (greaterThan && updateTimeSource<=updateTimeDest) {
                shouldCopy = false
            }
            else if (!greaterThan && updateTimeSource==updateTimeDest) {
                shouldCopy = false
            }
        }

        if (shouldCopy) {
            Log.debug("Copying  " + sourcePath + " to " + destPath);
            (new AntBuilder()).copy(file:sourcePath, tofile:destPath, preservelastmodified : 'true')
        }

     }
     void writeError(String errorMessage){
          Log.error(errorMessage);
          // the method in the context could not exist;
        if (context.metaClass.respondsTo(context, "addErrorMessage", String))
            context.addErrorMessage(errorMessage);
     }

String getParamValue(String paramValue, String defaultValue){
        String newParamValue = paramValue;
        if (!newParamValue)
            newParamValue = defaultValue;
        if (newParamValue == "2016")
              newParamValue = "2012";

        return newParamValue;
     }
}
package com.service_now.mid.probe.tpcon.test

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.URLConnection;
import java.util.List;

import org.apache.commons.codec.binary.Base64;

import com.glide.util.Log
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.event.SNEventSender
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.OperationStatusType
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event
import com.service_now.mid.probe.event.SNEventSenderProvider

import groovy.util.slurpersupport.GPathResult





import groovy.sql.Sql


public class HypericConnector extends ThirdPartyConnector {

	def alertsLimitToRead = 3000; // read up to 3000 alerts

	@Override
	OperationStatus testConnection() {
		def ok = false;
		try {
			Log.debug("HypericConnector: testing connection ...")
			
			GPathResult alertsResponce = readAlerts('hqu/hqapi1/alert/find.hqu?begin=0&end=1&count=1000000&severity=1');
			if (alertsResponce == null)
                                return new OperationStatus(OperationStatusType.FAILURE);
			Log.debug('HypericConnector: testing connection responce ' + alertsResponce.Status)
			if (alertsResponce.Status == "Success") {
				ok = true;
				Log.debug("HypericConnector: testing connection OK")
			}
			else {
				Log.debug("HypericConnector: testing connection failed")
				
			}
		} catch (Exception e) {
			 writeError("HypericConnector: Failed to connect", e)
		}
		return ok ? OperationStatus.success() : new OperationStatus(OperationStatusType.FAILURE)

	}

	
	
	
	@Override
	OperationStatus execute() {
		try {
			Log.debug("HypericConnector: getting events, last signature is: ${context.lastDiscoverySignature}")

			// read alert resources and alert definitions
			def alertDefMap = [:]
			def resourceDefMap = [:]
			def metricMap = [:]
		

			def list = new ArrayList();

			def lastSignatureStr = context.lastDiscoverySignature;
			
			// the first time take 2 days back
			if (lastSignatureStr == null)
				lastSignatureStr = new Long( System.currentTimeMillis() - 2*24*3600*1000L).toString();
			
			Long lastSignature = new Long(lastSignatureStr)
			String tillStr = new Long(System.currentTimeMillis() + 2*24*3600*1000L).toString();
				
			// read alerts
			GPathResult alertsResponce1 = readAlerts('hqu/hqapi1/alert/find.hqu?begin=' + lastSignatureStr + '&end='+ tillStr +'&count=' + alertsLimitToRead + '&severity=1&inEscalation=false&notFixed=false');
                         if (alertsResponce1 == null)
                                return new OperationStatus(OperationStatusType.FAILURE);
			alertsResponce1.Alert.each{

				fillDefinitionTables(it, alertDefMap, resourceDefMap, metricMap);	

			  	createEventFromIt(it,  alertDefMap, resourceDefMap, metricMap, list)
			  	
			  	if (new Long(it.@ctime.toString()) > lastSignature)
			  		lastSignature = new Long(it.@ctime.toString())

//			    Log.debug(it.@id.toString()  + " " + it.@name.toString()  + " " + it.@ctime.toString()  + " " +it.@reason.toString()  + " " +it.@fixed.toString()  + " ")
			}
			
			

			if (list.isEmpty()) {
				Log.debug("HypericConnector got no new events")
				return OperationStatus.success()
			}



			IEventSender eventSender = SNEventSenderProvider.getEventSender()
			
			for (Event event  : list) {
				eventSender.sendEvent(event)
			}

			context.lastDiscoverySignature = lastSignature.toString()
			
			Log.debug("HypericConnector got ${list.size()} events, new signature is ${context.lastDiscoverySignature}")
			
			return OperationStatus.success()

		} catch (Exception e) {
			 writeError("Failed to connect to HypericConnector", e)
			return new OperationStatus(OperationStatusType.FAILURE)
		}
	}


        void fillDefinitionTables(alert , alertDefMap, resourceDefMap, metricMap) {
                
            // do it only if resource does not found yet
            if (resourceDefMap.get(alert.@resourceId.toString()) == null) {
			    GPathResult alertsResponce = readAlerts('hqu/hqapi1/alertdefinition/listDefinitions.hqu?resourceId=' +  alert.@resourceId.toString());
	            Log.debug("HypericConnector:  got  " + alertsResponce.AlertDefinition.size() +  "  alert definitions");
			    alertsResponce.AlertDefinition.each{
			      	alertDefMap.putAt(it.@id.toString(), it.@priority.toString() );
			      	resourceDefMap.putAt(it.Resource.@id.toString(), it.Resource.@name.toString() );
                                
                              // if  type =  1  =>  metric condition (compare to absolute value)
                              // if type = 2 =>  metric condition (compare to baseline)
                               //  https://pubs.vmware.com/vfabric5/index.jsp#com.vmware.vfabric.hyperic.4.6/HQApi_alertdefinition_command.html
                               if (it. AlertCondition.@type == 1)
			      	    metricMap.putAt(it.@id.toString(),  it. AlertCondition.@thresholdMetric.toString());
                               else if (it. AlertCondition.@type == 2)
			      	     metricMap.putAt(it.@id.toString(),  it. AlertCondition.@baselineMetric.toString());

   				    // Log.debug("alert definition:" + it.@id.toString()  + " alert name:" + it.@name.toString()  + " resource id:" + it.Resource.@id.toString() + " resource:" + it.Resource.@name.toString() + " metric:" + metricMap.get(it.@id.toString()))
				}
			}
        }
	
        GPathResult readAlerts(String apiFunction){
		
		def authString = (context.username + ':'+ context.password).getBytes().encodeBase64().toString()
		
		def urlStr = context.parameters.protocol + '://'+context.host + ':' + context.parameters.port + '/' + apiFunction
		Log.debug("HypericConnector url " + urlStr)	
	        String req1;
		try{
		         URL url = new URL(urlStr);
		         URLConnection urlConnection = url.openConnection();
		         urlConnection.setRequestProperty("Authorization", "Basic " + authString);
		         req1 = urlConnection.content.text;
                 } catch (Exception e){
                          writeError("Exception connecting: ", e);
                         return null;
                 }
                //Log.debug("HypericConnector answer " + req1);
		def slurper = new XmlSlurper();
		def alertsResponse = slurper.parseText(req1);
		Log.debug("alertsResponse:" + alertsResponse.toString());
		return alertsResponse;
	}
	
	void createEventFromIt(def it, Map alertDefMap, Map resourceDefMap, Map metricMap, List<Event> list) {
			
		// Log.debug(it.@id.toString()  + " " + it.@name.toString()  + " " + it.@ctime.toString()  + " " +it.@reason.toString()  + " " +it.@fixed.toString()  + " ")
		
		
		Event event = new Event()
		event.emsSystem = context.name
		event.source = "Hyperic"
		event.description = it.@reason
		event.type = it.@name
		
		if (it.ctime) {
					
			//convert raw value (Sybase) to string value
			Long occNum = new Long(it.@ctime.toString());
			Date d = new Date(occNum);
			def tz = TimeZone.getTimeZone('GMT')
			String timeOfEvent = d.format('yyyy-MM-dd HH:mm:ss',tz);
			event.setTimeOfEvent(timeOfEvent);
		}
		
		// should be modified
		event.severity = 5
		
                String[] myHost = resourceDefMap.get(it.@resourceId.toString()).split("\\s+");
                event.hostAddress = myHost[0];
                event.resource = resourceDefMap.get(it.@resourceId.toString());
		event.setField("fixed", it.@fixed.toString())
		event.setField("priority", alertDefMap.get(it.@alertDefinitionId.toString()))
		event.setField("metric_name", metricMap.get(it.@alertDefinitionId.toString()))
			
		list << event
	
	}
	void writeError(String message, Exception e){
               Log.error(message, e);
               // the method in the context could not exist;
               if (context.metaClass.respondsTo(context, "addErrorMessage", String))
                         context.addErrorMessage(message + "  "+  e.toString());
        }
}
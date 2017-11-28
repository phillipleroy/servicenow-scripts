package com.service_now.mid.probe.tpcon.test

import com.glide.util.Log
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.OperationStatusType
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event
import groovy.sql.Sql

/**
 * @author rimar
 */
class NetcoolConnector extends ThirdPartyConnector {

    private static final String DRIVER = "com.sybase.jdbc3.jdbc.SybDriver"
    private static final String TEST_CONNECTOR_SIGNATURE = "1"

    OperationStatus testConnection() {
        Sql sql = null
        try {
            Log.debug("Netcool connection test")
            sql = Sql.newInstance(context.url, context.username, context.password, DRIVER)
            sql.eachRow("select count(*) as cnt from alerts.status") {
                Log.debug("There are " + it.cnt + " events in the alerts.status table")
            }
            Log.debug("Netcool connection success")
            return OperationStatus.success()

        } catch (Exception e) {
            writeError("Netcool test query failed", e)
           return new OperationStatus(OperationStatusType.FAILURE);
        } finally {
            if (sql)
                sql.close()
        }
    }

    OperationStatus execute() {

        def query
        def lastTimeSignature = context.lastDiscoverySignature
        def newLastTimeSig = lastTimeSignature
        def emsSystem  = context.name
        def initialPull = false

        if (!lastTimeSignature) {
            // first time take the last 2000 records
            query = "select top 2000 Identifier,Node,NodeAlias,AlertKey,Manager,Agent,AlertGroup,Severity,Type,Summary,Acknowledged,LastOccurrence,StateChange,SuppressEscl from alerts.status where Manager not like '^.*Watch\$' order by StateChange desc";
            initialPull = true
        } else if (lastTimeSignature == TEST_CONNECTOR_SIGNATURE) {
            query = "select top 1 Identifier,Node,NodeAlias,AlertKey,Manager,Agent,AlertGroup, Severity,Type,Summary,Acknowledged,LastOccurrence,StateChange,SuppressEscl from alerts.status";
        } else {
            // other then first time we do ascending sort so take the last signature
            query = "select top 3000 Identifier,Node,NodeAlias,AlertKey,Manager,Agent,AlertGroup,Severity,Type,Summary,Acknowledged,LastOccurrence,StateChange,SuppressEscl from alerts.status where StateChange > " + lastTimeSignature + " and Manager not like '^.*Watch\$' order by StateChange asc";
        }

        IEventSender eventSender = MIDServer.getSingleton(IEventSender.class)
        Sql sql = null
        try {
            Log.debug("Fetching Netcool events")

            sql = Sql.newInstance(context.url, context.username, context.password, DRIVER)
            def list = []
            sql.eachRow(query) {
                createEvent(it, list, emsSystem, initialPull)

                // first time the query is descending so take the first record, otherwise take the last
                // Log.debug("it.StateChange : " + it.StateChange )
                if (newLastTimeSig == null || lastTimeSignature) {
                    newLastTimeSig = "" + it.StateChange
                }
            }
            Log.debug("Fetched " + list.size() + " Netcool events")

            list.each { event ->
                eventSender.sendEvent(event)
            }

            if (newLastTimeSig)
            context.lastDiscoverySignature = newLastTimeSig
            Log.debug("Finished sending events")

            return OperationStatus.success()

        } catch (Exception e) {
            writeError("Netcool get events query failed", e)
            return new OperationStatus(OperationStatusType.FAILURE);
        } finally {
            if (sql)
                sql.close()
        }
    }

    

    private static void createEvent(it, list, emsSystem, initialPull) {
               
        Event event = new Event();

        try {
            event.setSource("IBM Netcool")
            event.setEmsSystem(emsSystem)
            
            if (it.Node) {
                def node = it.Node.replace('\u0000','')
                event.setField("node", node)                
                event.setHostAddress(node)
            }

            if (it.NodeAlias) {
                def nodeAlias = it.NodeAlias.replace('\u0000','')
                event.setField("node_alias", nodeAlias)
                if (!event.hostAddress) {
                    event.setHostAddress(nodeAlias)
                }
            }
            if (!event.hostAddress) {
                Log.debug("No host address found. Event ignored.")
                return
            }
            if (it.AlertKey) event.setField("alert_key", it.AlertKey.replace('\u0000',''));
            if (it.Manager) event.setField("alert_group", it.Manager.replace('\u0000',''));
            if (it.Agent) event.setField("manager", it.Agent.replace('\u0000',''));
            if (it.AlertGroup) event.setField("agent", it.AlertGroup.replace('\u0000',''));
            if (it.Identifier) event.setField("identifier", it.Identifier.replace('\u0000',''));

            def sType = "" + it.Type
            if (it.Type) {
                event.setField("netcool_type", sType.replace('\u0000',''))
            };

            Long supperesEsclNum = 0;
                try {
                    if (it.SuppressEscl != null) {
                        supperesEsclNum = Long.parseLong(it.SuppressEscl);
                    }
                } catch (Exception ignore) {

                }  

            def activeEvent = true
            if ("2".equals(sType) || "4".equals(sType) || "8".equals(sType) ||
                    "1".equals("" + it.Acknowledged) || supperesEsclNum >= 4) {
                activeEvent = false
            }

            if (activeEvent || !initialPull) {
                if (it.Severity) event.setField("netcool_severity", ("" + it.Severity).replace('\u0000',''));
                if (it.SuppressEscl) event.setField("suppress_escl", ("" + it.SuppressEscl).replace('\u0000',''));
                if (it.LastOccurrence) {
                    //save raw value
                    event.setField("last_occurence", ("" + it.LastOccurrence).replace('\u0000',''));
                    
                    //convert raw value (Sybase) to string value
                    Long occNum =it.LastOccurrence.toLong();
                    occNum = occNum*1000;
                    Date d = new Date(occNum);
                    def tz = TimeZone.getTimeZone('GMT')
                    String timeOfEvent = d.format('yyyy-MM-dd HH:mm:ss',tz);
                    event.setTimeOfEvent(timeOfEvent);
                }        

                try {
                    if (it.StateChange) {
                        Long stateChangeNum = Long.parseLong(it.StateChange);
                        Date stateChangeTime = new Date(stateChangeNum * 1000);
                        event.setField("state_change_time", stateChangeTime.toString().replace('\u0000',''));
                    }
                } catch (Exception ignore) {
                }

                String messageKey = it.Identifier.replace('\u0000','') + "_" + 
                                    event.hostAddress + "_" + 
                                    it.AlertGroup.replace('\u0000','') + "_" + 
                                    it.AlertKey.replace('\u0000','') + "_" +
                                    it.Manager.replace('\u0000','') + "_" + 
                                    it.Agent.replace('\u0000','');

                event.setMessageKey(messageKey);

                event.setResolutionState("New")
                if (!activeEvent) {
                    event.setResolutionState("Closing")
                }
                event.setText(it.Summary.replace('\u0000',''));
                event.setSeverity("5");
                def severity = it.Severity + ""
                if ("1".equals(severity) || "2".equals(severity)) {
                    event.setSeverity("4");
                }

                if ("3".equals(severity)) {
                    event.setSeverity("3");
                }

                if ("4".equals(severity)) {
                    event.setSeverity("2");
                }

                if ("5".equals(severity)) {
                    event.setSeverity("1");
                }

                list << event    
            }         
        } catch (Exception e) {
            writeError("Failed to create event: " + event, e);
        }

    }
    void writeError(String message, Exception e){
          Log.error(message, e);
          // the method in the context could not exist;
        if (context.metaClass.respondsTo(context, "addErrorMessage", String))
              context.addErrorMessage(message + "  "+  e.toString());
   }
}
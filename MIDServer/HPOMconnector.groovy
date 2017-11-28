package com.service_now.mid.probe.tpcon.test

import com.glide.util.Log
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.OperationStatusType
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event
import groovy.sql.Sql


public class HpomUnix extends ThirdPartyConnector {

    //private static final String DRIVER = "oracle.jdbc.OracleDriver"
    private long actTimeStamp = 0
    private long histTimeStamp = 0
    private def isError = false; 


    def testQuery(String driver, String url, String user, String pass) {
        Sql sql = null
        try {

            String ret = "error: uninitialized"
            sql = Sql.newInstance(url, user, pass, driver)
            sql.eachRow("select count(*) as cnt from opc_op.opc_act_messages") { ret = String.valueOf(it.cnt) }
            return ret

        } catch (Exception e) {
            writeError("HPOM test query failed: ", e)
            return "error: " + e.getMessage()
        } finally {
            if (sql)
                sql.close()
        }
    }

    def queryActTable(String driver, String url, String user, String pass, long lastActTime, long lastHistTime) {
        Sql sql = null
        def list = []
        try {

            sql = Sql.newInstance(url, user, pass, driver)
            sql.eachRow("select t1.message_number, receiving_time, severity, ackn_time, msg_key, text_part, node_name, service_name " +
                    " from opc_op.opc_act_messages t1, opc_op.opc_msg_text t2, opc_op.opc_node_names t3" +
                    " where t1.message_number = t2.message_number and t1.node_id = t3.node_id" +
                    " and rownum < 1000 and (receiving_time > ? or ackn_time > ?)" +
                    " order by ackn_time, receiving_time, t2.order_number", [lastActTime, lastHistTime]) {

                /* if (Log.tra()) {
                    res += "message_number: " + it.message_number + ", receiving_time: " + it.receiving_time + ", severity: "
                    +it.severity + ", ackn_time: " + it.ackn_time + ", msg_key: " + it.msg_key
                    +", text_part:" + it.text_part + " ### "
                } */

                createEventFromIt(it, list, false)
            }
            Log.debug("Number of active events is: " + list.size())

        } catch (Exception e) {
           isError = true
           writeError("Failed to query opc_act_messages", e)
        } finally {
            if (sql)
                sql.close()
        }
        return list
    }


    def queryHistTable(String driver, String url, String user, String pass, long lastTime) {
        Sql sql = null
        def list = []
        try {

            Log.debug("hpov: performing hist query")
            sql = Sql.newInstance(url, user, pass, driver)
            sql.eachRow("select t1.message_number, receiving_time, severity, ackn_time, msg_key, text_part, node_name, service_name " +
                    " from opc_op.opc_hist_messages t1, opc_op.opc_hist_msg_text t2, opc_op.opc_node_names t3" +
                    " where t1.message_number = t2.message_number and t1.node_id = t3.node_id" +
                    " and rownum < 1000 and ackn_time > ? " +
                    " order by ackn_time, receiving_time, t2.order_number", [lastTime]) {

                /*
                if (log.isTraceEnabled()) {
                    res += "message_number: " + it.message_number + ", receiving_time: " + it.receiving_time + ", severity: "
                    +it.severity + ", ackn_time: " + it.ackn_time + ", msg_key: " + it.msg_key
                    +", text_part:" + it.text_part + " ### "
                }
                */

                createEventFromIt(it, list, true)
            }

            Log.debug("HpOm got " + list.size() + " events");

        } catch (Exception e) {
            isError = true
            writeError("Failed to query opc_hist_messages", e)
        } finally {
            if (sql)
                sql.close()
        }
        return list

    }

    void createEventFromIt(def it, List<Event> list, boolean hist) {

        if (list.size() > 0 && list.last().getField("message_number") == String.valueOf(it.message_number))
            return

        Event event = new Event()
        event.setField("message_number", String.valueOf(it.message_number));
        event.emsSystem = context.name
        event.source = "HPOM"
        event.messageKey = it.msg_key
        event.text = it.text_part
        if (hist || it.ackn_time) {
            event.resolutionState = "Closing"
            event.setField("ackn_time", String.valueOf(it.ackn_time))
            if (it.ackn_time > histTimeStamp)
                histTimeStamp = it.ackn_time

        } else {
            event.resolutionState = "New"
            if (it.receiving_time > actTimeStamp)
                actTimeStamp = it.receiving_time

        }

        if (it.receiving_time) {
                    
            //convert raw value (Sybase) to string value
            Long occNum = it.receiving_time*1000;
            Date d = new Date(occNum);
            def tz = TimeZone.getTimeZone('GMT')
            String timeOfEvent = d.format('yyyy-MM-dd HH:mm:ss',tz);
            event.setTimeOfEvent(timeOfEvent);
        } 

        event.setField("receiving_time", String.valueOf(it.receiving_time))
        event.severity = to_sev(it.severity)
        event.hostAddress = it.node_name
        event.setField("service_name", it.service_name)

        list << event

    }

    static String to_sev(def sev) {
        if (sev == 4) return "4" // warning
        if (sev == 8) return "1" // critical
        if (sev == 16) return "3" // minoe
        if (sev == 32) return "2" // major
        return "1"
    }

    OperationStatus testConnection() {

        def url = context.url
        String driver = context.parameters.driver
        Log.debug("hpov: before test query url is: " + url + " driver is: " + driver)
        def result = testQuery(driver, url, context.username, context.password)
        Log.debug("hpov: test query result is: " + result)

        if (result.startsWith("error:"))
            return new OperationStatus(OperationStatusType.FAILURE)

        return OperationStatus.success()
    }

    OperationStatus execute() {
        String url = context.url
        String driver = context.parameters.driver
        def signature = context.lastDiscoverySignature

        Log.debug("hpov signature = " + signature)
        if (signature != null) {
            def dotIdx = signature.indexOf('.')
            if (dotIdx != -1) {
                actTimeStamp = Long.parseLong(signature.substring(0, dotIdx))
                histTimeStamp = Long.parseLong(signature.substring(dotIdx + 1))
            } else {
                actTimeStamp = Long.parseLong(signature)
                histTimeStamp = actTimeStamp
            }
        }

        Log.debug("before hpov event sync, actTimeStamp = " + actTimeStamp + ", histTimeStamp = " + histTimeStamp +", url = " + url)

        def list = []
        list.addAll(queryActTable(driver, url, context.username, context.password, actTimeStamp, histTimeStamp))
        list.addAll(queryHistTable(driver, url, context.username, context.password, histTimeStamp))
        if (isError)
                 return OperationStatus.failure() 
        def eventSender = MIDServer.getSingleton(IEventSender.class)
        list.each { event ->
            eventSender.sendEvent(event)
        }
        Log.debug("after hpov event sync, actTimeStamp = " + actTimeStamp + ", histTimeStamp = " + histTimeStamp)

        context.setLastDiscoverySignature(actTimeStamp + "." + histTimeStamp)

        return OperationStatus.success()
    }
    void writeError(String message, Exception e){
          Log.error(message, e);
          // the method in the context could not exist;
        if (context.metaClass.respondsTo(context, "addErrorMessage", String))
            context.addErrorMessage(message + "  "+  e.toString());
   }
}
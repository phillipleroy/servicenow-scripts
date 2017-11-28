package com.service_now.mid.probe.tpcon.test

import com.glide.util.Log
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.solarwinds.SolarWindsNodeCache
import com.service_now.mid.probe.solarwinds.SolarwindsClient
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.OperationStatusType
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event

/**
 * @author rimar
 */
public class SolarwindsConnector extends ThirdPartyConnector {

    SolarwindsClient client = new SolarwindsClient(new SolarWindsNodeCache())

    @Override
    OperationStatus testConnection() {
        def ok = false
        try {
            Log.debug("Solarwinds testing connection")
            ok = client.testConnection(context.host, context.port, context.username, context.password)
            Log.debug("Solarwinds testConnection success")
        } catch (Exception e) {
            Log.error("Failed to connect to Solarwinds", e)
        }
        return ok ? OperationStatus.success() : new OperationStatus(OperationStatusType.FAILURE)

    }

    @Override
    OperationStatus execute() {
        try {
            Log.debug("Solarwinds getting events, last signature is: ${context.lastDiscoverySignature}")

            def list = client.getEvents(context.host, context.port, context.username, context.password,
                    context.lastDiscoverySignature, 3000)

            if (list.isEmpty()) {
                Log.debug("Solarwinds got no new events")
                return OperationStatus.success()
            }

            Event latest = list.get(list.size() - 1);
            context.lastDiscoverySignature = latest.getField(SolarwindsClient.SW_EVENT_ID)


            Log.debug("Solarwinds got ${list.size()} events, new signature is ${context.lastDiscoverySignature}")

            IEventSender eventSender = MIDServer.getSingleton(IEventSender.class)
            def source = "SolarWinds"
            for (Event event  : list) {
                event.setSource(source)
                event.setEmsSystem(context.name)
                eventSender.sendEvent(event)
            }

            return OperationStatus.success()

        } catch (Exception e) {
            Log.error("Failed to connect to Solarwinds", e)
            return new OperationStatus(OperationStatusType.FAILURE)
        }
    }
}
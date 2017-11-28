package com.service_now.mid.probe.tpcon.test
import com.glide.util.Log
import com.service_now.mid.MIDServer
import com.service_now.mid.probe.event.IEventSender
import com.service_now.mid.probe.tpcon.OperationStatus
import com.service_now.mid.probe.tpcon.ThirdPartyConnector
import com.snc.commons.eventmgmt.Event

public class TestTpcon extends ThirdPartyConnector {

    OperationStatus testConnection() {

        Log.info("TestTpcon: testConnection called")
        IEventSender eventSender = MIDServer.getSingleton(IEventSender.class)
        def event = new Event()
        event.setSeverity("1")
        event.setMessageKey("123")
        event.setField("evFoo", "evBar")
        eventSender.sendEvent(event)
        return OperationStatus.success()
    }

    OperationStatus execute() {
        Log.info("TestTpcon: execute called");
        return OperationStatus.success()
    }

}
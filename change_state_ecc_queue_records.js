var myRecord = new GlideRecord("ecc_queue");
myRecord.addQuery('topic', 'ServiceDiscoveryProbe');
myRecord.addQuery('state', 'ready');
myRecord.query();
while (myRecord.next()) {
  //gs.print(myRecord.sys_id);
  myRecord.state = 'processed';
  myRecord.setWorkflow(false); //Don't fire Business rule,notifications
  myRecord.update();
}

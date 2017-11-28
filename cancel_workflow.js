/*

Script to cancel running/active Workflows.

*/

var myGR = new GlideRecord("wf_context");
myGR.addQuery('workflow_version.name', 'Normal Change 4 level approval'); //Sys ID from the old Workflow Version
myGR.addQuery('state', 'executing');
myGR.addQuery('started', '<', '2017-01-30 15:44:08');
myGR.query();
gs.print(myGR.getRowCount() + " records found");
while (myGR.next()) {
  var id_from_record = myGR.id;
  gs.print("Context: " + myGR.sys_id + " found! The context is related to Change: " + myGR.id.number);
  gs.print("It's using " + myGR.workflow_version.name + " Workflow Version (" + myGR.workflow_version.sys_id + ")");
  var myRecord = new GlideRecord("change_request");
  myRecord.addQuery("sys_id", myGR.id);
  myRecord.query();
  while (myRecord.next()) {
    gs.print('Restarting the Workflow for ' + myRecord.number);
    var w = new Workflow();
    w.cancel(myRecord);
    w.deleteWorkflow(myRecord);
    myRecord.comments = 'Restarting the Workflow via script';
    myRecord.update();
    gs.print("------------------------------------");
  }
}

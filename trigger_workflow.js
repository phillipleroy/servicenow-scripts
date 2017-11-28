var gr = new GlideRecord('wf_workflow');
gr.addQuery('name', 'SC_JRS_SQL');
gr.query();
if (gr.next()) {
  var wf = new Workflow();
  var workflowId = '' + gr.sys_id;
  //var vars = {"u_hostname": "hostname123"};
  wf.startFlow(workflowId);
}

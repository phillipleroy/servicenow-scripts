{
  var gr = new GlideRecord("table");
  //gr.addQuery('vendor', true);
  gr.setWorkflow(false); //Don't fire Business rule,notifications
  gr.deleteMultiple();
}

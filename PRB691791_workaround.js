// This script will go thru all checkpoint entries (svc_model_checkpoint) and verify that if previous_checkpoint is set then
// it points to a valid checkpoint record (possibly corrupted due to bad cascade delete).


// Set this to true to actually repair the records
var repair = false;
// Set this to true to view logging for each record identified and repaired
var debug = false;


var gr = new GlideRecord('svc_model_checkpoint');
gr.query();
gs.log("Total number of records in svc_model_checkpoint table = " + gr.getRowCount());


var impactedRecordCount = 0;
var repairedRecordCount = 0;


while (gr.next()) {
  var prevCheckpoint = gr.getValue('previous_checkpoint');
  if (!gs.nil(prevCheckpoint)) {
    var gr1 = new GlideRecord('svc_model_checkpoint');
    if (!gr1.get(prevCheckpoint)) {
      var recordSysId = gr.getValue('sys_id');
      impactedRecordCount++;
      if (debug) {
        gs.log("Checkpoint Sys Id: " + recordSysId + ". Previous Checkpoint Sys Id: " + prevCheckpoint);
      }

      if (repair) {
        gr.setValue('previous_checkpoint', '');
        if (gr.update()) {
          if (debug) {
            gs.log("Updated previous checkpoint for " + recordSysId);
          }
          repairedRecordCount++;
        }
      }
    }
  }
}


gs.log("Total number of records in svc_model_checkpoint table with non-existent previous checkpoint value = " + impactedRecordCount);
gs.log("Total number of records in svc_model_checkpoint that were repaired = " + repairedRecordCount);

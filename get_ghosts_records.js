// Author: david.piper@servicenow.com
// PRB607155 PRB600448
gs.print(“Starting: Search CMDB
  for Ghost records and Broken References.”);
gs.sql(“select count( * ), sys_class_name, name FROM cmdb_ci where sys_class_name not in (select d.name from sys_dictionary d where d.internal_type = ‘collection’) group by sys_class_name”);
var extensions = “”;
var tab = new GlideRecord(‘sys_db_object’);
tab.orderBy(‘name’);
tab.query();
while (tab.next()) {
  extensions = “”;
  if (isCiTable(tab.name)) {
    gs.print(“ === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === “);
    gs.print(“ === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === === “);
    gs.print(tab.name);
    gs.print(“Extends: “+extensions + “.”);
    gs.print(“———————————————————————————————————————————————————————————————“);
    gs.print(“Checking‘” + tab.name + “’records are in ‘cmdb_ci’.”);
    gs.sql(“SELECT COUNT( * ) FROM `” + tab.name + “`
      WHERE `sys_id`
      NOT IN(SELECT `sys_id`
        FROM `cmdb_ci`);”);
    gs.print(“Checking‘ cmdb_ci’ records of sys_class_name = “+tab.name + “are in table‘” + tab.name + “’.”);
    gs.sql(“SELECT COUNT( * ) FROM `cmdb_ci`
      WHERE `sys_class_name` = ‘”+tab.name + ”’AND `sys_id`
      NOT IN(SELECT `sys_id`
        FROM `” + tab.name + “`);”);
    //          gs.print(“Record Count in this table (including records in extending tables).”);
    //          gs.sql(“SELECT COUNT(*) FROM `”+ tab.name + “`;”);
    //          gs.print(“Record Count in ‘cmdb_ci’ with this class only.”);
    //          gs.sql(“SELECT COUNT(*) FROM `cmdb_ci` WHERE `sys_class_name`=‘” + tab.name + “’;”);
    /*          // spot missing references in this table
                var dic = new GlideRecord(“sys_dictionary”);
                dic.addQuery(“name”, tab.name);
                dic.addQuery(“internal_type”, “reference”);
                dic.orderBy(‘name’);
                dic.query();
                if (dic.getRowCount() > 0) {
                        gs.print(“———————————————————————————————————————————————————————————————“);
                        gs.print(“Checking for missing references.”);
                }
                while (dic.next()) {
                        //gs.print(“Running: SELECT * FROM “ + tab.name + “ WHERE  “ + dic.element + “ != NULL AND “ + dic.element + “ NOT IN (SELECT sys_id FROM “ + dic.reference + “);”);
                        gs.sql(“SELECT `sys_id`, `” + dic.element + “` FROM `” + tab.name + “` WHERE `” + dic.element + “` != NULL AND `” + dic.element + “` NOT IN (SELECT `sys_id` FROM `” + dic.reference + “`);”);
                }
    */
  }
}
gs.print(“Ending: Search CMDB
  for Ghost records“ + tab.name);

function isCiTable(table) {
  if (table == “cmdb_ci”) return true;
  var tab = new GlideRecord(‘sys_db_object’);
  if (tab.get(‘name’, table)) {
    if (tab.super_class.name == ‘cmdb_ci’) {
      extensions = “cmdb_ci” + extensions;
      return true;
    } else if (isCiTable(tab.super_class.name)) {
      extensions = tab.super_class.name + “ -“ +extensions;
      return true;
    } else {
      return false;
    }
  }
  return false;
}

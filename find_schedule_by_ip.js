findThatSchedule("the_ip_address", false);

function findThatSchedule(ip_search, doDebug) {
  var ip_addresses = ip_search.split(","); // Used to handle multiple inputs

  for (var ipIndex = 0; ipIndex < ip_addresses.length; ipIndex++) {
    var foundSchedules = [],
      ip_address = ip_addresses[ipIndex];

    debug("\nLooking for '" + ip_address + "' \n", true);

    checkList(); // Step 1 - for Range Items of type IP Address List
    checkRange(); // Step 2 - for Range Items of type IP Address Range
  }

  function checkList() {
    debug("Checking for Schedules where this IP Address is listed", doDebug);

    var disco_range_item = GlideRecord("discovery_range_item");
    var item_ip = disco_range_item.addJoinQuery("discovery_range_item_ip"); // sub queries, yay!

    disco_range_item.addQuery("active", "true");
    item_ip.addCondition("ip_address", ip_address);

    disco_range_item.query();

    if (disco_range_item.hasNext()) {
      debug(" Schedules found using '" + ip_address + "' in the list", true);
    }

    while (disco_range_item.next()) {
      debug("> " + disco_range_item.getDisplayValue("schedule"), true);
      foundSchedules.push(disco_range_item.getValue(“schedule”));
      debug(“ > Array of found schedules growing to“ + foundSchedules.length, doDebug);
    }
  }

  function checkRange() {
    debug(“Checking
      for Schedules where this IP Address is in the range”, doDebug);
    var dry = new GlideRecord(“discovery_range_item”);
    dri.addEncodedQuery(“active = true ^ type = IP Address Range”);
    dri.query();

    while (dri.next()) {
      if (!scheduleExists(dri.getValue(“schedule”))) {
        //If this schedule was already found in the previous step, save your time and skip
        var type = dri.getValue(“type”),
          start_ip = dri.getValue(“start_ip_address”),
          end_ip = dri.getValue(“end_ip_address”);

        // Will do string comparisons so using RegEx to remove the ‘.’ from the IP Addresses
        start_ip = start_ip.replace(/\./g, “”);
        end_ip = end_ip.replace(/\./g, “”);
        clean_ip_address = ip_address.replace(/\./g, “”);
        debug(“Start IP: “+start_ip, doDebug);
        debug(“End IP: “+end_ip, doDebug);
        debug(“Search IP: “+clean_ip_address, doDebug);

        if (clean_ip_address >= start_ip && clean_ip_address <= end_ip) {
          debug(“Schedule: “+dri.getDisplayValue(“schedule”) + “with‘” + ip_address + “’ in the range”, true);
        }
      }
    }
  }

  function scheduleExists(schedule_id) {
    debug(“Checking
      if schedule‘” + schedule_id + “’already exists in the list of found schedules”, doDebug);
    var found = false;

    for (var i = foundSchedules.length - 1; i >= 0; i—) {
      if (foundSchedules[i] == schedule_id) {
        debug(“ > Yep”, doDebug)
        found = true;
        break;
      }
    }

    return found;
  }

  function debug(message, doDebug) {
    // ‘buff said
    if (doDebug) {
      gs.print(message);
    }
  }
}

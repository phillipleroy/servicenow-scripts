/*

 This script fixes the issue seen on TASK277553.
 Related to PRB1239850. Don't provide the script to customers and make sure the issue is indeed the one mentioned in PRB.

*/

(function() {

        var debug =false;
        var debugQueue =false;

        //    var waitTimeBetweenImapctJobCheck = 10*1000;
        var waitTimeBetweenImapctJobCheck = 3000;

        var maxQueueIterations = 1000000;
        //var maxQueueIterations = 1000;


   function isDoneJobImpactCalc() {
        var grSaHashProgress = new GlideRecord("sa_hash");
        grSaHashProgress.addQuery("name","in_progress_impact");
        grSaHashProgress.query();
        grSaHashProgress.next();
        var progress = grSaHashProgress.getValue("hash");

        var grSaHashCalc = new GlideRecord("sa_hash");
        grSaHashCalc.addQuery("name","last_calculated_impact");
        grSaHashCalc.query();
        grSaHashCalc.next();
        var lastCalculated = grSaHashCalc.getValue("hash");
        if (progress == lastCalculated) {
            return true;
        }
        return false;
    }

    function wait(ms) {
        var start = new Date().getTime(), expire = start + ms;
        while (new Date().getTime() < expire) { }
        return isDoneJobImpactCalc();
    }

    function setImpactEnabled(value) {
         var grSaHash = new GlideRecord("sa_hash");
        grSaHash.addQuery("name","impact_calculation_enable");
        grSaHash.query();
        grSaHash.next();
        grSaHash.setValue("hash",value);
        grSaHash.update();

    }

    function waitTillImpactJobFinished() {
        //wait for 10 seconds each and at most 5 min
        var counter =0;
        while ((counter < 30)&&(!wait(waitTimeBetweenImapctJobCheck))) {
            counter++;
        }
        if (counter ==30) {
            gs.error("Impact job can't be disables, check impact");
            return;
        }
        else {
            gs.log("finishedSleepAfter " + counter + " iterations");
        }
    }

    function getServicesToGroups(){
        var bsToGroup = {};
        var grServiceRelation = new GlideRecord('sa_service_group_member');
        grServiceRelation.query();
        while(grServiceRelation.next()) {
            if (!(bsToGroup[grServiceRelation.service])) {
                bsToGroup[grServiceRelation.service] = {};
            }
            (bsToGroup[grServiceRelation.service])[grServiceRelation.service_group] ={};
        }
        return bsToGroup;
    }

    function initGroupObject() {
        return {critical : 0, major : 0, minor : 0, warning : 0};
    }

    function addSeverityToGroup(group, allGroupStatuses, newSeverity) {

        if (debug)
            gs.log("adding severity " + newSeverity + " to group " +group);

        var currentGroupStatus = allGroupStatuses[group];
        if (!(allGroupStatuses[group])) {
            currentGroupStatus = initGroupObject();
            allGroupStatuses[group] = currentGroupStatus;
        }

        addSeverityToSeveritiesVector(currentGroupStatus, newSeverity,group);
    }

    function addSeverityToSeveritiesVector(currentGroupStatus, newSeverity,ci) {

        if ((newSeverity < 0) || (newSeverity > 4))
            return;

        if (newSeverity == 1)
            currentGroupStatus.critical++;

        if (newSeverity <= 2)
            currentGroupStatus.major++;

        if (newSeverity <= 3)
            currentGroupStatus.minor++;

        if (newSeverity <= 4)
            currentGroupStatus.warning++;

    }

    function addSeverityToGroups(groupsToAddTo, allGroupStatuses, newSeverity) {
        if (groupsToAddTo) {
            for (var group in groupsToAddTo) {
                addSeverityToGroup(group, allGroupStatuses, newSeverity);
            }
        }
    }

    function printAllGroupsStatuses(allGroupStatuses) {
        if (debug) {
            for (var group in allGroupStatuses) {
                gs.log("group " + group + " vector is= (1:" + allGroupStatuses[group].critical  + ",2:"+allGroupStatuses[group].major+ ",3:"+allGroupStatuses[group].minor+ ",4:"+allGroupStatuses[group].warning+")");
            }
        }
    }

    function addGroupsToParentMap(groupsToParent, parentsToGroups) {
        var groupsGR = new GlideRecord("cmdb_ci_service_group");
        groupsGR.query();
        while(groupsGR.next()) {
            groupsToParent[groupsGR.sys_id] = groupsGR.parent_group + "";
            var sonsArray = parentsToGroups[groupsGR.parent_group];
            if (!sonsArray) {
                sonsArray = {};
                parentsToGroups[groupsGR.parent_group] = sonsArray;
            }
            sonsArray[groupsGR.sys_id] = {};
        }
    }

    function checkGroupInQueue(queue, group) {
        for (var i = 0; i < queue.length; i++) {
            if (queue[i] === group)
                return true;
        }
        return false;
    }

    function addAllParentsOfChangedGroupsToQueue(groupStatuses, groupsToParent, queue){
        for (var group in groupStatuses) {
            var parent = groupsToParent[group];
            if (parent) {
                if (!(checkGroupInQueue(queue, parent))) {
                    var sizeBeforePush = queue.length;
                    queue.push(parent);

                    if (debugQueue)
                        gs.log(queue[parent]+",Pusing allParents to queue group " + parent + ", size of queue before push is: " + sizeBeforePush +" and afer is " +queue.length);
                }
            }
            else {
                gs.log("Group " + group + " has no parents.");
            }

            //Add original service severity values
            groupStatuses[group].servicesSeverities = {};
            groupStatuses[group].servicesSeverities.critical = groupStatuses[group].critical;
            groupStatuses[group].servicesSeverities.major = groupStatuses[group].major;
            groupStatuses[group].servicesSeverities.minor = groupStatuses[group].minor;
            groupStatuses[group].servicesSeverities.warning = groupStatuses[group].warning;
        }
    }

    function printGroupsToParent(groupsToParent) {
        if (debug) {
            gs.log("GroupsToParent is:");

            for (var g in groupsToParent) {
                gs.log(groupsToParent[g] + ",");
            }
        }
    }

    function updateSeveritiesByQueue(queue, parentsToGroups, groupsToParent, groupStatuses){

        var counter =0;
        while (queue.length > 0 && (counter <= maxQueueIterations)) {
            counter++;
            var sizeBeforePop = queue.length;
            var group = queue.shift(); //shift is pop first

            if (debugQueue)
                gs.log("Poping from queue group " + group + ", size of queue before pop is: " + sizeBeforePop +" and after is " +queue.length);

            var currentGroupStatus = groupStatuses[group];
            if (!currentGroupStatus) {
                groupStatuses[group] = initGroupObject();
                currentGroupStatus = groupStatuses[group];
            }
            var orgSeverity = getSeverity(currentGroupStatus);

            //calc vector by sons groups
            var tempVector = initGroupObject();
            var sons = parentsToGroups[group];
            for (var son in sons) {
                var sonSeverity = getSeverity(groupStatuses[son]);
                addSeverityToSeveritiesVector(tempVector, sonSeverity);
            }

            //update vector by services severities
            if (currentGroupStatus.servicesSeverities) {
                tempVector.critical += currentGroupStatus.servicesSeverities.critical;
                tempVector.major += currentGroupStatus.servicesSeverities.major;
                tempVector.minor += currentGroupStatus.servicesSeverities.minor;
                tempVector.warning += currentGroupStatus.servicesSeverities.warning;
            }

            //update group vector to cuurent severities
            currentGroupStatus.critical = tempVector.critical;
            currentGroupStatus.major = tempVector.major;
            currentGroupStatus.minor = tempVector.minor;
            currentGroupStatus.warning = tempVector.warning;

            //If severity had changed - parents need to be updated as well
            //if (orgSeverity !== getSeverity(group)) {
                var parent = groupsToParent[group];
                if (parent) {
                    //if (!(checkGroupInQueue(queue, parent))) {
                        var sizeBeforePush = queue.length;
                        queue.push(parent);

                        if (debugQueue)
                            gs.log("Pusing to queue group " + parent + ", size of queue before push is: " + sizeBeforePush +" and after is " +queue.length);
                    //}
                }
            //}
        }

        if (counter >= maxQueueIterations) {
            gs.error("More then " + maxQueueIterations + " iterations on the queue, stopping processing");
            return;
        }
    }

    // function updateGroupsByServices(bsToGroup, groupStatuses) {
    //     var services = new GlideRecord("cmdb_ci_service_auto");
    //     services.addQuery("operational_status","1");
    //     services.addQuery("severity", ">", "0");
    //     services.addQuery("severity", "<", "5");
    //     services.query();
    //     while(services.next()) {
    //         if (debug) {
    //             gs.log("severity of bs " + services.sys_id + " is " + services.severity);
    //         }

    //         addSeverityToGroups(bsToGroup[services.sys_id], groupStatuses, services.severity);
    //     }
    // }

    function updateGroupsByServices(bsToGroup, groupStatuses) {
        // var services = new GlideRecord("cmdb_ci_service_auto");
        // services.addQuery("operational_status","1");
        // services.addQuery("severity", ">", "0");
        // services.addQuery("severity", "<", "5");
        // services.query();

        var services = new GlideRecord("cmdb_ci_service_auto");
        services.addQuery("operational_status",1);
        services.query();
        var serviceIDS={};
        while(services.next()){
            if (debug) {
                gs.log("---- service_id" + services.sys_id);
            }
            serviceIDS[services.sys_id]="";
        }
        var service_idsLst = Object.keys(serviceIDS).join();
        if (debug) {
            gs.log( " 88 - service_idsLst " + service_idsLst);
}
        var grImpactStatus = new GlideRecord("em_impact_status");
        grImpactStatus.addQuery("vt_end",">=",gs.daysAgoEnd(0));
        grImpactStatus.addQuery("element_id","IN",service_idsLst);
        grImpactStatus.query();

        while(grImpactStatus.next()) {
            if (debug) {
                gs.log("severity of bs " + grImpactStatus.business_service +" element id "+ grImpactStatus.element_id+" is " + grImpactStatus.severity);
            }

            if (grImpactStatus.element_id == grImpactStatus.business_service) {
                addSeverityToGroups(bsToGroup[grImpactStatus.element_id], groupStatuses, grImpactStatus.severity);
            }
            else {
                if (debug) {
                    gs.log("Element " + grImpactStatus.element_id +" is a connected service, not severity of the bs id "+ grImpactStatus.business_service);
                }
            }
        }
    }

    function getSeverity(group) {
        //only save real severities
        if (group.critical >0)
            return 1;
        else if (group.major >0)
            return 2;
        else if (group.minor >0)
            return 3;
        else if (group.warning >0)
            return 4;

        return 5;
    }

    function updateRecordWithSeverities(grImpactStatus, group){
            var contribution_vector_of_children = '{"1":' + group.critical*100  + ',"2":'+group.major*100+ ',"3":'+group.minor*100+ ',"4":'+group.warning*100+'}';
            grImpactStatus.setValue("contribution_vector_of_children",contribution_vector_of_children);
            grImpactStatus.setValue("dirty",false);
            grImpactStatus.setValue("force_parent_update",false);
            grImpactStatus.setValue("severity",getSeverity(group));
            grImpactStatus.setValue("self_severity","-1");
            grImpactStatus.setValue("contributed_severity",getSeverity(group));
    }

    function saveGroupsToDB(groupStatuses) {
        var group;
        var updatedGroups = {};

        var grImpactStatus = new GlideRecord("em_impact_status");
        grImpactStatus.addNullQuery("business_service");
        grImpactStatus.addQuery("vt_end",">=",gs.daysAgoEnd(0));
        grImpactStatus.query();
        while(grImpactStatus.next()) {
            group = groupStatuses[grImpactStatus.element_id];
            if (!group) {
                group = initGroupObject();
            }

            updateRecordWithSeverities(grImpactStatus, group);

            //deduplicated mulitple open records, if allready updated the group- close the record
            if (updatedGroups[grImpactStatus.element_id]) {
                gs.log("Closing duplicate impact_status " + grImpactStatus.sys_id + " for group " + grImpactStatus.element_id);
                grImpactStatus.setValue("vt_end",grImpactStatus.vt_start + "");
            }

            grImpactStatus.update();


            updatedGroups[grImpactStatus.element_id] = {};
        }

        //get a dummy record to use for new inserts
        grImpactStatus = new GlideRecord("em_impact_status");
        grImpactStatus.addQuery("vt_end",">=",gs.daysAgoEnd(0));
        grImpactStatus.query();
        grImpactStatus.next();

        for (group in groupStatuses) {
            if (!(updatedGroups[group])) {
                if (debug) {
                    gs.log("gsroup " + group + " hadn't had any record in impact status but do have a severity, cerate a new record.");
                }

                updateRecordWithSeverities(grImpactStatus, groupStatuses[group]);
                grImpactStatus.setValue("element_id",group);
                grImpactStatus.setValue("business_service","");
                grImpactStatus.setValue("ns_path","");
                grImpactStatus.setValue("business_service","");
                grImpactStatus.insert();

            }
        }
    }

    function deleteImpactGroupRel() {
    var counter = 0;
        var relGR = new GlideRecord("em_group_impact_relations");
        relGR.query();
        while (relGR.next()) {
                        counter++;
                        relGR.deleteRecord();
        }

        if (debug) {
            gs.log("Delete " + counter+ " records on em_group_impact_relations");
        }
    }

    function main() {
        gs.log("Started Script");

        setImpactEnabled("false");
        waitTillImpactJobFinished(waitTimeBetweenImapctJobCheck);
        var bsToGroup = getServicesToGroups();

        gs.log("There are " + Object.keys(bsToGroup).length + " bs");
        for (var bs in bsToGroup) {
            gs.log("bs " + bs + " has " + Object.keys(bsToGroup[bs]).length  + " groups.");
        }

        deleteImpactGroupRel();

        var groupStatuses = {}; //{groupId = {critical=0, major=0, minor=0, warning=0, }}
        updateGroupsByServices(bsToGroup, groupStatuses);

        printAllGroupsStatuses(groupStatuses);

        saveGroupsToDB(groupStatuses);

        //get groups hierarchical
        var groupsToParent = {};
        var parentsToGroups =  {};
        addGroupsToParentMap(groupsToParent, parentsToGroups);
        var queue = [];
        addAllParentsOfChangedGroupsToQueue(groupStatuses, groupsToParent, queue);

        updateSeveritiesByQueue(queue, parentsToGroups, groupsToParent, groupStatuses);

        printAllGroupsStatuses(groupStatuses);
        saveGroupsToDB(groupStatuses);

        //set hash to true;
        setImpactEnabled("true");
        gs.log("Ended Script");
    }

    main();
    })();

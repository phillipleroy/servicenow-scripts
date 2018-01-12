/*
In INT3554415, The customer was willing to cancel 1500 Cloud Resource Discovery Statuses automatically without impacting the instance performance.
I worked with David on the following script to achieve the customer requirement.
The script will query discovery_status table for the active and starting Cloud Resource discovery statuses and will return only the matching first 10 discovery statuses. Then the customer used the script in a scheduled job that runs every 15 minutes which will divide the cancellation into batches.
*/

var discogr = new GlideRecord('discovery_status'); // Defining the targeted table, It is a best practice to use a different variable name instead of gr

discogr.addEncodedQuery('state=Active^ORstate=Starting^discover=Cloud Resources'); // It’s better to use addEncodedQuery function with the query itself instead of using addQuery and then combine it if conditions.

//Limiting the returned discovery statuses to 10 at a script run
discogr.setLimit(10);

//Running the limited query
discogr.query();

// The while loop will iterate on the returned 10 discovery statuses or maybe less than 10 with the last run of the script.
while (discogr.next()) {
  // This line will print something like >> Cancelling Discovery Status 4dbb5559db368700f601f3d31d96195d
  gs.print('Cancelling Discovery Status ' + discogr.sys_id);

  // We used the following 2 lines from the UI action ‘Cancel Discovery Status’ as advised by Rahul
  // declaring a new object called test_dac from OOB SncDiscoveryCancel class
  var test_dac = new SncDiscoveryCancel();

  //cancelAll() function from SncDiscoveryCancel class will run against the current sys_id of the iterated discovery status.
  test_dac.cancelAll(discogr.sys_id);
}

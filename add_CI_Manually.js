var payload = {
    items: [{
        className: ‘cmdb_ci_computer’,
        values: {
            name: ‘leroy-2’,
            serial_number: ‘VMware-56 4d bf 26 47 c1 68 58-9e 9a a9 a8 c2 70 ad fe’,
            ip_address: ‘172.16.58.130’,
            ram: ‘2580’
        }
    }]
};
var input = new JSON().encode(payload);
var output = SNC.IdentificationEngineScriptableApi.createOrUpdateCI(‘ServiceNow’, input);
gs.print(output);

@IsTest
private class SmartSyncServiceTest {

    // Define Mock class FIRST
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();

            if (endpoint.contains('/services/oauth2/token')) {
                res.setHeader('Content-Type', 'application/json');
                res.setStatusCode(200);
                res.setBody('{"access_token": "mocked_crm_access_token", "instance_url": "https://mocked.crm.instance"}');
            } else if (endpoint.contains('/services/a360/token')) {
                res.setHeader('Content-Type', 'application/json');
                res.setStatusCode(200);
                res.setBody('{"access_token": "mocked_dc_access_token", "instance_url": "mocked.dc.instance"}');
            } else if (endpoint.contains('/api/v1/insight')) {
                res.setHeader('Content-Type', 'application/json');
                res.setStatusCode(200);
                res.setBody('{"data":"mocked insight data"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":"Unknown endpoint"}');
            }

            return res;
        }
    }

    // Valid test method using the mock
    @IsTest
    static void testGetAllCioMetadata() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        SmartSyncService.getAllCioMetadata();
        Test.stopTest();
    }

    @IsTest
    static void testGetDataOfCio() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        SmartSyncService.getDataOfCio('Accounts_with_Unified_Details__cio');
        Test.stopTest();
    }

    @IsTest
    static void testGetDataOfCioWithBlankInput() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        SmartSyncService.getDataOfCio('');
        Test.stopTest();
    }
}
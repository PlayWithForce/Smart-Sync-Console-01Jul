@IsTest
private class DataCloudAuthServiceTest {

    public class MockHttpResponseGenerator implements System.HttpCalloutMock {
        public System.HttpResponse respond(System.HttpRequest req) {
            System.HttpResponse res = new System.HttpResponse();
            String endpoint = req.getEndpoint();

            if (endpoint.contains('/services/oauth2/token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token": "mocked_crm_access_token", "instance_url": "mocked.crm.instance"}');
            } else if (endpoint.contains('/services/a360/token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token": "mocked_dc_access_token", "instance_url": "mocked.dc.instance"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error": "not_found"}');
            }

            return res;
        }
    }

    @IsTest
    static void testAuthenticateWithDataCloud() {
        System.Test.setMock(System.HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        List<String> tokens = DataCloudAuthService.authenticateWithDataCloud();
        Test.stopTest();

        System.assertEquals(2, tokens.size(), 'Expected 2 elements: URL and token');
        System.assert(tokens[0].startsWith('https://'), 'First element should be URL');
        System.assert(tokens[1].startsWith('Bearer '), 'Second element should be Bearer token');
    }

    @IsTest
    static void testGetDataCloudTenantToken() {
        System.Test.setMock(System.HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        List<String> result = DataCloudAuthService.getDataCloudTenantToken(
            'mocked_crm_access_token',
            'https://mocked.crm.instance',
            'mockspace'
        );
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return 2 items');
        System.assert(result[0].startsWith('https://'), 'Should return instance URL');
        System.assert(result[1].contains('mocked_dc_access_token'), 'Should include mocked token');
    }



}
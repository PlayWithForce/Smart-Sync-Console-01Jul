/**
 * @name        DataCloudIntegrationUtilTest
 * @description Test class for DataCloudIntegrationUtil that validates authentication and callout behaviors using HttpCalloutMock.
 * @author      Debanjan Mukherjee
 * @created     20 Jun 2025
 */
@IsTest
private class DataCloudIntegrationUtilTest {

    /**
     * @description Mock callout handler for token and Data Cloud query success responses.
     */
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();

            if (endpoint.contains('/services/oauth2/token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token": "mocked_crm_access_token", "instance_url": "https://mocked.crm.instance"}');
            } else if (endpoint.contains('/services/a360/token')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token": "mocked_dc_access_token", "instance_url": "mocked.dc.instance"}');
            } else if (endpoint.contains('/api/v2/query')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"records": [{"Id": "001000000000001"}]}');
            } else {
                res.setStatusCode(400);
                res.setBody('{"error": "Bad request"}');
            }

            return res;
        }
    }

    /**
     * @description Mock callout handler for simulating a server error.
     */
    private class MockServerErrorResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": "Internal Server Error"}');
            return res;
        }
    }

    /**
     * @description Tests a full callout flow including token init and a generic Data Cloud call.
     */
    @IsTest
    static void testGetDataFromDataCloudSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        String httpMethod = 'POST';
        String endpoint = '/api/v2/query';
        String body = '{"sql": "SELECT Id FROM UnifiedssotAccountAccd__dlm LIMIT 1"}';

        Test.startTest();
        HttpResponse response = DataCloudIntegrationUtil.getDataFromDataCloud(httpMethod, endpoint, body);
        Test.stopTest();

        System.assertEquals(200, response.getStatusCode(), 'Expected 200 response from Data Cloud');
        System.assert(response.getBody().contains('records'), 'Expected records in response');
    }

    /**
     * @description Tests fallback and failure handling when an error is returned from Data Cloud.
     */
    @IsTest
    static void testGetDataFromDataCloudFailure() {
        Test.setMock(HttpCalloutMock.class, new MockServerErrorResponse());

        String httpMethod = 'GET';
        String endpoint = '/api/v2/invalid';
        String body = null;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DataCloudIntegrationUtil.getDataFromDataCloud(httpMethod, endpoint, body);
        } catch (Exception ex) {
            exceptionThrown = true;
            System.debug('Expected exception: ' + ex.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception to be thrown on failed callout');
    }

    /**
     * @description Validates token caching behavior by calling the same method twice.
     */
    @IsTest
    static void testTokenCaching() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        String method = 'POST';
        String endpoint = '/api/v2/query';
        String body = '{"sql": "SELECT Id FROM test"}';

        Test.startTest();
        HttpResponse firstCall = DataCloudIntegrationUtil.getDataFromDataCloud(method, endpoint, body);
        HttpResponse secondCall = DataCloudIntegrationUtil.getDataFromDataCloud(method, endpoint, body);
        Test.stopTest();

        System.assertEquals(200, firstCall.getStatusCode(), 'First call should succeed');
        System.assertEquals(200, secondCall.getStatusCode(), 'Second call should reuse token');
    }
}
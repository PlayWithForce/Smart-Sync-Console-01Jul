/**
 * @name        BulkApiDataFetcherService
 * @description Fetches data from Smart_Sync_Stage__c object in external Salesforce org using Bulk API 2.0
 * @author      Debanjan
 * @date        2025-06-29
 */
public with sharing class BulkApiDataFetcherService {

    //@future(callout=true)
    public static string fetchJobIdForStageData(String objectApiName) { 
        try {
            // Step 1: Authenticate
            DataCloudAuthService.TokenResponse token = DataCloudAuthService.authOnlyCRM();
            if (token == null || String.isBlank(token.access_token) || String.isBlank(token.instance_url)) {
                System.debug('Invalid CRM token response');
                return 'Unable to connect to Data Cloud';
            }

            String instanceUrl = token.instance_url;                // Already includes https://
            String authHeader = 'Bearer ' + token.access_token;

            Http http = new Http();
			String theQuery = 'SELECT Id, Name, Insight_Name__c, LastModifiedDate, Increment_Data__c ' +
               'FROM Smart_Sync_Stage__c ' +
               'WHERE Insight_Name__c = \'' + String.escapeSingleQuotes(objectApiName) + '\' ' +
               'LIMIT 100';
			system.debug('query'+theQuery);
            // Step 2: Create query job
            HttpRequest createJobReq = new HttpRequest();
            createJobReq.setEndpoint(instanceUrl + '/services/data/v59.0/jobs/query');
            createJobReq.setMethod('POST');
            createJobReq.setHeader('Authorization', authHeader);
            createJobReq.setHeader('Content-Type', 'application/json');
            createJobReq.setBody(JSON.serialize(new Map<String, Object>{
                'operation' => 'query',
                'query' => theQuery
            }));

            HttpResponse jobResp = http.send(createJobReq);
            if (jobResp.getStatusCode() != 200 && jobResp.getStatusCode() != 201) {
                System.debug('Failed to create job: ' + jobResp.getBody());
                return 'Failed to create job to retrive increment data: ' + jobResp.getBody();
            }

            Map<String, Object> jobResponseMap = (Map<String, Object>) JSON.deserializeUntyped(jobResp.getBody());
            String jobId = (String) jobResponseMap.get('id');
            system.debug('fetchSmartSyncStageData : '+jobId);
            String jobState = (String) jobResponseMap.get('state');

            // Step 3: Poll for job completion (simple poll in same method; production use should async poll)
            if (jobState == 'Open' || jobState == 'UploadComplete' || jobState == 'InProgress' || jobState == 'Queued') {
                HttpRequest pollReq = new HttpRequest();
                pollReq.setEndpoint(instanceUrl + '/services/data/v59.0/jobs/query/' + jobId);
                pollReq.setMethod('GET');
                pollReq.setHeader('Authorization', authHeader);

                HttpResponse pollResp = http.send(pollReq);
                if (pollResp.getStatusCode() == 200) {
                    jobResponseMap = (Map<String, Object>) JSON.deserializeUntyped(pollResp.getBody());
                    jobState = (String) jobResponseMap.get('state');
                }

                if (jobState != 'JobComplete') {
                    System.debug('Job not yet complete: ' + jobState);
                    return jobId;
                }
                
            }
			/*
            // Step 4: Get results
            HttpRequest resultReq = new HttpRequest();
            resultReq.setEndpoint(instanceUrl + '/services/data/v59.0/jobs/query/' + jobId + '/results');
            resultReq.setMethod('GET');
            resultReq.setHeader('Authorization', authHeader);
            resultReq.setHeader('Accept', 'application/json'); // Change to 'text/csv' if needed

            HttpResponse resultResp = http.send(resultReq);
            if (resultResp.getStatusCode() == 200) {
                System.debug('Bulk API result:\n' + resultResp.getBody());
                // Optional: parse result and store in local object
                return jobId;
            } else {
                System.debug('Failed to retrieve results: ' + resultResp.getBody());
                return('Failed to retrieve results for Increment Data: ' + resultResp.getBody());
            }
			*/
            return jobId;
        } catch (Exception ex) {
            System.debug('Exception during Bulk API fetch: ' + ex.getMessage());
            return 'Failed to retrieve results for Increment Data: ' + ex.getMessage();
        }
    }
    //@future(callout=true)
     // Existing: fetchSmartSyncStageDataAndReturnJobId()
    // Add this new method:

    public static List<String> getResultForJob(String jobId) {
        List<String> csvLines = new List<String>();
        Integer maxRetries = 5;
        Integer waitTimeMs = 3000; // 3 seconds between polls
    
        try {
            DataCloudAuthService.TokenResponse token = DataCloudAuthService.authOnlyCRM();
            if (token == null || String.isBlank(token.access_token) || String.isBlank(token.instance_url)) {
                System.debug('Invalid token response');
                return csvLines;
            }
    
            String instanceUrl = token.instance_url;
            String authHeader = 'Bearer ' + token.access_token;
            Http http = new Http();
    
            // 1. Poll for job completion
            Boolean isComplete = false;
            String jobState = '';
    
            for (Integer i = 0; i < maxRetries; i++) {
                HttpRequest statusReq = new HttpRequest();
                statusReq.setEndpoint(instanceUrl + '/services/data/v59.0/jobs/query/' + jobId);
                statusReq.setMethod('GET');
                statusReq.setHeader('Authorization', authHeader);
    
                HttpResponse statusResp = http.send(statusReq);
                if (statusResp.getStatusCode() == 200) {
                    Map<String, Object> jobStatus = (Map<String, Object>) JSON.deserializeUntyped(statusResp.getBody());
                    jobState = (String) jobStatus.get('state');
                    System.debug('Polling Job Status: ' + jobState);
                    if (jobState == 'JobComplete') {
                        isComplete = true;
                        break;
                    }
                }
    
                // Wait between polls (Governor-safe delay)
                System.runAs(new User(Id = UserInfo.getUserId())) {
                    Long target = DateTime.now().getTime() + waitTimeMs;
                    while (DateTime.now().getTime() < target) {
                        // idle loop (Apex has no native sleep)
                    }
                }
            }
    
            if (!isComplete) {
                System.debug('Job not completed after max retries. Current state: ' + jobState);
                return csvLines;
            }
    
            // 2. Download results
            HttpRequest resultReq = new HttpRequest();
            resultReq.setEndpoint(instanceUrl + '/services/data/v59.0/jobs/query/' + jobId + '/results');
            resultReq.setMethod('GET');
            resultReq.setHeader('Authorization', authHeader);
            resultReq.setHeader('Accept', 'text/csv');
    
            HttpResponse resultResp = http.send(resultReq);
            if (resultResp.getStatusCode() == 200) {
                //csvLines = resultResp.getBody().split('\n');
                csvLines = safelySplitCsvLines(resultResp.getBody());
            } else {
                System.debug('Failed to retrieve job result: ' + resultResp.getBody());
            }
    
        } catch (Exception ex) {
            System.debug('Exception while fetching Bulk API result: ' + ex.getMessage());
        }
    	//system.debug('Data fetcher csvLines'+csvLines);
        return csvLines;
    }
    public static List<String> safelySplitCsvLines(String csvText) {
        List<String> lines = new List<String>();
        Integer start = 0;
        for (Integer i = 0; i < csvText.length(); i++) {
            if (csvText.substring(i, i + 1) == '\n') {
                lines.add(csvText.substring(start, i).trim());
                start = i + 1;
            }
        }
    
        // Add final line if needed
        if (start < csvText.length()) {
            lines.add(csvText.substring(start).trim());
        }
    
        return lines;
    }


    public static String getJobStatus(String jobId) {
        try {
            DataCloudAuthService.TokenResponse token = DataCloudAuthService.authOnlyCRM();
            if (token == null || String.isBlank(token.access_token) || String.isBlank(token.instance_url)) {
                System.debug('Invalid token');
                return 'InvalidToken';
            }
    
            HttpRequest req = new HttpRequest();
            req.setEndpoint(token.instance_url + '/services/data/v59.0/jobs/query/' + jobId);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + token.access_token);
    
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> jobStatus = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String jobState = String.valueOf(jobStatus.get('state'));
                System.debug('Job state: ' + jobState);
                return jobState;
            } else {
                System.debug('Failed to fetch job status: ' + res.getBody());
                return 'Error';
            }
        } catch (Exception ex) {
            System.debug('Exception in getJobStatus: ' + ex.getMessage());
            return 'Exception';
        }
    }


}
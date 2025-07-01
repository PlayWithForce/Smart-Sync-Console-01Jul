/**
 * @name        SmartSyncService
 * @description Executes Data Cloud API calls by dynamically retrieving endpoint configuration from Custom Metadata records.
 *              Uses only fields that are populated, without throwing errors for missing metadata values.
 * @author      Debanjan Mukherjee
 * @created     20 Jun 2025
 */
public with sharing class SmartSyncService {
	public class MetadataServiceException extends Exception {}
    /**
     * @description Retrieves the Insight metadata from Data Cloud using metadata configuration.
     * SmartSyncService.getAllCioMetadata();
     */
    public static string getAllCioMetadata() {
        return invokeDataCloudCall('Insight_Metadata');
    }

    /**
     * @description Retrieves data for a Calculated Insight using metadata and appends object name to endpoint.
     * @param cioDevName Developer name of the Calculated Insight object (e.g., Accounts_with_Unified_Details__cio)
     */
    public static string getDataOfCio(String cioDevName,String key,integer currOffset) {
        return invokeDataCloudCall('Calculated_Insight', cioDevName,key,currOffset);
    }

    /**
     * @description Generic executor to call Data Cloud endpoints using custom metadata and optional CIO name.
     * @param metadataDevName Developer Name of the metadata record (e.g., Insight_Metadata)
     * @param cioName Optional insight object to append to the endpoint (if applicable)
     */
    private static string invokeDataCloudCall(String metadataDevName, String cioName,String key,integer currOffset) {
        try
        {
            List<SmartSync_Integration_Endpoint__mdt> configList = [
                SELECT DeveloperName, Base_Url__c, Http_Method__c, Synch_Endpoint__c,limit__c,offset__c,orderby__c
                FROM SmartSync_Integration_Endpoint__mdt
                WHERE DeveloperName IN ('Insight_Metadata', 'Calculated_Insight')
            ];

            SmartSync_Integration_Endpoint__mdt selectedConfig;

            for (SmartSync_Integration_Endpoint__mdt config : configList) {
                if (config.DeveloperName == metadataDevName) {
                    selectedConfig = config;
                    break;
                }
            }

            if (selectedConfig == null) {
                System.debug('No configuration found for: ' + metadataDevName);
                return 'No configuration found for: ' + metadataDevName;
            }

            String httpMethod = String.isNotBlank(selectedConfig.Http_Method__c)
                ? selectedConfig.Http_Method__c
                : 'GET';

            String baseUrl = String.isNotBlank(selectedConfig.Base_Url__c)
                ? selectedConfig.Base_Url__c
                : '';

            String endpoint = '';
            if (String.isNotBlank(selectedConfig.Synch_Endpoint__c)) {
                endpoint = selectedConfig.Synch_Endpoint__c;
            }

            if (String.isNotBlank(cioName)) {
                endpoint = endpoint.endsWith('/')
                    ? endpoint + cioName
                    : endpoint + '/' + cioName;
            }

            String fullEndpoint = baseUrl + endpoint;

            if(NULL == currOffset || currOffset==0)
            {
                currOffset=(Integer)selectedConfig.offset__c;
            }
            integer intLimit;
            if(NULL!=selectedConfig.limit__c)
            {
                intLimit = (Integer)selectedConfig.limit__c;
            }
            fullEndpoint = fullEndpoint+'?limit='+intLimit+'&offset='
                +currOffset+'&orderby='+key;
            HttpResponse res = DataCloudIntegrationUtil.getDataFromDataCloud(httpMethod, fullEndpoint, '');

            System.debug('Response Status: ' + res.getStatus());
            System.debug('Response Body: ' + res.getBody());
            return res.getBody();
      	}
        catch(Exception ex)
        {
            throw new MetadataServiceException('Field creation error: ' , ex);
        }
    }

    /**
     * @description Overloaded version for fixed endpoints without dynamic CIO name.
     * @param metadataDevName Developer name of the metadata configuration
     */
    private static string invokeDataCloudCall(String metadataDevName) {
        return invokeDataCloudCall(metadataDevName,null,null,null);
    }
}
public with sharing class CISyncController {
    
    @AuraEnabled(cacheable=true)
    public static List<Calculated_Insight__c> getCalculatedInsights() {
        return [
            SELECT Id, Name, Developer_Name__c, displayName__c, latestProcessTime__c, 
                   latestSuccessfulProcessTime__c, Data_Sync_Done__c, Last_Data_Sync__c,
                   Data_Process_Error__c, Data_Processing_Retry_Interval__c, Metadata_Sync_Done__c
            FROM Calculated_Insight__c
            ORDER BY displayName__c ASC
        ];
    } 

    @AuraEnabled(cacheable=true)
    public static List<Insight_Field__c> getInsightFields(String ciName) {
        return [
            SELECT Id, Name, Calculated_Insight__c, Developer_Name__c,
                   displayName__c, field_type__c,
                   Calculated_Insight__r.displayName__c,
                   Calculated_Insight__r.Developer_Name__c
            FROM Insight_Field__c
            WHERE Calculated_Insight__r.Developer_Name__c = :ciName
            ORDER BY displayName__c ASC
        ];
    }

    @AuraEnabled
    public static void initializeMetadata() {
        Database.executeBatch(new CiMetadataInitBatch(), 1);
    }

    @AuraEnabled
    public static void fullSync(String ciDevName) {
        boolean isSuccess = SmartSyncInitializer.getSelectedCI(ciDevName, 'SmartSyncConsole', 'SmartSyncConsole');
    }

    @AuraEnabled
    public static void incrementalSync(String ciDevName, String fieldDevName) {
        SmartSyncInitializer.getSelectedCI(ciDevName, fieldDevName, 'SmartSyncConsole');
    }
}
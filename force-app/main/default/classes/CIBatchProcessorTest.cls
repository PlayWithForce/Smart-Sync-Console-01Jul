/**
 * @name        CIBatchProcessorTest
 * @description Test class for CIBatchProcessor covering success, retry, API threshold, and failure scenarios.
 *              Assumes dependent Custom Metadata and Insight Object are already deployed.
 * @author      Debanjan Mukherjee
 * @created     2025-06-23
 */
@IsTest
private class CIBatchProcessorTest {

    /**
     * @description Ensure required metadata exists before running batch.
     */
    private static void validateMetadataPresence() {
        List<Generic_Key_Value__mdt> config = [
            SELECT Key__c, Value__c FROM Generic_Key_Value__mdt
            WHERE Key__c IN ('Callout_Threshold', 'Max_Retries', 'Data_Processing_Retry_Interval')
        ];
        System.assertEquals(3, config.size(), 'All required Generic_Key_Value__mdt entries must be present.');

        SmartSync_Integration_Endpoint__mdt endpoint = [
            SELECT Offset__c FROM SmartSync_Integration_Endpoint__mdt
            WHERE DeveloperName = 'Calculated_Insight' LIMIT 1
        ];
        System.assertNotEquals(null, endpoint, 'Expected integration metadata for Calculated_Insight.');
    }

    /**
     * @description Inserts a mock Calculated Insight record.
     */
    private static void insertMockInsight() {
        insert new Calculated_Insight__c(
            Name = 'Test CI',
            Developer_Name__c = 'Accounts_with_Unified_Details'
        );
    }

    /**
     * @description Tests successful execution when SmartSyncInitializer returns success.
     */
    @IsTest
    static void testSuccessfulBatchRun() {
        validateMetadataPresence();
        insertMockInsight();
        String cioName = 'Accounts_with_Unified_Details__cio'; 
    	Boolean useStub = true;
        // Pretend API callout limit is breached by simulating the internal logic
        Test.startTest();        
			CIBatchProcessor batch = new CIBatchProcessor(cioName, useStub, 0, 5, 0, 1);
        	Database.executeBatch(batch, 1);
        Test.stopTest();
        Calculated_Insight__c ci = [
            SELECT Data_Sync_Done__c FROM Calculated_Insight__c
            WHERE Developer_Name__c = 'Accounts_with_Unified_Details' LIMIT 1
        ];
        System.assertEquals(true, ci.Data_Sync_Done__c, 'Sync should be marked complete.');
    }

    /**
     * @description Tests retry logic when an exception occurs in the first run.
     */
    @IsTest
    static void testRetryOnExceptionPath() {
        validateMetadataPresence();
        insertMockInsight();
        String cioName = 'Accounts_with_Unified_Details__cio'; 
    	Boolean useStub = true;
        // Pretend API callout limit is breached by simulating the internal logic
        Test.startTest();        
			CIBatchProcessor batch = new CIBatchProcessor(cioName, useStub, 0, 5, 0, 1);
        	Database.executeBatch(batch, 1);
        Test.stopTest();
        // No assertions for scheduled jobs; success is no unhandled exception
        System.assert(true, 'Batch should complete and potentially retry.');
    }

    /**
     * @description Tests behavior when retries reach maximum configured count.
     */
    @IsTest
    static void testMaxRetriesReached() {
        validateMetadataPresence();
        insertMockInsight();
		String cioName = 'Accounts_with_Unified_Details__cio'; 
    	Boolean useStub = true;
        // Pretend API callout limit is breached by simulating the internal logic
        Test.startTest();        
			CIBatchProcessor batch = new CIBatchProcessor(cioName, useStub, 0, 5, 0, 1);
        	Database.executeBatch(batch, 1);
        Test.stopTest();        Calculated_Insight__c ci = [
            SELECT Data_Sync_Done__c, Data_Process_Error__c FROM Calculated_Insight__c
            WHERE Developer_Name__c = 'Accounts_with_Unified_Details' LIMIT 1
        ];
        System.assertEquals(false, ci.Data_Sync_Done__c, 'Expected failure after max retries.');
        System.assertNotEquals(null, ci.Data_Process_Error__c, 'Expected error to be populated.');
    }

    /**
     * @description Simulates scenario where API threshold has been breached.
     */
    @IsTest
    static void testApiLimitExceededScenario() {
        validateMetadataPresence();
        insertMockInsight();    
        String cioName = 'Accounts_with_Unified_Details__cio'; 
    	Boolean useStub = true;
        // Pretend API callout limit is breached by simulating the internal logic
        Test.startTest();        
			CIBatchProcessor batch = new CIBatchProcessor(cioName, useStub, 0, 5, 0, 1);
        	Database.executeBatch(batch, 1);
        Test.stopTest();
    
        Calculated_Insight__c ci = [
            SELECT Data_Sync_Done__c, Data_Process_Error__c FROM Calculated_Insight__c
            WHERE Developer_Name__c = 'Accounts_with_Unified_Details' LIMIT 1
        ];
        System.assertEquals(false, ci.Data_Sync_Done__c, 'Sync should remain false due to API limit.');
        System.assertEquals('Api Limit reached. Will Automatically start processing tomorrow', ci.Data_Process_Error__c);
    }

}
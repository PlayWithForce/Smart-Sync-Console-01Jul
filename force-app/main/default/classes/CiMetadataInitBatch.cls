/**
 * @name        CiMetadataInitBatch
 * @description Batch to initialize CI metadata snapshot via SmartSyncInitializer.createCiMetaSnapshots().
 *              Includes retry mechanism based on Generic_Key_Value__mdt and publishes platform event result.
 * @author      Debanjan Mukherjee
 * @created     2025-06-26
 */
global without sharing class CiMetadataInitBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    private Integer retryCount;
	private string errMessage = '';
    /**
     * @description Default constructor, initializes retry to 0
     */
    public CiMetadataInitBatch() {
        this.retryCount = 0;
        this.errMessage = '';
    }

    /**
     * @description Overloaded constructor for retry batch run
     * @param retryCount Current retry count
     */
    public CiMetadataInitBatch(Integer retryCount) {
        this.retryCount = retryCount;
        this.errMessage = '';
    }

    /**
     * @description Dummy start method with 1-record scope for one-time execution
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM User WHERE Id = :UserInfo.getUserId()
        ]);
    }

    /**
     * @description Attempts to fetch CI metadata snapshot via SmartSyncInitializer
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            Set<String> cioNames = SmartSyncInitializer.createCiMetaSnapshots();
        } catch (Exception ex) {
            System.debug('Execution failed: ' + ex.getMessage());
            errMessage = errMessage+ex.getMessage();
        }
    }

    /**
     * @description Handles retry and result publication post execution
     */
    global void finish(Database.BatchableContext bc) {
        Boolean hasFailed = false;
        String errorMessage = errMessage;

        try {
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors
                FROM AsyncApexJob
                WHERE Id = :bc.getJobId()
                LIMIT 1
            ];
            hasFailed = (job.NumberOfErrors > 0);
        } catch (Exception e) {
            hasFailed = true;
        }

        Integer maxRetries = getRetrySetting('Max_Metadata_Retries');
        Integer retryInterval = getRetrySetting('Metadata_Processing_Retry_Interval');

        if (hasFailed) {
            errorMessage = 'Metadata initialization failed.';
            if (retryCount < maxRetries) {
                errorMessage += ' We will retry after ' + retryInterval + ' min.';
                System.schedule(
                    'Retry_Metadata_Init_' + Datetime.now().getTime(),
                    buildCronAfterMinutes(retryInterval),
                    new CiMetadataInitBatch(retryCount + 1)
                );
            } else {
                errorMessage += ' ' + maxRetries + ' retries failed. Giving up.';
            }

            updateCalculatedInsightOnFailure(errorMessage);
        } else {
            clearCalculatedInsightError();
        }

        publishResultEvent(hasFailed, errorMessage);
    }

    /**
     * @description Publishes SmartSync_Event__e platform event with status and error
     * @param isFailed Boolean flag indicating failure
     * @param errorMsg Error message string
     */
    private void publishResultEvent(Boolean isFailed, String errorMsg) {
        SmartSync_Event__e evt = new SmartSync_Event__e(
            Phase__c = 'Initialize',
            Status__c = isFailed ? 'Failed' : 'Success',
            Processing_Error__c = isFailed ? errorMsg : ''
        );
        EventBus.publish(evt);
    }

    /**
     * @description Builds cron expression for future scheduling
     * @param minutes Minutes from now to schedule
     * @return Cron expression string
     */
    private String buildCronAfterMinutes(Integer minutes) {
        Datetime dt = Datetime.now().addMinutes(minutes);
        return String.format('{0} {1} {2} {3} {4} ?',
            new List<String>{
                String.valueOf(dt.second()),
                String.valueOf(dt.minute()),
                String.valueOf(dt.hour()),
                String.valueOf(dt.day()),
                String.valueOf(dt.month())
            }
        );
    }

    /**
     * @description Retrieves retry metadata from Generic_Key_Value__mdt
     * @param keyName Metadata key (e.g. Max_Retries__c)
     * @return Parsed Integer value
     */
    @TestVisible
    private Integer getRetrySetting(String keyName) {
        try {
            List<Generic_Key_Value__mdt> entries = [
                SELECT Value__c FROM Generic_Key_Value__mdt
                WHERE Key__c = :keyName LIMIT 1
            ];
            if (!entries.isEmpty()) {
                return Integer.valueOf(entries[0].Value__c);
            }
        } catch (Exception e) {
            System.debug('Failed to read retry metadata: ' + e.getMessage());
        }
        return 1; // default fallback
    }

    /**
     * @description Updates Calculated_Insight__c with error message
     * @param errorMessage The error to persist
     */
    private void updateCalculatedInsightOnFailure(String errorMessage) {
        if (Schema.sObjectType.Calculated_Insight__c.isAccessible()
            && Schema.sObjectType.Calculated_Insight__c.fields.Developer_Name__c.isUpdateable()
            && Schema.sObjectType.Calculated_Insight__c.fields.Data_Process_Error__c.isUpdateable()) {

            Calculated_Insight__c insight = new Calculated_Insight__c(
                Name = 'Initialization Error',
                Developer_Name__c = 'Initialization_Error',
                displayName__c = 'Failed to Initialize',
                Data_Process_Error__c = errorMessage
            );
            upsert insight Developer_Name__c;
        }
    }

    /**
     * @description Clears error message from Calculated_Insight__c if success
     */
    private void clearCalculatedInsightError() {
        if (!Schema.sObjectType.Calculated_Insight__c.isAccessible()
            || !Schema.sObjectType.Calculated_Insight__c.fields.Data_Process_Error__c.isUpdateable()) {
            return;
        }

        List<Calculated_Insight__c> insights = [
            SELECT Id, Data_Process_Error__c FROM Calculated_Insight__c
            WHERE Developer_Name__c = 'Initialization_Error'
        ];

        for (Calculated_Insight__c ci : insights) {
            ci.Data_Process_Error__c = '';
        }
        update insights;
    }

    /**
     * @description Scheduler interface implementation
     * @param sc Context
     */
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new CiMetadataInitBatch(), 1);
    }

    /**
     * @description Custom exception for Metadata failures
     */
    public class MetadataInitException extends Exception {}
}
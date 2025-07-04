/**
 * @name        CIBatchProcessor
 * @description Batch job to fetch Calculated Insight data from Data Cloud with retry and callout threshold logic.
 *              Uses metadata-driven configuration and logs sync completion/error to Calculated_Insight__c.
 *              maxNumberOfCalls is intended for testing purposes only to prevent infinite retry loops.
 * @implements  Database.Batchable, Database.AllowsCallouts, Database.Stateful
 * @author      Debanjan Mukherjee
 * @created     2025-06-22
 */
public with sharing class CIBatchProcessor implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private final String cioName;
    private final Boolean useStub;
    private final Integer currOffset;
    private final Integer maxNumberOfCalls;
    private final Integer currRetryCount;
    private final Integer executionCount;

    private Integer metadataOffset;
    private String processingStatus;
    private Boolean nearCalloutLimit = false;
    private String processingError;

    /**
     * @description Constructor to initialize batch parameters
     */
    public CIBatchProcessor(String cioName, Boolean useStub, Integer currOffset, Integer maxNumberOfCalls, Integer currRetryCount, Integer executionCount) {
        this.cioName = cioName;
        this.useStub = useStub;
        this.currOffset = currOffset != null ? currOffset : 0;
        this.maxNumberOfCalls = maxNumberOfCalls;
        this.currRetryCount = currRetryCount != null ? currRetryCount : 0;
        this.executionCount = executionCount != null ? executionCount : 1;
    }

    /**
     * @description Initializes metadata offset and marks CI as processing started
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        try {
            SmartSync_Integration_Endpoint__mdt meta = [
                SELECT Offset__c FROM SmartSync_Integration_Endpoint__mdt
                WHERE DeveloperName = 'Calculated_Insight'
                LIMIT 1
            ];
            metadataOffset = meta.Offset__c != null ? meta.Offset__c.intValue() : 100;
        } catch (Exception ex) {
            metadataOffset = 100;
        }

        updateCalculatedInsightRecord(false, false);
        return Database.getQueryLocator([
            SELECT Id FROM User WHERE Id = :UserInfo.getUserId()
        ]);
    }

    /**
     * @description Executes the data sync for CI and handles retry or error logic
     */
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            Integer calloutThreshold = fetchMetadataValue('Callout_Threshold', 95);
            Integer used = Limits.getCallouts();
            Integer max = Limits.getLimitCallouts();
            Integer percentUsed = (used * 100) / max;

            if (percentUsed >= calloutThreshold) {
                nearCalloutLimit = true;
                processingStatus = 'false';
                processingError = 'Failed to Full Sync.Api Limit reached. Will Automatically start processing tomorrow';
                updateCalculatedInsightRecord(true, false);
                return;
            }

            processingStatus = getDataOfSelectedCI(cioName, useStub, currOffset);
        } catch (Exception ex) {
            processingStatus = 'false';
            processingError = ex.getMessage();

            Integer retryInterval = fetchMetadataValue('Data_Processing_Retry_Interval', 20);
            Integer maxRetries = fetchMetadataValue('Max_Retries', 5);

            if (currRetryCount < maxRetries) {
                scheduleRetryAfterMinutes(retryInterval);
            } else {
                updateCalculatedInsightRecord(true, false);
            }
        }
    }

    /**
     * @description Final step to handle success/failure & re-scheduling
     */
    public void finish(Database.BatchableContext context) {
        Boolean isDone = 'true'.equalsIgnoreCase(processingStatus);
        Boolean maxReached = maxNumberOfCalls != null && maxNumberOfCalls > 0 && executionCount >= maxNumberOfCalls;
		Boolean hasFailed = false;
        String errorMessage = '';
        if (maxReached) {
            isDone = true;
        }

        if (!isDone && !maxReached && !nearCalloutLimit && processingError == null) {
            Integer nextOffset = currOffset + metadataOffset;
            Integer nextRetryCount = currRetryCount + 1;
            Integer nextExecutionCount = executionCount + 1;

            Database.executeBatch(
                new CIBatchProcessor(cioName, useStub, nextOffset, maxNumberOfCalls, nextRetryCount, nextExecutionCount), 1
            );
        } else if (nearCalloutLimit && !maxReached) {
            scheduleNextDayRetry(currOffset + metadataOffset, currRetryCount + 1, executionCount + 1);
        } else {
            updateCalculatedInsightRecord(true, true);
        }
        //Boolean hasFailed = false;


        try {
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors
                FROM AsyncApexJob
                WHERE Id = :context.getJobId()
                LIMIT 1
            ];
            hasFailed = (job.NumberOfErrors > 0);
            if (hasFailed) {
            	errorMessage = 'Full Sync data import Failed-'+processingError;
                updateCalculatedInsightOnFailure(errorMessage);
            }
            else {
            	clearCalculatedInsightError();
        	}
        	publishResultEvent(hasFailed, errorMessage);
        } catch (Exception e) {
            hasFailed = true;
        }
    }

    /**
     * @description Updates sync flags & error status on Calculated_Insight__c record
     * @param isFinalAttempt Whether the update is in final batch run
     * @param dataSyncDone Whether sync was successful
     */
    private void updateCalculatedInsightRecord(Boolean isFinalAttempt, Boolean dataSyncDone) {
        try {
            String objectApiName = cioName.endsWith('__cio')
                ? cioName.substring(0, cioName.length() - 3)
                : cioName;

            Schema.SObjectType ciType = Schema.getGlobalDescribe().get('Calculated_Insight__c');
            if (ciType == null || !ciType.getDescribe().isAccessible()) return;

            List<Calculated_Insight__c> ciList = [
                SELECT Id, Data_Sync_Done__c, Last_Data_Sync__c, Data_Process_Error__c
                FROM Calculated_Insight__c
                WHERE Developer_Name__c = :objectApiName
                LIMIT 1
            ];

            if (!ciList.isEmpty() && ciType.getDescribe().isUpdateable()) {
                Calculated_Insight__c ci = ciList[0];
                Schema.DescribeSObjectResult describeResult = ciType.getDescribe();
                Map<String, Schema.SObjectField> fields = describeResult.fields.getMap();

                if (fields.containsKey('Data_Sync_Done__c') && fields.get('Data_Sync_Done__c').getDescribe().isUpdateable()) {
                    ci.Data_Sync_Done__c = dataSyncDone;
                }
                if (fields.containsKey('Last_Data_Sync__c') && fields.get('Last_Data_Sync__c').getDescribe().isUpdateable()) {
                    ci.Last_Data_Sync__c = isFinalAttempt && dataSyncDone == true ? Datetime.now() : null;
                }
                if (fields.containsKey('Data_Process_Error__c') && fields.get('Data_Process_Error__c').getDescribe().isUpdateable()) {
                    ci.Data_Process_Error__c = (isFinalAttempt && dataSyncDone != true && String.isNotBlank(processingError))
                        ? processingError
                        : null;
                }
                update ci;
            }
        } catch (Exception ex) {
            System.debug('Failed to update Calculated_Insight__c: ' + ex.getMessage());
        }
    }

    /**
     * @description Fetches value from Generic_Key_Value__mdt
     * @param key The metadata key
     * @param fallback Fallback integer value
     * @return Integer value from metadata or fallback
     */
    private Integer fetchMetadataValue(String key, Integer fallback) {
        try {
            Generic_Key_Value__mdt valueMdt = [
                SELECT Value__c FROM Generic_Key_Value__mdt
                WHERE Key__c = :key LIMIT 1
            ];
            return Integer.valueOf(valueMdt.Value__c);
        } catch (Exception ex) {
            System.debug('Metadata for key ' + key + ' not found. Using fallback: ' + fallback);
            return fallback;
        }
    }

    /**
     * @description Schedules this batch after N minutes
     */
    private void scheduleRetryAfterMinutes(Integer minutes) {
        Datetime futureTime = Datetime.now().addMinutes(minutes);
        String cron = getCronExpressionForDatetime(futureTime);
        String jobName = 'CI_ErrorRetry_' + String.valueOf(Datetime.now().getTime());

        CIBatchScheduler scheduler = new CIBatchScheduler(cioName, useStub, currOffset, maxNumberOfCalls, currRetryCount + 1, executionCount + 1);
        System.schedule(jobName, cron, scheduler);
    }

    /**
     * @description Schedules this batch for next day retry
     */
    private void scheduleNextDayRetry(Integer nextOffset, Integer retryCount, Integer nextExecutionCount) {
        String cronExpr = getCronExpressionForDatetime(Datetime.now().addDays(1));
        String jobName = 'Retry_CI_' + String.valueOf(Datetime.now().getTime());

        CIBatchScheduler scheduler = new CIBatchScheduler(cioName, useStub, nextOffset, maxNumberOfCalls, retryCount, nextExecutionCount);
        System.schedule(jobName, cronExpr, scheduler);
    }

    /**
     * @description Helper to generate cron from a datetime
     */
    private static String getCronExpressionForDatetime(Datetime dt) {
        return String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<String>{
                String.valueOf(dt.second()),
                String.valueOf(dt.minute()),
                String.valueOf(dt.hour()),
                String.valueOf(dt.day()),
                String.valueOf(dt.month()),
                String.valueOf(dt.year())
            }
        );
    }

    /**
     * @description Internal scheduler for retry execution
     */
    public class CIBatchScheduler implements Schedulable {
        private final String cioName;
        private final Boolean useStub;
        private final Integer offset;
        private final Integer maxNumberOfCalls;
        private final Integer retryCount;
        private final Integer executionCount;

        public CIBatchScheduler(String cioName, Boolean useStub, Integer offset, Integer maxNumberOfCalls, Integer retryCount, Integer executionCount) {
            this.cioName = cioName;
            this.useStub = useStub;
            this.offset = offset;
            this.maxNumberOfCalls = maxNumberOfCalls;
            this.retryCount = retryCount;
            this.executionCount = executionCount;
        }

        public void execute(SchedulableContext context) {
            Database.executeBatch(
                new CIBatchProcessor(cioName, useStub, offset, maxNumberOfCalls, retryCount, executionCount), 1
            );
        }
    }
    /**
     * @description Publishes SmartSync_Event__e platform event with status and error
     * @param isFailed Boolean flag indicating failure
     * @param errorMsg Error message string
     */
    private void publishResultEvent(Boolean isFailed, String errorMsg) {
        SmartSync_Event__e evt = new SmartSync_Event__e(
            Phase__c = 'Full Sync',
            Status__c = isFailed ? 'Failed' : 'Success',
            Processing_Error__c = isFailed ? errorMsg : ''
        );
        EventBus.publish(evt);
    }
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
     * @description Updates Calculated_Insight__c with error message
     * @param errorMessage The error to persist
     */
    private void updateCalculatedInsightOnFailure(String errorMessage) {
        if (Schema.sObjectType.Calculated_Insight__c.isAccessible()
            && Schema.sObjectType.Calculated_Insight__c.fields.Developer_Name__c.isUpdateable()
            && Schema.sObjectType.Calculated_Insight__c.fields.Data_Process_Error__c.isUpdateable()) {

            Calculated_Insight__c insight = new Calculated_Insight__c(
                Name = 'Full sync data import failure',
                Developer_Name__c = 'Initialization_Error',
                displayName__c = 'Failed to import complete data',
                Data_Process_Error__c = errorMessage
            );
            upsert insight Developer_Name__c;
        }
    }
    public static string getDataOfSelectedCI(String ciName,boolean useStub,integer currOffset) {
        try {
            CiDataHelper.enableStubMode(useStub);
            string isDone = CiDataHelper.createRecordsFromInsightFields(ciName,currOffset);
            System.debug(isDone);
            return isDone;
        } catch (Exception ex) {

            System.debug('Failed to initialize CI structure: ' + ex.getMessage());
            return 'false';
            //throw new SmartSyncException('Failed to initialize CI structure: ' + ex.getMessage());
        }
    }
}
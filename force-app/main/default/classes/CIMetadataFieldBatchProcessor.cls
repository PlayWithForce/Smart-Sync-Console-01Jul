/**
 * @name        CIMetadataFieldBatchProcessor
 * @description Batch class to create fields via Metadata API for a Calculated Insight object.
 *              It includes built-in retry, error handling, sync tracking, and permission set updates.
 *              This version uses generic SObject batching and includes internal schedulable logic.
 * @author      Debanjan Mukherjee
 * @created     2025-06-25
 */
public with sharing class CIMetadataFieldBatchProcessor implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private final String ciName;
    private final String permissionSetName;
    private final Integer retryCount;
    private final String objectApiName;
    private Boolean anyFailure = false;
    private String collectedErrors = '';

    /**
     * @description Constructor to initialize batch with target CI name and permission set.
     * @param ciName Developer name of the Calculated Insight object (without __c)
     * @param permissionSetName Name of the permission set to update access on
     * @param retryCount Number of retries so far
     */
    public CIMetadataFieldBatchProcessor(String ciName, String permissionSetName, Integer retryCount) {
        this.ciName = ciName;
        this.permissionSetName = permissionSetName;
        this.retryCount = retryCount;
        if(this.ciName.endsWith('__c'))
            this.objectApiName = ciName;        	
        else
            this.objectApiName = ciName + '__c';
    }

    /**
     * @description Query locator defining the scope of fields to process.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        updateCalculatedInsightRecord(false, '', false);

        if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
            anyFailure = true;
            collectedErrors = 'Object not found: ' + objectApiName;
            return Database.getQueryLocator([SELECT Id FROM User WHERE Id = :UserInfo.getUserId()]);
        }

        return Database.getQueryLocator([
            SELECT Id, Name, Calculated_Insight__c, Developer_Name__c, displayName__c, field_type__c,
                   Calculated_Insight__r.displayName__c, Calculated_Insight__r.Developer_Name__c
            FROM Insight_Field__c
            WHERE Calculated_Insight__r.Developer_Name__c = :ciName
        ]);
    }

    /**
     * @description Processes each chunk of Insight_Field__c records and creates metadata fields.
     */
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            List<Insight_Field__c> insightFields = new List<Insight_Field__c>();
            for (SObject sObj : scope) {
                if (sObj instanceof Insight_Field__c) {
                    insightFields.add((Insight_Field__c) sObj);
                }
            }

            List<MetaDataServiceHandler.fieldDef> fields = prepareFields(objectApiName, insightFields);
            List<MetaDataServiceHandler.fieldDefNumber> numFields = prepareNumFields(objectApiName, insightFields);
            MetaDataServiceHandler.createFields(fields,numFields);
        } catch (Exception ex) {
            anyFailure = true;
            collectedErrors += 'Field creation failed: ' + ex.getMessage() + '\n';
        }
    }

    /**
     * @description Handles retry, success, or permission grant failure at batch completion.
     */
    public void finish(Database.BatchableContext context) {
        if (anyFailure) {
            retryOrFail();
        }         
        try {
            PermissionSetUpdater.grantFullAccessToPermissionSet(objectApiName, permissionSetName);
            updateCalculatedInsightRecord(true, '', true);
            Database.executeBatch(new CIBatchProcessor('Accounts_with_Unified_Details', false, 0, 3, 0,0), 1);
        } catch (Exception ex) {
            updateCalculatedInsightRecord(true, 'Permission grant failed: ' + ex.getMessage(), false);
        }
        Boolean hasFailed = false;
        try {
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors
                FROM AsyncApexJob
                WHERE Id = :context.getJobId()
                LIMIT 1
            ];
            hasFailed = (job.NumberOfErrors > 0);
            if (hasFailed) {
            	collectedErrors = 'Object creation failure-'+collectedErrors;  
                updateCalculatedInsightOnFailure(collectedErrors);
            }
            else {
                clearCalculatedInsightError();
            }
        	publishResultEvent(hasFailed, collectedErrors);
        } catch (Exception e) {
            hasFailed = true;
        }
    }

    /**
     * @description Retries batch using internal Schedulable class or marks failure if retries exceeded.
     */
    private void retryOrFail() {
        Integer maxRetries = getIntegerConfigValue('Max_Metadata_Retries');
        Integer retryInterval = getIntegerConfigValue('Metadata_Processing_Retry_Interval');

        if (retryCount < maxRetries) {
            Datetime nextRun = Datetime.now().addMinutes(retryInterval);
            String cron = String.format('0 {0} {1} {2} {3} ? {4}',
                new List<String>{
                    String.valueOf(nextRun.minute()),
                    String.valueOf(nextRun.hour()),
                    String.valueOf(nextRun.day()),
                    String.valueOf(nextRun.month()),
                    String.valueOf(nextRun.year())
                }
            );

            String jobName = 'Retry_Metadata_CI_' + objectApiName + '_' + DateTime.now().getTime();
            System.schedule(jobName, cron, new RetryScheduler(ciName, permissionSetName, retryCount + 1));
        } else {
            updateCalculatedInsightRecord(true, collectedErrors, false);
        }
    }

    /**
     * @description Updates the Calculated_Insight__c record with sync and error details.
     */
    private void updateCalculatedInsightRecord(Boolean isFinalAttempt, String errorMsg, Boolean syncDone) {
        try {
            List<Calculated_Insight__c> insights = [
                SELECT Id, Metadata_Sync_Done__c, Metadata_Processing_Error__c, Last_Metadata_Sync__c
                FROM Calculated_Insight__c
                WHERE Developer_Name__c = :ciName
                LIMIT 1
            ];

            if (!insights.isEmpty()) {
                Calculated_Insight__c ci = insights[0];
                ci.Metadata_Processing_Error__c = errorMsg;
                ci.Metadata_Sync_Done__c = syncDone;
                if (isFinalAttempt) {
                    ci.Last_Metadata_Sync__c = Datetime.now();
                }
                update ci;
            }
        } catch (Exception e) {
            System.debug('Error updating CI metadata status: ' + e.getMessage());
        }
    }

    /**
     * @description Helper to convert Insight_Field__c list into metadata field definitions.
     */
    private List<MetaDataServiceHandler.fieldDef> prepareFields(String objectAPI, List<Insight_Field__c> insightFields) {
        List<MetaDataServiceHandler.fieldDef> fieldDefs = new List<MetaDataServiceHandler.fieldDef>();
        for (Insight_Field__c f : insightFields) {
            if(f.field_type__c !='NUMBER')
            {
            	MetaDataServiceHandler.fieldDef def = new MetaDataServiceHandler.fieldDef();
                def.fullName = objectAPI + '.' + f.Name;
                def.label = f.displayName__c;
                def.type_x = f.field_type__c;
    
                if (def.type_x == 'LongTextArea') {
                    def.length = 32000;
                } else if (def.type_x == 'STRING') {
                    def.type_x = 'Text';
                    def.length = 255;
                }
                else {
                    def.type_x = 'Text';
                    def.length = 255;
                }
                fieldDefs.add(def);
            }
        }
        return fieldDefs;
    }
	/**
     * @description Helper to convert Insight_Field__c list into metadata field definitions.
     */
    private List<MetaDataServiceHandler.fieldDefNumber> prepareNumFields(String objectAPI, List<Insight_Field__c> insightFields) {
        List<MetaDataServiceHandler.fieldDefNumber> fieldDefs = new List<MetaDataServiceHandler.fieldDefNumber>();
        for (Insight_Field__c f : insightFields) {
            if(f.field_type__c =='NUMBER')
            {
            	MetaDataServiceHandler.fieldDefNumber def = new MetaDataServiceHandler.fieldDefNumber();
                def.fullName = objectAPI + '.' + f.Name;
                def.label = f.displayName__c;
                def.type_x = 'Number';
                def.precision = 18;  // Total digits
                def.scale = 0;      // Digits after decimal                
                fieldDefs.add(def);
            }
        }
        return fieldDefs;
    }

    /**
     * @description Fetches Integer config value from Generic_Key_Value__mdt.
     */
    private Integer getIntegerConfigValue(String key) {
        List<Generic_Key_Value__mdt> rows = [
            SELECT Value__c FROM Generic_Key_Value__mdt WHERE Key__c = :key LIMIT 1
        ];
        if (!rows.isEmpty() && String.isNotBlank(rows[0].Value__c)) {
            return Integer.valueOf(rows[0].Value__c);
        }
        return 1;
    }

    /**
     * @description Schedulable class used to retry the batch after a delay.
     */
    public class RetryScheduler implements Schedulable {
        private final String retryCiName;
        private final String retryPermissionSet;
        private final Integer newRetryCount;

        public RetryScheduler(String ciName, String permissionSetName, Integer retryCount) {
            this.retryCiName = ciName;
            this.retryPermissionSet = permissionSetName;
            this.newRetryCount = retryCount;
        }

        public void execute(SchedulableContext context) {
            Database.executeBatch(
                new CIMetadataFieldBatchProcessor(retryCiName, retryPermissionSet, newRetryCount),
                10
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
                Name = 'Field creation failure',
                Developer_Name__c = 'Initialization_Error',
                displayName__c = 'Failed to create fields',
                Data_Process_Error__c = errorMessage
            );
            upsert insight Developer_Name__c;
        }
    }
}
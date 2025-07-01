global class CreateCustomObjectBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful  {

    private String objectName;
    private String objectAPI;
    private String objectPlural;
    private String permissionSetName;
    private String permissionSetLabel;
    private Boolean creationSuccess = false; // used to track success
    private String errMessage;
	
    // Constructor
    public CreateCustomObjectBatch(String objectName, String objectAPI, String objectPlural, String permissionSetName,String permissionSetLabel) {
        this.errMessage = '';
        this.objectName = objectName;
        if(objectAPI.endsWith('__c'))
        {
            this.objectAPI = objectAPI;
        }
        else
        {
            this.objectAPI = objectAPI+'__c';
        }
        this.objectPlural = objectPlural;
        this.permissionSetName = permissionSetName;
        this.permissionSetLabel = permissionSetLabel;
    }

    // Start method - returns a dummy iterable just to execute once
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM User WHERE Id = :UserInfo.getUserId()
        ]);
    }

    // Execute method - will try to create the custom object
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            MetaDataServiceHandler.createCustomObject(objectName, objectAPI, objectPlural);
        }catch(Exception ex)
        {
            errMessage = errMessage+ex.getMessage();
        }
    }

    // Finish method - runs after the batch completes
    global void finish(Database.BatchableContext bc) {
        PermissionSetUpdater.grantCrudAccessViaMetadata(objectAPI,permissionSetName,permissionSetLabel);
        if(objectAPI.endsWith('__c'))
        {
            this.objectAPI = objectAPI.replace('__c','');
        }
        Database.executeBatch(new CIMetadataFieldBatchProcessor(objectAPI, permissionSetName, 0), 10);
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
        if (hasFailed) {
            errMessage = 'Object creation failure'+objectAPI;
            updateCalculatedInsightOnFailure(errorMessage);
        } else {
            clearCalculatedInsightError();
        }

        publishResultEvent(hasFailed, errorMessage);
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
                Name = 'Object creation failure',
                Developer_Name__c = 'Initialization_Error',
                displayName__c = 'Failed to create  object',
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
     * @description Publishes SmartSync_Event__e platform event with status and error
     * @param isFailed Boolean flag indicating failure
     * @param errorMsg Error message string
     */
    private void publishResultEvent(Boolean isFailed, String errorMsg) {
        SmartSync_Event__e evt = new SmartSync_Event__e(
            Phase__c = 'Full Sync ',
            Status__c = isFailed ? 'Failed' : 'Success',
            Processing_Error__c = isFailed ? errorMsg : ''
        );
        EventBus.publish(evt);
    }
}
public with sharing class BulkApiBatchProcessor implements Database.Batchable<SObject>, Database.Stateful, Schedulable,Database.AllowsCallouts {

    private final String objectApiName;
    private final String keyField;
    public String jobId;
    public String jobState;
    public Integer attempt;

    public BulkApiBatchProcessor(String objectApiName, String keyField) {
        this(objectApiName, keyField, null, 0);
    }

    public BulkApiBatchProcessor(String objectApiName, String keyField, String jobId, Integer attempt) {
        this.objectApiName = objectApiName;
        this.keyField = keyField;
        this.jobId = jobId;
        this.attempt = attempt;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM User WHERE Id = :UserInfo.getUserId()]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (String.isBlank(jobId)) {
            jobId = BulkApiDataFetcherService.fetchJobIdForStageData(objectApiName);
            System.debug('✅ Created jobId: ' + jobId);
        }

        jobState = BulkApiDataFetcherService.getJobStatus(jobId);
        System.debug('🔁 Job Status: ' + jobState);
        
    }

    public void finish(Database.BatchableContext bc) {
        if (jobState != 'JobComplete' && attempt < 6) {
            Integer delayInSeconds = 10;
            
            String jobName = 'Retry_BulkApi_' + DateTime.now().getTime();

            System.debug('⏳ Scheduling retry attempt #' + (attempt + 1) + ' at +' + delayInSeconds + 's');

            scheduleRetry(objectApiName, keyField, jobId, attempt, 10); // retry after 10 seconds
        } else if (jobState != 'JobComplete') {
            System.debug('❌ Max attempts reached. Job still not complete: ' + jobState);
        } else {
            List<String> csvLines = BulkApiDataFetcherService.getResultForJob(jobId);
            if (!csvLines.isEmpty()) {
                System.debug('✅ Processing CSV with ' + csvLines.size() + ' lines');
                Database.executeBatch(new CsvLineProcessorBatch(objectApiName, keyField, csvLines), 200);
            } else {
                System.debug('⚠️ No result lines found');
            }
        }
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new BulkApiBatchProcessor(objectApiName, keyField, jobId, attempt), 1);
    }

    
    private static void scheduleRetry(String objectApiName, String keyField, String jobId, Integer attempt, Integer secondsDelay) {
        Datetime runTime = Datetime.now().addSeconds(secondsDelay);
        String cron = String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<String>{
                String.valueOf(runTime.second()),
                    String.valueOf(runTime.minute()),
                    String.valueOf(runTime.hour()),
                    String.valueOf(runTime.day()),
                    String.valueOf(runTime.month()),
                    String.valueOf(runTime.year())
                    }
        );
        
        String jobName = 'RetryBulkApi_' + attempt + '_' + Datetime.now().getTime();
        
        System.schedule(
            jobName,
            cron,
            new BulkApiBatchProcessor(objectApiName, keyField, jobId, attempt + 1)
        );
    }

}
public class RetryBatchIfJobIncomplete implements Queueable, Schedulable {
    private final String objectApiName;
    private final String keyField;
    private final String jobId;
    private final Integer attempt;

    public RetryBatchIfJobIncomplete(String objectApiName, String keyField, String jobId, Integer attempt) {
        this.objectApiName = objectApiName;
        this.keyField = keyField;
        this.jobId = jobId;
        this.attempt = attempt;
    }

    public void execute(QueueableContext context) {
        String jobState = BulkApiDataFetcherService.getJobStatus(jobId);
        System.debug('🔁 Retry attempt ' + attempt + ', job state: ' + jobState);

        if (jobState == 'JobComplete') {
            System.debug('✅ Job complete, launching final processor batch...');
            Database.executeBatch(new BulkApiBatchProcessor(objectApiName, keyField), 1);
        } else if (attempt < 6) {
            System.debug('⏳ Job not complete. Scheduling another retry...');
            String jobName = 'RetryBulkApi_' + DateTime.now().getTime();
            String cron = getCronAfterDelay(10); // 10 sec delay
            System.schedule(jobName, cron, new RetryBatchIfJobIncomplete(objectApiName, keyField, jobId, attempt + 1));
        } else {
            System.debug('❌ Max retries reached. Job not complete: ' + jobState);
        }
    }

    public void execute(SchedulableContext context) {
        System.enqueueJob(new RetryBatchIfJobIncomplete(objectApiName, keyField, jobId, attempt));
    }

    private static String getCronAfterDelay(Integer delaySeconds) {
        DateTime dt = System.now().addSeconds(delaySeconds);
        return String.format('%s %s %s %s %s ? %s',
            new List<String>{
                String.valueOf(dt.second()),
                String.valueOf(dt.minute()),
                String.valueOf(dt.hour()),
                String.valueOf(dt.day()),
                String.valueOf(dt.month()),
                String.valueOf(dt.year())
            });
    }
}
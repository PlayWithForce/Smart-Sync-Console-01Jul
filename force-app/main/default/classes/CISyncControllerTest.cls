@IsTest
private class CISyncControllerTest {

    @IsTest
    static void testGetCalculatedInsights() {
        Calculated_Insight__c ci = new Calculated_Insight__c(
            Name = 'Test Insight',
            Developer_Name__c = 'Test_Insight',
            displayName__c = 'Test Insight Display'
        );
        insert ci;

        Test.startTest();
        List<Calculated_Insight__c> insights = CISyncController.getCalculatedInsights();
        Test.stopTest();

        System.assert(!insights.isEmpty(), 'Expected at least one insight');
    }

    @IsTest
    static void testGetInsightFields() {
        Calculated_Insight__c ci = new Calculated_Insight__c(
            Name = 'Test Insight',
            Developer_Name__c = 'Test_CI',
            displayName__c = 'Test Insight Display'
        );
        insert ci;

        Insight_Field__c field = new Insight_Field__c(
            Name = 'Test Field',
            displayName__c = 'Test Field Display',
            Developer_Name__c = 'Test_Field',
            Calculated_Insight__c = ci.Id
        );
        insert field;

        Test.startTest();
        List<Insight_Field__c> fields = CISyncController.getInsightFields('Test_CI');
        Test.stopTest();

        System.assertEquals(1, fields.size(), 'Should return 1 field');
    }

    @IsTest
    static void testInitializeMetadata() {
        Test.startTest();
        CISyncController.initializeMetadata();
        Test.stopTest();
    }

    @IsTest
    static void testFullAndIncrementalSync() {
        Test.startTest();
        CISyncController.fullSync('Test_Insight');
        CISyncController.incrementalSync('Test_Insight', 'Test_Field');
        Test.stopTest();
    }
}
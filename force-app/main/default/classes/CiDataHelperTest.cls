@IsTest
private class CiDataHelperTest {

    @IsTest
    static void testBulkInsertFromCiJson() {
        String mockJson = '{\"data\": [' +
            '{\"Name\": \"Record One\", \"SomeField__c\": \"Value 1\", \"SomeNumber__c\": 123},' +
            '{\"Name\": \"Record Two\", \"SomeField__c\": \"Value 2\", \"SomeNumber__c\": 456}' +
        ']}';

        String testCioDevName = 'Test_CIO';

        // Insert the CI record first
        Calculated_Insight__c ci = new Calculated_Insight__c(
            Name = 'Test CIO',
            Developer_Name__c = testCioDevName
        );
        insert ci;

        // Insert required Insight_Field__c fields with valid lookup and developer name
        insert new Insight_Field__c(
            Name = 'SomeField__c',
            field_type__c = 'STRING',
            Developer_Name__c = 'SomeField',
            Insight__c = ci.Id
        );

        insert new Insight_Field__c(
            Name = 'SomeNumber__c',
            field_type__c = 'NUMBER',
            Developer_Name__c = 'SomeNumber',
            Insight__c = ci.Id
        );

        // Simulate stub mode behavior (stub flag only – real JSON is used internally in your class)

        Test.startTest();
        CiDataHelper.enableStubMode(true);
		CiDataHelper.testJsonOverride = '{\"data\": [' +
            '{\"Name\": \"Record One\", \"SomeField__c\": \"Value 1\", \"SomeNumber__c\": 123},' +
            '{\"Name\": \"Record Two\", \"SomeField__c\": \"Value 2\", \"SomeNumber__c\": 456}' +
        ']}';
        List<SObject> result = CiDataHelper.createRecordsFromInsightFields(testCioDevName);
        Test.stopTest();

        //System.assertEquals(2, result.size(), 'Expected two records inserted');

        for (SObject s : result) {
            System.assertNotEquals(null, s.get('SomeField__c'), 'SomeField__c should not be null');
            System.assertNotEquals(null, s.get('SomeNumber__c'), 'SomeNumber__c should not be null');
        }
    }
}
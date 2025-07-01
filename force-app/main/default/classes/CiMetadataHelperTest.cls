/**
 * @name        CiMetadataHelperTest
 * @description Tests ciMetadataHelper.parseInsightMetas() using mock JSON string.
 * @author      Debanjan Mukherjee
 * @created     2025-06-22
 */
@IsTest
private class CiMetadataHelperTest {

    @IsTest
    static void testParseInsightMetas() {
        String mockJson = '{"metadata":[{'+
            '"name":"Test_Insight__cio",'+
            '"displayName":"Test Insight",'+
            '"latestProcessTime":"2025-06-21T10:00:00.000Z",'+
            '"latestSuccessfulProcessTime":"2025-06-21T09:30:00.000Z",'+
            '"partitionBy":"partition__c",'+
            '"measures":[{'+
                '"name":"Measure_Field__c",'+
                '"displayName":"Measure Field",'+
                '"businessType":"Numeric",'+
                '"type":"NUMBER",'+
                '"rollupable":true'+
            '}],'+
            '"dimensions":[{'+
                '"name":"Dimension_Field__c",'+
                '"displayName":"Dimension Field",'+
                '"businessType":"Text",'+
                '"type":"STRING"'+
            '}],'+
            '"relationships":[{'+
                '"toEntity":"EntityA",'+
                '"fromEntity":"EntityB"'+
            '}]'+
        '}]}';

        Test.startTest();
        List<ciMetadataHelper.metadata> result = ciMetadataHelper.parseInsightMetas(mockJson);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should parse 1 metadata object');
        System.assertEquals('Test_Insight__cio', result[0].name);
        System.assertEquals(1, result[0].measures.size(), '1 measure expected');
        System.assertEquals(1, result[0].dimensions.size(), '1 dimension expected');
        System.assertEquals(1, result[0].relationships.size(), '1 relationship expected');
    }
}
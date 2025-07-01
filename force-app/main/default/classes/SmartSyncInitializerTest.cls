@isTest
public class SmartSyncInitializerTest {

    @testSetup
    static void setupTestData() {
        // Insert required Custom Metadata or support data if needed
        // Here we assume no extra dependencies
    }
	@IsTest
    static void testCreateCiMetaSnapshots() {
        // Prepare mock metadata
        List<ciMetadataHelper.metadata> mockMetaList = new List<ciMetadataHelper.metadata>();

        ciMetadataHelper.metadata mockMeta = new ciMetadataHelper.metadata();
        mockMeta.name = 'SampleCI__cio';
        mockMeta.displayName = 'Sample CI';
        mockMeta.latestSuccessfulProcessTime = DateTime.now();
        mockMeta.latestProcessTime = DateTime.now();
        mockMeta.partitionBy = 'Region';

        // Add one measure
        ciMetadataHelper.measures measure = new ciMetadataHelper.measures();
        measure.name = 'TestMetric__c';
        measure.displayName = 'Test Metric';
        measure.businessType = 'Numeric';
        measure.type = 'NUMBER';
        measure.rollupable = true;

        // Add one dimension
        ciMetadataHelper.dimensions dimension = new ciMetadataHelper.dimensions();
        dimension.name = 'TestDim__c';
        dimension.displayName = 'Test Dimension';
        dimension.businessType = 'Text';
        dimension.type = 'STRING';

        mockMeta.measures = new List<ciMetadataHelper.measures>{ measure };
            mockMeta.dimensions = new List<ciMetadataHelper.dimensions>{ dimension };
                mockMetaList.add(mockMeta);
        SmartSyncInitializer.lstInsightMetas = mockMetaList;
        Test.startTest();
        Set<String> result = SmartSyncInitializer.createCiMetaSnapshots();
        Test.stopTest();
        System.assert(result.contains('SampleCI'), 'Expected CI Developer Name "SampleCI" in snapshot results');
    }

    @isTest
    static void testGetDetailsOfChosenCi() {
        // Create mock CI and field
        Calculated_Insight__c ci = new Calculated_Insight__c(
            Name = 'SampleCI__cio',
            Developer_Name__c = 'SampleCI',
            DisplayName__c = 'Sample CI'
        );
        insert ci;

        Insight_Field__c ciField = new Insight_Field__c(
            Name = 'TestMetric__c',
            Developer_Name__c = 'SampleCI_TestMetric_Measure',
            DisplayName__c = 'Test Metric',
            Insight__c = 'SampleCI',
            Calculated_Insight__c = ci.Id,
            Measure_Dimension__c = 'Measure',
            Field_Type__c = 'Number'
        );
        insert ciField;

        Test.startTest();
        List<Insight_Field__c> result = SmartSyncInitializer.getDetailsOfChosenCi('SampleCI');
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected 1 Insight Field record');
        System.assertEquals('SampleCI_TestMetric_Measure', result[0].Developer_Name__c);
    }

    @isTest
    static void testGetSelectedCI() {
        // Reuse logic from above
        Calculated_Insight__c ci = new Calculated_Insight__c(
            Name = 'SelectedCI__cio',
            Developer_Name__c = 'SelectedCI',
            DisplayName__c = 'Selected CI'
        );
        insert ci;

        Insight_Field__c ciField = new Insight_Field__c(
            Name = 'RollupMetric__c',
            Developer_Name__c = 'SelectedCI_RollupMetric_Measure',
            DisplayName__c = 'Rollup Metric',
            Insight__c = 'SelectedCI',
            Calculated_Insight__c = ci.Id,
            Measure_Dimension__c = 'Measure',
            Field_Type__c = 'Number'
        );
        insert ciField;

        Test.startTest();
        Boolean result = SmartSyncInitializer.getSelectedCI('SelectedCI');
        Test.stopTest();

        System.assertEquals(true, result, 'Expected successful creation of metadata structure');
    }
    @IsTest
    static void testPrepareFieldsCoverage() {
        // Arrange mock Insight_Field__c list
        List<Insight_Field__c> fieldList = new List<Insight_Field__c>();

        Insight_Field__c field1 = new Insight_Field__c();
        field1.Name = 'Field1__c';
        field1.displayName__c = 'Field One';
        field1.field_type__c = 'STRING';

        Insight_Field__c field2 = new Insight_Field__c();
        field2.Name = 'Field2__c';
        field2.displayName__c = 'Field Two';
        field2.field_type__c = 'NUMBER';

        Insight_Field__c field3 = new Insight_Field__c();
        field3.Name = 'Field3__c';
        field3.displayName__c = 'Field Three';
        field3.field_type__c = 'LongTextArea';

        fieldList.addAll(new List<Insight_Field__c>{ field1, field2, field3 });

        // Act
        List<MetaDataServiceHandler.fieldDef> result = SmartSyncInitializer.prepareFields('MockObject__c', fieldList);

        // Assert
        System.assertEquals(3, result.size(), 'Expected 3 fields to be prepared.');
        System.assertEquals('MockObject__c.Field1__c', result[0].fullName);
        System.assertEquals('Text', result[0].type_x);
        System.assertEquals(255, result[0].length);

        System.assertEquals('Number', result[1].type_x);
        System.assertEquals(18, result[1].length);

        System.assertEquals('LongTextArea', result[2].type_x);
        System.assertEquals(32000, result[2].length);
    }
}
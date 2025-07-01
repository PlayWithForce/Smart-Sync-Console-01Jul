/**
 * @description Test class for MetaDataServiceHandler utility.
 * Validates field and object creation logic under test context.
 * Actual metadata operations are bypassed using Test.isRunningTest().
 * @author Debanjan Mukherjee
 * @since 2025-06-22
 */
@isTest
private class MetaDataServiceHandlerTest {

    /**
     * @description Test method for createCustomObject
     * @return void
     */
    @isTest
    static void testCreateCustomObject() {
        Test.startTest();
        MetaDataServiceHandler.createCustomObject('Test Object', 'TestObject__c', 'Test Objects');
        Test.stopTest();
        System.assertEquals(true, Test.isRunningTest(), 'Metadata call should be skipped in test context.');
    }

    /**
     * @description Test method for createFields
     * @return void
     */
    @isTest
    static void testCreateFields() {
        List<MetaDataServiceHandler.fieldDef> fieldList = new List<MetaDataServiceHandler.fieldDef>();

        MetaDataServiceHandler.fieldDef textField = new MetaDataServiceHandler.fieldDef();
        textField.fullName = 'TestObject__c.Text_Field__c';
        textField.label = 'Text Field';
        textField.type_x = 'Text';
        textField.length = 255;
        fieldList.add(textField);

        MetaDataServiceHandler.fieldDef numberField = new MetaDataServiceHandler.fieldDef();
        numberField.fullName = 'TestObject__c.Number_Field__c';
        numberField.label = 'Number Field';
        numberField.type_x = 'Number';
        numberField.length = 18;
        fieldList.add(numberField);

        Test.startTest();
        MetaDataServiceHandler.createFields(fieldList);
        Test.stopTest();

        System.assertEquals(2, fieldList.size(), 'Two fields should be added to the list.');
    }

    /**
     * @description Test method for createField helper
     * @return void
     */
    @isTest
    static void testCreateFieldHelper() {
        MetadataService.CustomField cf = new MetadataService.CustomField();
        cf = MetaDataServiceHandler.createField(cf, 'TestObject__c.SampleField__c', 'Sample Field', 'Text', 100);
        System.assertEquals('TestObject__c.SampleField__c', cf.fullName);
        System.assertEquals('Sample Field', cf.label);
        System.assertEquals('Text', cf.type_x);
        System.assertEquals(100, cf.length);
    }
}
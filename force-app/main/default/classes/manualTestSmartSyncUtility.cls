public class manualTestSmartSyncUtility {
	public static void cleanDataForMeta()
    {
        Insight_Field__c[] lstFields = [SELECT Id FROM Insight_Field__c];
        if(lstFields.size()>0)
            delete lstFields;
        Calculated_Insight__c[] lstCi=[SELECT Id FROM Calculated_Insight__c];
        if(lstCi.size()>0)
            delete lstCi;  
        
    }
    /*
     ////////*********Start Calling Your Methods ************////
//manualTestSmartSyncUtility.cleanDataForMeta();//for Objects with CI metadata
//Run script to clear data for ciMimic object //cant keep here as then u ll not b able to del the object
//SmartSyncInitializer.createCiMetaSnapshots();
//SmartSyncInitializer.getSelectedCI('Accounts_with_Unified_Details');
//PermissionSetUpdater.grantCrudAccessViaMetadata('Accounts_with_Unified_Details__c','SmartSyncConsole','SmartSyncConsole');
//PermissionSetUpdater.grantFullAccessToPermissionSet('Accounts_with_Unified_Details__c','SmartSyncConsole'); //worked for Fields 
//SmartSyncInitializer.getDataOfSelectedCI('Accounts_with_Unified_Details',false);
/********End of Test script *********************///

    /*check FLS amendment to PS from backened 
        SELECT Id, SObjectType, Field, PermissionsRead, PermissionsEdit, ParentId
        FROM FieldPermissions
        WHERE SObjectType = 'Accounts_with_Unified_Details__c'
        AND Parent.Name = 'SmartSyncConsole'
    */
    /*Check Object CRUD accesses from backened
        SELECT Id,Parent.Name,PermissionsCreate,PermissionsDelete,PermissionsEdit,PermissionsModifyAllRecords,SobjectType
        FROM ObjectPermissions 
        WHERE SObjectType = 'Accounts_with_Unified_Details__c'
     
     */
}
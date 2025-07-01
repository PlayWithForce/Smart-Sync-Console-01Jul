/**
 * @description Utility class for dynamic creation and manipulation of Custom Metadata using Salesforce Metadata API.
 * Handles object and field creation programmatically from Apex.
 * @author Debanjan Mukherjee
 * @created 2025-06-19
 */
public class MetaDataServiceHandler {
	public class MetadataServiceException extends Exception {}
    /**
     * @description Creates a custom object using MetadataService.
     * @param objectName Label of the custom object
     * @param objectAPI API name of the custom object
     * @param objectPlural Plural label of the custom object
     * @return void
     */
    public static void createCustomObject(String objectName, String objectAPI, String objectPlural) {
        if (Test.isRunningTest()) {
            System.debug('Test context detected. Skipping Metadata API call.');
            return;
        }

        MetadataService.MetadataPort metadataservice = new MetadataService.MetadataPort();
        metadataservice.SessionHeader = new MetadataService.SessionHeader_element();
        metadataservice.SessionHeader.sessionId = UserInfo.getSessionId();

        MetadataService.CustomObject customObject = new MetadataService.CustomObject();
        customObject.fullName = objectAPI;
        customObject.label = objectName;
        customObject.pluralLabel = objectPlural;
        customObject.nameField = new MetadataService.CustomField();
        customObject.nameField.type_x = 'Text';
        customObject.nameField.label = 'Name';
        customObject.deploymentStatus = 'Deployed';
        customObject.sharingModel = 'ReadWrite';

        List<MetadataService.CustomObject> objectList = new List<MetadataService.CustomObject> { customObject };
        try
        {
        	metadataservice.createMetadata(objectList);
        }
        catch(Exception ex)
        {
            throw new MetadataServiceException('Field to create object: ' + ex.getMessage());
        }
        System.debug('MetaDataServiceHandler.createCustomObject - Created: ' + objectAPI);
    }

    /**
     * @description Creates custom fields on a custom object.
     * @param lstFieldDefs List of field definitions to create
     * @return void
     */
    public static void createFields(List<fieldDef> lstFieldDefs,List<MetaDataServiceHandler.fieldDefNumber> lstNumFields) {
        if (Test.isRunningTest()) {
            System.debug('Test context detected. Skipping Metadata API call.');
            return;
        }

        MetadataService.MetadataPort metadataservice = new MetadataService.MetadataPort();
        metadataservice.SessionHeader = new MetadataService.SessionHeader_element();
        metadataservice.SessionHeader.sessionId = UserInfo.getSessionId();

        List<MetadataService.CustomField> fieldsToCreate = new List<MetadataService.CustomField>();
		List<string> lstFieldFullNames = new List<string>();
        for (fieldDef theField : lstFieldDefs) {
            MetadataService.CustomField customField = createField(
                new MetadataService.CustomField(),
                theField.fullName,
                theField.label,
                theField.type_x,
                theField.length
            );
            fieldsToCreate.add(customField);
            lstFieldFullNames.add(theField.fullName);
        }
		for (fieldDefNumber theField : lstNumFields) {
            MetadataService.CustomField customField = createNumField(
                new MetadataService.CustomField(),
                theField.fullName,
                theField.label,
                theField.type_x,
                theField.precision,
                theField.scale
            );
            fieldsToCreate.add(customField);
            lstFieldFullNames.add(theField.fullName);
        }
        List<MetadataService.Metadata> lstMetadata = new List<MetadataService.Metadata>();
        lstMetadata.addAll(fieldsToCreate);
        //metadataservice.createMetadata(lstMetadata);
        

        MetadataService.SaveResult[] results = metadataservice.createMetadata(fieldsToCreate);
        string errorMessage='';
        // Proceed only if field creation succeeded
        if (results != null && results[0].success) {
            System.debug('created successfully');
            //updateAdminFieldLevelSecurity(lstFieldFullNames);
        } else {
            for (MetadataService.Error err : results[0].errors) {    
                errorMessage = errorMessage + err.message;
                System.debug('Field creation error: ' + err.message);
            }
            throw new MetadataServiceException('Field creation error: ' + errorMessage);
        }
        
        //grantFieldAccessToAdminWithDml(lstFieldFullNames);
    }

    /**
     * @description Grants Read and Edit FLS for all fields on an sObject to a specific Permission Set.
     * @param sObjectApiName The API name of the object (e.g., Account, MyObject__c)
     * @param permissionSetName The DeveloperName of the Permission Set (e.g., Admin_Field_Access)
     */
    public static void grantFlsToPermissionSet(String sObjectApiName, String permissionSetName) {
        if (String.isBlank(sObjectApiName) || String.isBlank(permissionSetName)) {
            throw new IllegalArgumentException('Both object API name and permission set name are required.');
        }
    
        Map<String, Schema.SObjectType> allObjects = Schema.getGlobalDescribe();
    
        if (!allObjects.containsKey(sObjectApiName)) {
            throw new IllegalArgumentException('Invalid sObject type: ' + sObjectApiName);
        }
    
        Id permSetId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ].Id;
    
        Schema.DescribeSObjectResult objDescribe = allObjects.get(sObjectApiName).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
    
        Set<String> blockedFields = new Set<String>{
            'id', 'name', 'isdeleted', 'ownerid',
            'createdbyid', 'createddate', 'lastmodifiedbyid', 'lastmodifieddate',
            'systemmodstamp', 'masterrecordid', 'lastactivitydate',
            'lastvieweddate', 'lastreferenceddate'
        };
    
        List<FieldPermissions> fieldPermsToInsert = new List<FieldPermissions>();
    
        for (String fieldName : fieldMap.keySet()) {
            String lower = fieldName.toLowerCase();
    
            if (blockedFields.contains(lower) ||
                lower.endsWith('__tag') ||
                lower.endsWith('__history') ||
                lower.endsWith('__share') ||
                lower.contains('geocoded') ||
                lower.contains('cleanstatus')) {
                continue;
            }
    
            fieldPermsToInsert.add(new FieldPermissions(
                ParentId = permSetId,
                SObjectType = sObjectApiName,
                Field = sObjectApiName + '.' + fieldName,
                PermissionsRead = true,
                PermissionsEdit = true
            ));
        }
    
        if (!fieldPermsToInsert.isEmpty()) {
            insert fieldPermsToInsert;
        }
    }



    public static MetadataService.CustomField createField(
        MetadataService.CustomField customField,
        String fullName,
        String label,
        String type_x,
        Integer length
    ) {
        customField.fullName = fullName;
        customField.label = label;
        customField.type_x = type_x;
        customField.length = length;
        return customField;
    }
	public static MetadataService.CustomField createNumField(
        MetadataService.CustomField customField,
        String fullName,
        String label,
        String type_x,
        Integer precision,
        Integer scale
    ) {
        customField.fullName = fullName;
        customField.label = label;
        customField.type_x = type_x;
        customField.precision = precision;
        customField.scale = scale;
        return customField;
    }
    /**
     * @description Class to hold field definitions for custom fields.
     */
    public class fieldDef {
        public String fullName { get; set; }
        public String label { get; set; }
        public String type_x { get; set; }
        public Integer length { get; set; }
    }
    /**
     * @description Class to hold field definitions for custom fields.
     */
    public class fieldDefNumber {
        public String fullName { get; set; }
        public String label { get; set; }
        public String type_x { get; set; }
        public Integer precision { get; set; }
        public Integer scale { get; set; }
    }

}
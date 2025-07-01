/**
 * @name        CiDataHelper
 * @description Invokes CI data retrieval and processes dynamic JSON using untyped deserialization.
 *              Provides utility methods to extract typed attributes from JSON response from Data Cloud.
 * @author      Debanjan Mukherjee
 * @created     2025-06-22
 */
public with sharing class CiDataHelper {

    private static Boolean runStub = false;
	public static String testJsonOverride;
    public static void enableStubMode(Boolean useStub) {
        runStub = useStub;
    }

    /**
     * @description Navigates JSON using dot/bracket notation to extract a nested value
     * @param jsonBody Raw JSON response body
     * @param attributePath Attribute path in dot/bracket notation (e.g., data[0].Name)
     * @return The value of the attribute if found, else null
     */
    public static Object getJsonAttribute(String jsonBody, String attributePath) {
        if (String.isBlank(jsonBody) || String.isBlank(attributePath)) {
            return null;
        }

        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        boolean isDone = (boolean)jsonMap.get('done');
        List<String> pathSegments = attributePath.split('\\.');

        Object current = jsonMap;
        for (String segment : pathSegments) {
            if (current == null) break;

            if (segment.contains('[')) {
                String key = segment.substringBefore('[');
                Integer index = Integer.valueOf(segment.substringBetween('[', ']'));

                if (current instanceof Map<String, Object> && ((Map<String, Object>) current).containsKey(key)) {
                    Object listObj = ((Map<String, Object>) current).get(key);
                    if (listObj instanceof List<Object> && ((List<Object>) listObj).size() > index) {
                        current = ((List<Object>) listObj)[index];
                    } else {
                        return null;
                    }
                } else {
                    return null;
                }
            } else {
                if (current instanceof Map<String, Object> && ((Map<String, Object>) current).containsKey(segment)) {
                    current = ((Map<String, Object>) current).get(segment);
                } else {
                    return null;
                }
            }
        }

        return current;
    }

    /**
     * @description Creates and inserts records from CI JSON response into corresponding custom object
     * @param cioDevName Developer Name of the Calculated Insight Object (without __c suffix)
     * @return List of inserted records
     */
    public static string createRecordsFromInsightFields(String cioDevName,integer currOffset) {
        List<Insight_Field__c> fieldDefs = [
            SELECT Name, field_type__c FROM Insight_Field__c
            WHERE Calculated_Insight__r.Developer_Name__c = :cioDevName
        ];
        List<SObject> resultRecords = new List<SObject>();
        String responseJson;

        if (Test.isRunningTest() || runStub) {
            StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = 'cioDataStub' LIMIT 1];
            responseJson = sr.Body.toString();
        } else {
            if(!cioDevName.endsWith('__cio'))
            	responseJson = SmartSyncService.getDataOfCio(cioDevName + '__cio',fieldDefs[0].Name,currOffset);
        }

        if (String.isBlank(responseJson)) {
            return 'No records available in the selected Calculated Insight';
        }

        Map<String, Object> fullJson = (Map<String, Object>) JSON.deserializeUntyped(responseJson);
        boolean isDone = (boolean)fullJson.get('done');
        if (!fullJson.containsKey('data')) {
            return 'No records available in the selected Calculated Insight';
        }

        List<Object> dataList = (List<Object>) fullJson.get('data');
        String objectApiName = cioDevName + '__c';
		Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sobjectType == null) {
            System.debug('Object API not found: ' + objectApiName);
            return 'No Calculated Insight available with this Name';
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();


        for (Object entryObj : dataList) {
            if (entryObj instanceof Map<String, Object>) {
                Map<String, Object> entry = (Map<String, Object>) entryObj;
                SObject record = (SObject) Type.forName('', objectApiName).newInstance();

                for (Insight_Field__c field : fieldDefs) {
                    String fieldName = field.Name;
                    if (fieldMap.containsKey(fieldName)) {
                        Schema.SObjectField sFld = fieldMap.get(fieldName);
                        if (sFld.getDescribe().isAccessible() && sFld.getDescribe().isCreateable()) {
                            if (entry.containsKey(fieldName) && fieldName != 'Id') {
                                record.put(fieldName, entry.get(fieldName));
                            }
                        }
                    }
                }
                resultRecords.add(record);
            }
        }

        if (!resultRecords.isEmpty()) {
            insert resultRecords;
        }
        if(isDone)
        	return 'true';
        else
            return 'false';
    }
}
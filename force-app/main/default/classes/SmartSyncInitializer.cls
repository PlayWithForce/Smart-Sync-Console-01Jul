/**
 * @name        smartSyncInitializer
 * @description Handles Calculated Insight metadata snapshot and dynamic sObject creation.
 * @author      Debanjan Mukherjee
 * @created     2025-06-19
 */
public with sharing class SmartSyncInitializer {
    public class SmartSyncException extends Exception {}
    @TestVisible
    public static List<CiMetadataHelper.metadata> lstInsightMetas;
    public static Set<String> createCiMetaSnapshots() {
        Set<String> setCiNames = new Set<String>();
            if (Test.isRunningTest() && lstInsightMetas != null && !lstInsightMetas.isEmpty()) {
                System.debug('Using injected mock metadata');
            } else {
                try
                {
                	lstInsightMetas = CiMetadataHelper.fetchInsightMetas();
                } catch (Exception ex) {
                    throw new SmartSyncException('Failed to upsert Calculated Insights: ' + ex.getMessage());
                }
            }
            List<Calculated_Insight__c> ciListToUpsert = new List<Calculated_Insight__c>();
            Map<String, List<Insight_Field__c>> ciFieldsMap = new Map<String, List<Insight_Field__c>>();

            for (CiMetadataHelper.metadata meta : lstInsightMetas) {
                String ciDevName = meta.name.replace('__cio', '');
                setCiNames.add(ciDevName);

                Calculated_Insight__c ci = new Calculated_Insight__c(
                    Name = meta.name,
                    latestSuccessfulProcessTime__c = meta.latestSuccessfulProcessTime,
                    displayName__c = meta.displayName,
                    latestProcessTime__c = meta.latestProcessTime,
                    partitionBy__c = meta.partitionBy,
                    Developer_Name__c = ciDevName
                );
                ciListToUpsert.add(ci);

                List<Insight_Field__c> fieldsForCi = new List<Insight_Field__c>();

                for (CiMetadataHelper.measures measure : meta.measures) {
                    fieldsForCi.add(prepareInsightField(ciDevName, measure.name, measure.displayName, measure.businessType, measure.type, 'Measure'));
                }

                for (CiMetadataHelper.dimensions dim : meta.dimensions) {
                    fieldsForCi.add(prepareInsightField(ciDevName, dim.name, dim.displayName, dim.businessType, dim.type, 'Dimension'));
                }

                ciFieldsMap.put(ciDevName, fieldsForCi);
            }

        try {
            upsert ciListToUpsert Developer_Name__c;
        } catch (Exception ex) {
            throw new SmartSyncException('Failed to upsert Calculated Insights: ' + ex.getMessage());
        }

        List<Insight_Field__c> ciFieldsToUpsert = new List<Insight_Field__c>();
        for (Calculated_Insight__c ciRecord : ciListToUpsert) {
            List<Insight_Field__c> relatedFields = ciFieldsMap.get(ciRecord.Developer_Name__c);
            for (Insight_Field__c field : relatedFields) {
                field.Calculated_Insight__c = ciRecord.Id;
            }
            ciFieldsToUpsert.addAll(relatedFields);
        }

        try {
            upsert ciFieldsToUpsert Developer_Name__c;
        } catch (Exception ex) {
            throw new SmartSyncException('Failed to upsert Insight Fields: ' + ex.getMessage());
        }
		system.debug('final output for LWC'+setCiNames);
        return setCiNames;
    }

    public static List<Insight_Field__c> getDetailsOfChosenCi(String ciName) {
        if (!Schema.sObjectType.Insight_Field__c.fields.Calculated_Insight__c.isAccessible() ||
            !Schema.sObjectType.Insight_Field__c.fields.Name.isAccessible() ||
            !Schema.sObjectType.Insight_Field__c.fields.Developer_Name__c.isAccessible() ||
            !Schema.sObjectType.Insight_Field__c.fields.displayName__c.isAccessible() ||
            !Schema.sObjectType.Insight_Field__c.fields.field_type__c.isAccessible()) {
            throw new SmartSyncException('You do not have access to required Insight Field fields');
        }

        List<Insight_Field__c> fields = [
            SELECT Id, Name, Calculated_Insight__c, Developer_Name__c,
                   displayName__c, field_type__c,
                   Calculated_Insight__r.displayName__c,
                   Calculated_Insight__r.Developer_Name__c
            FROM Insight_Field__c
            WHERE Calculated_Insight__r.Developer_Name__c = :ciName //Limit 10
        ];

        if (fields.isEmpty()) {
            throw new SmartSyncException('No CI Details found - Please perform initial sync');
        }

        return fields;
    }

    public static Boolean getSelectedCI(String ciName,string permissionSetName, string permissionSetLabel) {
        try {
            List<Insight_Field__c> insightFields = getDetailsOfChosenCi(ciName);
            String objectName = insightFields[0].Calculated_Insight__r.displayName__c;
            String objectAPI = insightFields[0].Calculated_Insight__r.Developer_Name__c + '__c';
            String objectPlural = objectName + 's';
            //MetaDataServiceHandler.createCustomObject(objectName, objectAPI, objectPlural);
			if (!Test.isRunningTest()) {
            	Database.executeBatch(new CreateCustomObjectBatch(objectName, objectAPI, objectPlural, permissionSetName,permissionSetLabel),1);
                //Database.executeBatch(new CIMetadataFieldBatchProcessor(objectAPI, permissionSetName,permissionSetLabel, 0), 10);
                //below two lines will be replaced by Batch call
            	//List<MetaDataServiceHandler.fieldDef> fields = prepareFields(objectAPI, insightFields);
            	//MetaDataServiceHandler.createFields(fields);
            }

            return true;
        } catch (Exception ex) {
            System.debug('Failed to initialize CI structure: ' + ex.getMessage());
            return false;
        }
    }

    private static Insight_Field__c prepareInsightField(
        String ciDevName,
        String name,
        String display,
        String businessType,
        String type_x,
        String fieldGroup
    ) {
        return new Insight_Field__c(
            Name = name,
            displayName__c = display,
            businessType__c = businessType,
            field_type__c = type_x,
            Measure_Dimension__c = fieldGroup,
            Insight__c = ciDevName,
            Developer_Name__c = ciDevName + '_' + name.replace('__c', '') + '_' + fieldGroup
        );
    }
    /*
    public static string getDataOfSelectedCI(String ciName,boolean useStub,integer currOffset) {
        try {
            CiDataHelper.enableStubMode(useStub);
            string isDone = CiDataHelper.createRecordsFromInsightFields(ciName,currOffset);
            System.debug(isDone);
            return isDone;
        } catch (Exception ex) {
            System.debug('Failed to initialize CI structure: ' + ex.getMessage());
            throw new SmartSyncException('Failed to initialize CI structure: ' + ex.getMessage());
        }
    }*/
}
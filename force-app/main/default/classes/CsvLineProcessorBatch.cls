public with sharing class CsvLineProcessorBatch implements Database.Batchable<String>, Database.Stateful {

    private final String objectApiName;
    private final String keyField;
    private final List<String> csvLines;

    public CsvLineProcessorBatch(String objectApiName, String keyField, List<String> csvLines) {
        this.objectApiName = objectApiName;
        this.keyField = keyField;
        this.csvLines = csvLines;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> scopeLines = new List<String>();
        for (Integer i = 1; i < csvLines.size(); i++) {
            scopeLines.add(csvLines[i]);
        }
        return scopeLines;
    }

    public void execute(Database.BatchableContext bc, List<String> lines) {
        Map<String, Wrapper> keyToLatestRecord = new Map<String, Wrapper>();

        for (String line : lines) {
            List<String> fields = parseCsvLine(line);

            if (fields.size() < 5) {
                System.debug('⚠️ Malformed line skipped: ' + line);
                continue;
            }

            Wrapper wrapper = new Wrapper();
            wrapper.StageRecordId = fields[0];
            wrapper.StageAutoNumber = fields[1];
            wrapper.CiName = fields[2];
            wrapper.LastModifiedDateInStage = parseBulkApiDate(fields[3]);
            wrapper.Increment_Data = fields[4];

            Map<String, Object> incDataMap = parseIncrementData(wrapper.Increment_Data);
            if (incDataMap == null) {
                System.debug('⚠️ Skipping malformed Increment_Data: ' + wrapper.Increment_Data);
                continue;
            }

            Object keyValue = incDataMap.get(keyField);
            if (keyValue == null || String.valueOf(keyValue).trim() == '') {
                System.debug('⚠️ Skipping record with blank keyField: ' + keyField);
                continue;
            }

            wrapper.keyFieldData = String.valueOf(keyValue);

            if (!objectApiName.equalsIgnoreCase(wrapper.CiName)) {
                continue;
            }

            if (!keyToLatestRecord.containsKey(wrapper.keyFieldData)
                || (wrapper.LastModifiedDateInStage != null &&
                    wrapper.LastModifiedDateInStage.getTime() > keyToLatestRecord.get(wrapper.keyFieldData).LastModifiedDateInStage.getTime())) {
                keyToLatestRecord.put(wrapper.keyFieldData, wrapper);
            }
        }

        // Now prepare dynamic sObject creation
        String sObjectApi = objectApiName.endsWith('__c') ? objectApiName : objectApiName + '__c';
        List<SObject> lstRecords = new List<SObject>();
        List<String> failedStageRecordIds = new List<String>();

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(sObjectApi).getDescribe().fields.getMap();

        for (Wrapper wrapper : keyToLatestRecord.values()) {
            SObject record = (SObject) Type.forName('Schema.' + sObjectApi).newInstance();
            Map<String, Object> dataMap = parseIncrementData(wrapper.Increment_Data);

            if (dataMap != null) {
                for (String fieldName : dataMap.keySet()) {
                    if (fieldMap.containsKey(fieldName)) {
                        try {
                            Schema.SObjectField sObjField = fieldMap.get(fieldName);
                            Schema.DisplayType fieldType = sObjField.getDescribe().getType();
                            Object rawValue = dataMap.get(fieldName);
                            Object finalValue;
                    
                            if (rawValue == null) return;
                    
                            String rawString = String.valueOf(rawValue).trim();
                    
                            // Type conversions based on field type
                            switch on fieldType {
                                when Boolean {
                                    finalValue = rawString.toLowerCase() == 'true' || rawString == '1';
                                }
                                when Double {
                                    finalValue = Decimal.valueOf(rawString);
                                }
                                when Currency {
                                    finalValue = Decimal.valueOf(rawString);
                                }
                                when Integer {
                                    finalValue = Integer.valueOf(rawString);
                                }
                                when Date {
                                    finalValue = Date.valueOf(rawString);
                                }
                                when Datetime {
                                    finalValue = Datetime.valueOfGmt(rawString.replace('T', ' ').replace('Z', ''));
                                }
                                when String, TextArea, Email, Phone, Url, Picklist {
                                    finalValue = rawString;
                                }
                                when else {
                                    finalValue = rawString; // fallback
                                }
                            }
                    
                            record.put(fieldName, finalValue);
                    
                        } catch (Exception ex) {
                            System.debug('⚠️ Error setting field ' + fieldName + ': ' + ex.getMessage());
                        }
                    }

                }
                lstRecords.add(record);
            }
        }

        // Debug the final result (safe to comment in production)
        System.debug('✅ Prepared ' + lstRecords.size() + ' records of type: ' + sObjectApi);
        for (SObject rec : lstRecords) {
            System.debug(rec);
        }

        // Uncomment below for actual insert
        // Database.SaveResult[] results = Database.insert(lstRecords, false);
        // for (Integer i = 0; i < results.size(); i++) {
        //     if (!results[i].isSuccess()) {
        //         failedStageRecordIds.add(keyToLatestRecord.values()[i].StageRecordId);
        //     }
        // }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('✅ CsvLineProcessorBatch finished.');
    }

    // --- Helpers ---
    private static List<String> parseCsvLine(String line) {
        List<String> values = new List<String>();
        Boolean inQuotes = false;
        String curr = '';

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                values.add(curr.trim());
                curr = '';
            } else {
                curr += ch;
            }
        }
        values.add(curr.trim());
        return values;
    }

    private static Map<String, Object> parseIncrementData(String jsonStr) {
        if (String.isBlank(jsonStr)) return null;

        try {
            // Fix double-escaped quotes ("" -> ")
            jsonStr = jsonStr.replaceAll('""', '"');

            // If field names are unquoted, fix them
            if (!jsonStr.contains('\"')) {
                jsonStr = jsonStr.replaceAll('([a-zA-Z0-9_]+):', '"$1":');
                jsonStr = jsonStr.replaceAll(': ([^\",}{\\s]+)', ': "$1"');
            }

            return (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        } catch (Exception ex) {
            System.debug('⚠️ Error parsing Increment_Data: ' + ex.getMessage());
            return null;
        }
    }

    private static Datetime parseBulkApiDate(String rawDate) {
        if (String.isBlank(rawDate)) return null;

        try {
            if (rawDate.endsWith('Z')) {
                rawDate = rawDate.removeEnd('Z');
            }

            rawDate = rawDate.replace('T', ' '); // Replace T with space

            if (rawDate.length() == 19) {
                rawDate += '.000';
            }

            return Datetime.valueOfGmt(rawDate);
        } catch (Exception e) {
            System.debug('⚠️ Failed to parse date: ' + rawDate + ' - ' + e.getMessage());
            return null;
        }
    }

    public class Wrapper {
        public String StageRecordId;
        public String StageAutoNumber;
        public String CiName;
        public Datetime LastModifiedDateInStage;
        public String Increment_Data;
        public String keyFieldData;
    }
}
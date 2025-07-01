/**
 * @name        PermissionSetUpdaterTest
 * @description Validates field and object permission updates using standard object 'Campaign'.
 *              Ensures restricted system fields are excluded from FLS insert.
 * @author      Debanjan Mukherjee
 * @created     2025-06-22
 */
@IsTest
private class PermissionSetUpdaterTest {

    @TestSetup
    static void setup() {
        PermissionSet ps = new PermissionSet(
            Name = 'CampaignPermSet',
            Label = 'Campaign Permission Set'
        );
        insert ps;
    }

    @IsTest
    static void testGrantCrudAndFieldAccess() {
        String permissionSetName = 'CampaignPermSet';
        String sObjectApiName = 'Campaign';

        Test.startTest();
        PermissionSetUpdater.grantCrudAndFieldAccess(permissionSetName, sObjectApiName);
        Test.stopTest();

        List<ObjectPermissions> objPerms = [
            SELECT Id, SObjectType FROM ObjectPermissions
            WHERE Parent.Name = :permissionSetName
        ];
        System.assertEquals(1, objPerms.size(), 'One object permission should be assigned.');

        List<FieldPermissions> fieldPerms = [
            SELECT Id, Field FROM FieldPermissions
            WHERE Parent.Name = :permissionSetName AND SObjectType = :sObjectApiName
        ];
        System.assert(fieldPerms.size() > 0, 'Field permissions should exist.');

        for (FieldPermissions fp : fieldPerms) {
            String lower = fp.Field.toLowerCase();
            System.assert(!lower.endsWith('.id'), 'Id must be excluded.');
            System.assert(!lower.contains('.isdeleted'), 'IsDeleted must be excluded.');
            System.assert(!lower.contains('masterrecordid'), 'MasterRecordId must be excluded.');
            System.assert(!lower.contains('lastactivitydate'), 'LastActivityDate must be excluded.');
        }
    }

    @IsTest
    static void testBlankInputThrows() {
        Boolean failed = false;
        try {
            PermissionSetUpdater.grantCrudAndFieldAccess('', '');
        } catch (IllegalArgumentException e) {
            failed = true;
            System.assert(e.getMessage().contains('must not be blank'));
        }
        System.assert(failed, 'Should throw for blank inputs');
    }

    @IsTest
    static void testInvalidObjectThrows() {
        Boolean failed = false;
        try {
            PermissionSetUpdater.grantCrudAndFieldAccess('CampaignPermSet', 'FakeObject__c');
        } catch (IllegalArgumentException e) {
            failed = true;
            System.assert(e.getMessage().contains('Invalid sObject type'));
        }
        System.assert(failed, 'Should throw for invalid object');
    }
}
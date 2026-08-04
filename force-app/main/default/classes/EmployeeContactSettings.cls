/**
 * Resolves the custom metadata that drives the employee contact sync.
 *
 * getInstance() reads custom metadata without spending a SOQL query and without
 * needing test setup data, which is why this replaced the SOQL read the original
 * version used.
 */
public with sharing class EmployeeContactSettings {
    @TestVisible
    private static final String COMPANY_ACCOUNT_RECORD = 'Company_Account';

    /**
     * Test seam. Custom metadata records cannot be inserted by a test, so the way to
     * exercise a populated or a malformed setting is to stand one in for the org's.
     */
    @TestVisible
    private static Boolean useOverride = false;

    @TestVisible
    private static Employee_Contact_Setting__mdt settingOverride;

    /**
     * The account every employee contact is filed under.
     *
     * @return the configured Account Id, or null when the Company Account metadata
     *         record is missing, blank, or holds something that is not a record Id.
     */
    public static Id getCompanyAccountId() {
        Employee_Contact_Setting__mdt setting = useOverride
            ? settingOverride
            : Employee_Contact_Setting__mdt.getInstance(COMPANY_ACCOUNT_RECORD);

        if (setting == null || String.isBlank(setting.ID__c)) {
            return null;
        }

        try {
            return Id.valueOf(setting.ID__c.trim());
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Employee Contact Setting ' +
                    COMPANY_ACCOUNT_RECORD +
                    ' holds a value that is not a record Id: ' +
                    e.getMessage()
            );
            return null;
        }
    }
}

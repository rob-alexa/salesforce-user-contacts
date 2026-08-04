/**
 * Coverage for the employee contact sync.
 *
 * Two notes on how bulk safety is proved here. The decision layer is exercised with
 * 200 in-memory user records, which needs no DML and so cannot run into user license
 * limits in a small org. The service layer is exercised against real users with the
 * governor counters asserted directly, which is the thing that actually matters: a
 * query or a DML statement inside the per-user loop would move those numbers.
 */
@IsTest
private class UserContactSyncTest {
    private static final String COMPANY_ACCOUNT_NAME = 'Employee Contact Sync Test Co';
    private static final String RUN_KEY = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 10);
    private static Integer userCounter = 0;
    private static Integer fakeIdCounter = 0;

    @TestSetup
    static void makeCompanyAccount() {
        insert new Account(Name = COMPANY_ACCOUNT_NAME);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    private static Id companyAccountId() {
        return [SELECT Id FROM Account WHERE Name = :COMPANY_ACCOUNT_NAME LIMIT 1].Id;
    }

    private static void useCompanyAccount(Id accountId) {
        useSetting(new Employee_Contact_Setting__mdt(ID__c = accountId));
    }

    private static void useSetting(Employee_Contact_Setting__mdt setting) {
        EmployeeContactSettings.useOverride = true;
        EmployeeContactSettings.settingOverride = setting;
    }

    private static Id standardProfileId() {
        return [SELECT Id FROM Profile WHERE UserType = 'Standard' ORDER BY Name LIMIT 1].Id;
    }

    /**
     * State and Country are deliberately left off. An org with State and Country
     * Picklists turned on rejects a plain code or name on User, so setting them here
     * would make the fixture pass or fail on an org setting that has nothing to do
     * with the sync. Street and City cover the address mapping and are free text
     * either way.
     */
    private static User buildUser(String lastName) {
        userCounter++;
        String unique = RUN_KEY + String.valueOf(userCounter).leftPad(3, '0');
        return new User(
            FirstName = 'Sync',
            LastName = lastName,
            Alias = unique.substring(0, 8),
            Email = 'employee.contact.sync@example.com',
            Username = 'ucs' + unique + '@usercontacts.test.invalid',
            ProfileId = standardProfileId(),
            TimeZoneSidKey = 'America/Phoenix',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Title = 'Engineer',
            Department = 'Engineering',
            Phone = '555-0100',
            Extension = '4242',
            MobilePhone = '555-0199',
            Street = '100 Main Street',
            City = 'Phoenix'
        );
    }

    /** Inserts users outside the setup-object DML restriction. */
    private static void insertUsers(List<User> users) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }
    }

    private static void updateUsers(List<User> users) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update users;
        }
    }

    /**
     * A syntactically valid User Id that belongs to no record. The describe is
     * deferred so it does not pull every child relationship in to read one prefix.
     *
     * @return an unused 15 character User Id
     */
    private static Id fakeUserId() {
        fakeIdCounter++;
        String keyPrefix = User.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        return Id.valueOf(keyPrefix + String.valueOf(fakeIdCounter).leftPad(12, '0'));
    }

    /**
     * A user record that was never saved. UserType is not writeable through the sObject
     * constructor, so it is set the way a trigger would see it: by deserializing.
     */
    private static User fabricatedUser(String lastName) {
        return fabricatedUser(lastName, true);
    }

    private static User fabricatedUser(String lastName, Boolean isActive) {
        return (User) JSON.deserialize(
            '{"attributes":{"type":"User"},"Id":"' +
                fakeUserId() +
                '","UserType":"Standard","IsActive":' +
                isActive +
                ',"LastName":"' +
                lastName +
                '"}',
            User.class
        );
    }

    private static List<Contact> employeeContactsFor(Set<Id> userIds) {
        return [
            SELECT
                Id,
                FirstName,
                LastName,
                Email,
                Title,
                Department,
                Phone,
                MobilePhone,
                Extension__c,
                MailingStreet,
                MailingCity,
                AccountId,
                OwnerId,
                ReportsToId,
                Status__c,
                No_Longer_There__c,
                User__c
            FROM Contact
            WHERE User__c IN :userIds
        ];
    }

    // ─── tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void newUserGetsAnEmployeeContact() {
        Id accountId = companyAccountId();
        useCompanyAccount(accountId);
        User employee = buildUser('Alpha');

        Test.startTest();
        insertUsers(new List<User>{ employee });
        Test.stopTest();

        List<Contact> contacts = employeeContactsFor(new Set<Id>{ employee.Id });
        Assert.areEqual(1, contacts.size(), 'The new user should have exactly one employee contact');

        Contact created = contacts[0];
        Assert.areEqual('Alpha', created.LastName, 'Last name should come from the user');
        Assert.areEqual('Sync', created.FirstName, 'First name should come from the user');
        Assert.areEqual('Engineer', created.Title, 'Title should come from the user');
        Assert.areEqual('Engineering', created.Department, 'Department should come from the user');
        Assert.areEqual('4242', created.Extension__c, 'Extension should come from the user');
        Assert.areEqual('100 Main Street', created.MailingStreet, 'Mailing street should come from the user Street');
        Assert.areEqual('Phoenix', created.MailingCity, 'Mailing city should come from the user City');
        Assert.areEqual(accountId, created.AccountId, 'The contact should be filed under the company account');
        Assert.areEqual(employee.Id, created.OwnerId, 'The user should own their own employee contact');
        Assert.areEqual(employee.Id, created.User__c, 'The User lookup should point back at the user');
        Assert.areEqual('Active', created.Status__c, 'An active user should give an Active contact');
        Assert.isFalse(created.No_Longer_There__c, 'An active user should not be flagged as gone');
    }

    @IsTest
    static void updatingAUserUpdatesTheSameContact() {
        Id accountId = companyAccountId();
        useCompanyAccount(accountId);

        UserContactSync.bypass = true;
        User employee = buildUser('Bravo');
        insertUsers(new List<User>{ employee });
        UserContactSync.bypass = false;

        insert new Contact(
            LastName = 'Bravo',
            AccountId = accountId,
            OwnerId = employee.Id,
            User__c = employee.Id,
            Title = 'Engineer'
        );

        Test.startTest();
        employee.Title = 'Principal Engineer';
        updateUsers(new List<User>{ employee });
        Test.stopTest();

        List<Contact> contacts = employeeContactsFor(new Set<Id>{ employee.Id });
        Assert.areEqual(1, contacts.size(), 'Updating a user should not create a second contact');
        Assert.areEqual('Principal Engineer', contacts[0].Title, 'The contact title should follow the user');
    }

    /**
     * The active flag drives two contact fields, and it is checked against the mapping
     * directly rather than end to end. Writing it would mean a contact owned by an
     * inactive user, which needs the Update Records with Inactive Owners permission,
     * and an org that has not granted it would fail this on setup rather than on the
     * rule being tested.
     */
    @IsTest
    static void theActiveFlagDrivesStatusAndNoLongerThere() {
        UpsertUserContact sync = new UpsertUserContact(new Set<Id>(), companyAccountId());

        Test.startTest();
        Contact fromActive = sync.buildContact(fabricatedUser('Charlie', true));
        Contact fromInactive = sync.buildContact(fabricatedUser('Charlie', false));
        Test.stopTest();

        Assert.areEqual('Active', fromActive.Status__c, 'An active user should give an Active contact');
        Assert.isFalse(fromActive.No_Longer_There__c, 'An active user should not be flagged as gone');
        Assert.areEqual('Inactive', fromInactive.Status__c, 'An inactive user should give an Inactive contact');
        Assert.isTrue(fromInactive.No_Longer_There__c, 'An inactive user should be flagged as gone');
    }

    @IsTest
    static void managerContactPopulatesReportsTo() {
        Id accountId = companyAccountId();
        useCompanyAccount(accountId);

        UserContactSync.bypass = true;
        User manager = buildUser('Delta');
        insertUsers(new List<User>{ manager });
        UserContactSync.bypass = false;

        Contact managerContact = new Contact(
            LastName = 'Delta',
            AccountId = accountId,
            OwnerId = manager.Id,
            User__c = manager.Id
        );
        insert managerContact;

        User report = buildUser('Echo');
        report.ManagerId = manager.Id;

        Test.startTest();
        insertUsers(new List<User>{ report });
        Test.stopTest();

        List<Contact> contacts = employeeContactsFor(new Set<Id>{ report.Id });
        Assert.areEqual(1, contacts.size(), 'The report should have one employee contact');
        Assert.areEqual(
            managerContact.Id,
            contacts[0].ReportsToId,
            'Reports To should point at the manager employee contact'
        );
    }

    @IsTest
    static void contactOwnedByTheUserIsAdoptedNotDuplicated() {
        Id accountId = companyAccountId();
        useCompanyAccount(accountId);

        UserContactSync.bypass = true;
        User employee = buildUser('Foxtrot');
        insertUsers(new List<User>{ employee });
        UserContactSync.bypass = false;

        // A contact from before the User lookup existed: owned by the user, lookup blank.
        Contact legacy = new Contact(LastName = 'Foxtrot', AccountId = accountId, OwnerId = employee.Id);
        insert legacy;

        Test.startTest();
        employee.Title = 'Staff Engineer';
        updateUsers(new List<User>{ employee });
        Test.stopTest();

        List<Contact> contacts = [SELECT Id, User__c, Title FROM Contact WHERE AccountId = :accountId];
        Assert.areEqual(1, contacts.size(), 'The pre-existing contact should be adopted, not duplicated');
        Assert.areEqual(legacy.Id, contacts[0].Id, 'The same contact record should be reused');
        Assert.areEqual(employee.Id, contacts[0].User__c, 'Adoption should stamp the User lookup for next time');
        Assert.areEqual('Staff Engineer', contacts[0].Title, 'The adopted contact should take the user values');
    }

    @IsTest
    static void aSaveThatChangesNoSyncedFieldQueuesNothing() {
        useCompanyAccount(companyAccountId());

        UserContactSync.bypass = true;
        User employee = buildUser('Golf');
        insertUsers(new List<User>{ employee });
        UserContactSync.bypass = false;

        Test.startTest();
        // Alias is not mirrored onto the contact, so changing it is not worth a job.
        employee.Alias = 'zz' + RUN_KEY.substring(0, 6);
        updateUsers(new List<User>{ employee });
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, queued, 'A save touching no mirrored field should queue no sync job');
        Assert.areEqual(
            0,
            employeeContactsFor(new Set<Id>{ employee.Id }).size(),
            'No contact should have been created'
        );
    }

    @IsTest
    static void twoHundredUsersQueueASingleJob() {
        useCompanyAccount(companyAccountId());

        List<User> saved = new List<User>();
        for (Integer i = 0; i < 200; i++) {
            saved.add(fabricatedUser('Bulk' + i));
        }

        Test.startTest();
        UserContactSync.handleAfterSave(saved, null);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(1, queued, '200 users in one save should queue one job, not one job each');
    }

    @IsTest
    static void syncSpendsTheSameQueriesRegardlessOfUserCount() {
        Id accountId = companyAccountId();
        useCompanyAccount(accountId);

        UserContactSync.bypass = true;
        List<User> employees = new List<User>{ buildUser('Hotel'), buildUser('India'), buildUser('Juliett') };
        insertUsers(employees);
        UserContactSync.bypass = false;

        Set<Id> userIds = new Map<Id, User>(employees).keySet();

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        new UpsertUserContact(userIds, accountId).sync();
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(3, employeeContactsFor(userIds).size(), 'Every user in the set should get a contact');
        Assert.areEqual(
            2,
            queriesUsed,
            'The sync should cost one user query and one contact query, whatever the count'
        );
        Assert.areEqual(1, dmlUsed, 'The sync should write every contact in a single upsert');
    }

    @IsTest
    static void missingCompanyAccountSettingSkipsTheSync() {
        // The metadata record exists, with nobody having filled the Account Id in yet.
        useSetting(new Employee_Contact_Setting__mdt(ID__c = null));

        User employee = buildUser('Kilo');

        Test.startTest();
        insertUsers(new List<User>{ employee });
        Test.stopTest();

        Assert.areEqual(
            0,
            employeeContactsFor(new Set<Id>{ employee.Id }).size(),
            'With no company account configured the sync should skip rather than fail the user save'
        );
    }

    @IsTest
    static void bypassSuppressesTheSync() {
        useCompanyAccount(companyAccountId());
        UserContactSync.bypass = true;
        User employee = buildUser('Lima');

        Test.startTest();
        insertUsers(new List<User>{ employee });
        Test.stopTest();

        UserContactSync.bypass = false;
        Assert.areEqual(
            0,
            employeeContactsFor(new Set<Id>{ employee.Id }).size(),
            'Bypass should stop the sync from running at all'
        );
    }

    @IsTest
    static void aPopulatedSettingResolvesToTheAccountId() {
        Id accountId = companyAccountId();
        useSetting(new Employee_Contact_Setting__mdt(ID__c = accountId));

        Test.startTest();
        Id resolved = EmployeeContactSettings.getCompanyAccountId();
        Test.stopTest();

        Assert.areEqual(accountId, resolved, 'A populated setting should resolve to that Account Id');
    }

    @IsTest
    static void aSettingThatIsNotARecordIdResolvesToNull() {
        useSetting(new Employee_Contact_Setting__mdt(ID__c = 'the company account'));

        Test.startTest();
        Id resolved = EmployeeContactSettings.getCompanyAccountId();
        Test.stopTest();

        Assert.isNull(resolved, 'A value that is not a record Id should resolve to null rather than throw');
    }

    @IsTest
    static void aMissingSettingResolvesToNull() {
        useSetting(null);

        Test.startTest();
        Id resolved = EmployeeContactSettings.getCompanyAccountId();
        Test.stopTest();

        Assert.isNull(resolved, 'A metadata record that does not exist should resolve to null rather than throw');
    }

    @IsTest
    static void settingsReadTheCompanyAccountMetadata() {
        // No override: this exercises the real custom metadata read. The shipped
        // Company Account record has no Account Id until an admin fills it in, so a
        // null answer here is the configured-nothing case, not a failure.
        Test.startTest();
        Id resolved = EmployeeContactSettings.getCompanyAccountId();
        Test.stopTest();

        Employee_Contact_Setting__mdt setting = Employee_Contact_Setting__mdt.getInstance('Company_Account');
        if (setting == null || String.isBlank(setting.ID__c)) {
            Assert.isNull(resolved, 'An unpopulated setting should resolve to null, not throw');
        } else {
            Assert.areEqual(Id.valueOf(setting.ID__c.trim()), resolved, 'The configured Account Id should be returned');
        }
    }

    @IsTest
    static void enqueueDoesNothingForAnEmptySet() {
        useCompanyAccount(companyAccountId());

        Test.startTest();
        UpsertUserContact.enqueue(new Set<Id>());
        UpsertUserContact.enqueue(null);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(0, queued, 'There is nothing to sync, so nothing should be queued');
    }
}

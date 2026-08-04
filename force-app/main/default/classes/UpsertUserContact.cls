/**
 * Mirrors a set of Salesforce users onto employee Contact records under a single
 * company account.
 *
 * Matching is by the Contact.User lookup. A contact that does not have it set yet is
 * picked up by owner instead and stamped with the lookup on the way past, so an
 * existing org converges on the exact key after one sync per user.
 */
public with sharing class UpsertUserContact implements Queueable {
    private final Set<Id> userIds;
    private final Id companyAccountId;

    public UpsertUserContact(Set<Id> userIds, Id companyAccountId) {
        this.userIds = userIds == null ? new Set<Id>() : userIds;
        this.companyAccountId = companyAccountId;
    }

    /**
     * Queues a sync for an arbitrary set of users, resolving the company account from
     * custom metadata. Use this to backfill from anonymous Apex or another class.
     *
     * @param userIds the users to mirror onto employee contacts
     */
    public static void enqueue(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        Id companyAccountId = EmployeeContactSettings.getCompanyAccountId();
        if (companyAccountId == null) {
            System.debug(
                LoggingLevel.ERROR,
                'Employee contact sync skipped: the Company Account custom metadata record holds no Account Id.'
            );
            return;
        }
        System.enqueueJob(new UpsertUserContact(userIds, companyAccountId));
    }

    public void execute(QueueableContext context) {
        sync();
    }

    @TestVisible
    private void sync() {
        if (userIds.isEmpty() || companyAccountId == null) {
            return;
        }

        List<User> users = [
            SELECT
                Id,
                FirstName,
                LastName,
                Email,
                Extension,
                Department,
                ManagerId,
                Fax,
                IsActive,
                Phone,
                MobilePhone,
                Title,
                Street,
                City,
                State,
                PostalCode,
                Country
            FROM User
            WHERE Id IN :userIds
            WITH SYSTEM_MODE
        ];
        if (users.isEmpty()) {
            return;
        }

        // Managers are looked up alongside the users themselves so Reports To can be
        // resolved from the same query.
        Set<Id> lookupIds = new Set<Id>(userIds);
        for (User employee : users) {
            if (employee.ManagerId != null) {
                lookupIds.add(employee.ManagerId);
            }
        }

        Map<Id, Contact> existingByUserId = findEmployeeContacts(lookupIds);

        List<Contact> toUpsert = new List<Contact>();
        for (User employee : users) {
            toUpsert.add(toUpsertRecord(employee, existingByUserId));
        }

        logFailures(Database.upsert(toUpsert, false));
    }

    /**
     * One user's contact, ready to upsert: the field mapping plus the record Id, the
     * owner, and Reports To.
     *
     * @param employee the user to mirror
     * @param existingByUserId employee contacts already in the org, keyed by user Id
     * @return the contact to upsert, with an Id when one already exists
     */
    private Contact toUpsertRecord(User employee, Map<Id, Contact> existingByUserId) {
        Contact employeeContact = buildContact(employee);
        Contact existing = existingByUserId.get(employee.Id);

        if (existing == null) {
            employeeContact.OwnerId = employee.Id;
        } else {
            employeeContact.Id = existing.Id;
            // Only write the owner when it has drifted. Re-asserting an unchanged owner
            // would need Update Records with Inactive Owners on every sync of a
            // departed employee, for no change at all.
            if (existing.OwnerId != employee.Id) {
                employeeContact.OwnerId = employee.Id;
            }
        }

        // A manager whose own employee contact does not exist yet leaves Reports To
        // alone; the next sync of this user fills it in.
        Contact managerContact = employee.ManagerId == null ? null : existingByUserId.get(employee.ManagerId);
        if (managerContact != null) {
            employeeContact.ReportsToId = managerContact.Id;
        }

        return employeeContact;
    }

    /**
     * The user to contact field mapping, with no record Id, owner, or Reports To on
     * it yet. Kept separate from the loop so the mapping rules can be checked without
     * writing anything, which matters for the inactive case: a contact owned by an
     * inactive user needs the Update Records with Inactive Owners permission, and a
     * test should not depend on the org granting it.
     *
     * @param employee the user to mirror
     * @return an unsaved contact carrying that user's values
     */
    @TestVisible
    private Contact buildContact(User employee) {
        return new Contact(
            AccountId = companyAccountId,
            User__c = employee.Id,
            FirstName = employee.FirstName,
            LastName = employee.LastName,
            Email = employee.Email,
            Department = employee.Department,
            Fax = employee.Fax,
            Extension__c = employee.Extension,
            Phone = employee.Phone,
            MobilePhone = employee.MobilePhone,
            Title = employee.Title,
            MailingStreet = employee.Street,
            MailingCity = employee.City,
            MailingState = employee.State,
            MailingPostalCode = employee.PostalCode,
            MailingCountry = employee.Country,
            Status__c = employee.IsActive ? 'Active' : 'Inactive',
            No_Longer_There__c = !employee.IsActive
        );
    }

    /**
     * @param lookupIds the users whose employee contacts are wanted
     * @return the employee contact for each of those users, keyed by user Id
     */
    private Map<Id, Contact> findEmployeeContacts(Set<Id> lookupIds) {
        List<Contact> matches = [
            SELECT Id, OwnerId, User__c
            FROM Contact
            WHERE AccountId = :companyAccountId AND (User__c IN :lookupIds OR OwnerId IN :lookupIds)
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate ASC
        ];

        // Owner is the adoption path for a contact with no User lookup set, so it is
        // filled in first and an explicit User match always overwrites it.
        Map<Id, Contact> byUserId = new Map<Id, Contact>();
        for (Contact match : matches) {
            if (match.User__c == null && lookupIds.contains(match.OwnerId)) {
                byUserId.put(match.OwnerId, match);
            }
        }
        for (Contact match : matches) {
            if (match.User__c != null) {
                byUserId.put(match.User__c, match);
            }
        }
        return byUserId;
    }

    /**
     * The upsert runs with allOrNone false so one bad record cannot discard a whole
     * batch. That makes reporting the rejects the only way anyone finds out.
     */
    private void logFailures(List<Database.UpsertResult> results) {
        for (Database.UpsertResult result : results) {
            if (result.isSuccess()) {
                continue;
            }
            for (Database.Error error : result.getErrors()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Employee contact upsert failed: ' +
                        error.getStatusCode() +
                        ' ' +
                        error.getMessage() +
                        ' on ' +
                        error.getFields()
                );
            }
        }
    }
}

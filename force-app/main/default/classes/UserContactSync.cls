/**
 * Decides which User saves need an employee contact refreshed, and queues that work.
 *
 * User is a setup object and Contact is not, so writing a contact in the same
 * transaction as a user save throws MIXED_DML_OPERATION. Moving the work to a
 * Queueable puts it in its own transaction, which removes the restriction and also
 * means a contact failure can never block someone from saving a user record.
 */
public with sharing class UserContactSync {
    /**
     * Set to true to suppress the sync for the rest of the transaction, for example
     * during a data load that would otherwise queue one job per batch.
     */
    public static Boolean bypass = false;

    /**
     * The user fields mirrored onto the employee contact. A save that changes none of
     * them queues no job, which keeps routine user updates (last login, a permission
     * set assignment) from churning the queue.
     */
    private static final Set<String> SYNCED_FIELDS = new Set<String>{
        'City',
        'Country',
        'Department',
        'Email',
        'Extension',
        'Fax',
        'FirstName',
        'IsActive',
        'LastName',
        'ManagerId',
        'MobilePhone',
        'Phone',
        'PostalCode',
        'State',
        'Street',
        'Title'
    };

    /**
     * Called from the after insert and after update contexts of the User trigger.
     *
     * @param newUsers the saved users (Trigger.new)
     * @param oldUsers the prior versions (Trigger.oldMap), null on insert
     */
    public static void handleAfterSave(List<User> newUsers, Map<Id, User> oldUsers) {
        if (bypass || newUsers == null || newUsers.isEmpty()) {
            return;
        }

        Set<Id> userIds = collectUserIdsNeedingSync(newUsers, oldUsers);
        if (userIds.isEmpty()) {
            return;
        }

        // A batch or future context allows only one queued job, so say why nothing
        // happened rather than letting a LimitException surface from the trigger.
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(
                LoggingLevel.WARN,
                'Employee contact sync skipped for ' +
                    userIds.size() +
                    ' user(s): this transaction has no queueable jobs left.'
            );
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

    /**
     * @param newUsers the saved users
     * @param oldUsers the prior versions, null on insert
     * @return the ids of the standard users whose employee contact is now out of date
     */
    private static Set<Id> collectUserIdsNeedingSync(List<User> newUsers, Map<Id, User> oldUsers) {
        Set<Id> userIds = new Set<Id>();
        for (User newUser : newUsers) {
            if (newUser.UserType != 'Standard') {
                continue;
            }
            User oldUser = oldUsers == null ? null : oldUsers.get(newUser.Id);
            if (oldUser == null || isSyncedFieldChanged(newUser, oldUser)) {
                userIds.add(newUser.Id);
            }
        }
        return userIds;
    }

    private static Boolean isSyncedFieldChanged(User newUser, User oldUser) {
        for (String fieldName : SYNCED_FIELDS) {
            if (newUser.get(fieldName) != oldUser.get(fieldName)) {
                return true;
            }
        }
        return false;
    }
}

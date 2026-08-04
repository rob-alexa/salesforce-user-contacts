/**
 * Keeps an employee contact in step with every standard Salesforce user.
 *
 * Only the after save contexts are declared. A trigger fires for every context it
 * names, so listing the other five just to reserve them costs a call on each user
 * save that this has nothing to do.
 */
trigger UserTrigger on User(after insert, after update) {
    UserContactSync.handleAfterSave(Trigger.new, Trigger.oldMap);
}

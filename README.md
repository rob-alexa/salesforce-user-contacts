# salesforce-user-contacts

_An employee contact record for every Salesforce user_

There are a number of reasons why it might be helpful for every Salesforce user to have a related contact record that is updated whenever certain user fields are updated. A few of those reasons might be:

- using cases for internal support, to benefit from case contact functionality
- mail merges, since Mass Email Users can't include recipient field values
- making the built-in contact hierarchy org chart work for your company

## How it works

A trigger on the after insert and after update contexts of `User` hands off to `UserContactSync`, which skips any save that changed none of the mirrored fields and queues a single `UpsertUserContact` job for the rest. That job runs in its own transaction, matches each user to their employee contact, and writes them all in one upsert.

`User` is a setup object and `Contact` is not, so the contact write has to happen asynchronously or Salesforce rejects the whole user save with `MIXED_DML_OPERATION`. The asynchronous hop also means a contact problem can never stop someone from saving a user record.

Contacts are matched on the `Contact.User` lookup. A contact that predates that field is matched on its owner instead and stamped with the lookup as it goes past, so an existing org moves onto the exact key after one sync per user.

## What is deployed

| Component                       | Purpose                                                              |
| ------------------------------- | -------------------------------------------------------------------- |
| `UserTrigger`                   | Fires on user saves                                                  |
| `UserContactSync`               | Decides what needs syncing and queues it                             |
| `UpsertUserContact`             | Queueable that mirrors users onto contacts                           |
| `EmployeeContactSettings`       | Reads the company account from custom metadata                       |
| `UserContactSyncTest`           | Apex tests                                                           |
| `Contact.User__c`               | Lookup to the user this contact mirrors, the key the sync matches on |
| `Contact.Status__c`             | Active or Inactive, from the user                                    |
| `Contact.No_Longer_There__c`    | Checked when the user is inactive                                    |
| `Contact.Extension__c`          | Phone extension, which Contact has no standard field for             |
| `Employee_Contact_Setting__mdt` | Configuration, with the `Company Account` record                     |

## Install

```bash
sf project deploy start --target-org <your-org> --test-level RunLocalTests
```

Then finish the one piece of configuration that cannot ship in source:

1. In Setup, open **Custom Metadata Types** > **Employee Contact Setting** > **Manage Employee Contact Settings** > **Company Account**.
2. Put the Id of the account that employee contacts should belong to in the **ID** field, and save.

Until that field holds an account Id the sync logs the reason and does nothing, rather than creating contacts under no account.

The user who owns the sync also needs the **Update Records with Inactive Owners** permission, because an employee contact stays owned by its user after that user is deactivated.

<a href="https://githubsfdeploy.herokuapp.com">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Upgrading from the 2020 version

The old version matched contacts by owner and by last name, and read the first record of the batch when it did it, so a save touching more than one user matched every one of them against the first user's name and manager. Two things to know before deploying over it:

- **Backfill `Contact.User__c` first if you can.** Anything the old version matched by last name alone, where the contact was not owned by its user, is invisible to the new matching and would get a second contact. This finds them:

    ```sql
    SELECT Id, Name, OwnerId FROM Contact WHERE AccountId = '<your company account Id>' AND User__c = null
    ```

- **`UpsertUserContact.execute(Set<Id>)` is now `UpsertUserContact.enqueue(Set<Id>)`.** Nothing outside this repo called it, but a custom caller would need the rename.

To resync everyone after the backfill, from anonymous Apex:

```apex
Set<Id> userIds = new Map<Id, User>([SELECT Id FROM User WHERE UserType = 'Standard' AND IsActive = true]).keySet();
UpsertUserContact.enqueue(userIds);
```

## Development

```bash
npm install
npm run prettier
npm run scan
sf project deploy start --dry-run --test-level RunSpecifiedTests --tests UserContactSyncTest
```

The last one validates and runs the tests without saving anything to the org, which is the quickest way to check a change.

CI runs formatting and Salesforce Code Analyzer on every push and pull request. The Apex test job needs a Dev Hub: set a repository secret named `DEVHUB_AUTH_URL` to a Dev Hub Sfdx Auth Url and it will create a scratch org, deploy, and run the tests. Without that secret the job reports that it was skipped rather than passing quietly.

## Notes and limits

- Only users with a `UserType` of `Standard` are synced.
- A manager whose own employee contact does not exist yet leaves **Reports To** blank; the next sync of that user fills it in.
- `Status__c` and `No_Longer_There__c` carry the same meaning in two shapes. Both are kept so existing reports and list views do not break.
- Nothing at the database level stops two contacts pointing at one user, because a lookup field cannot be marked unique. The sync converges on whichever contact it finds rather than making more.

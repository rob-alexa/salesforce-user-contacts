# Changelog

## 2.0.0

Same purpose, same field contract on the contact, rebuilt underneath.

### Fixed

- **The batch was matched against one user.** `users[0]` drove the contact lookup, the manager lookup, and the fallback map entry, so a save touching more than one user matched every one of them against the first user's last name and manager. Any save that came from the API, a data load, or a permission change on several users at once could attach the wrong contact or create duplicates.
- **A missing configuration record threw.** `companyAcctIds[0]` was read before the `isEmpty()` guard that appeared later in the same method, so an unconfigured org failed on an index out of bounds instead of skipping.
- **An empty user query threw.** `users[0]` was read without checking that the query returned anything.

### Changed

- Matching is on a new `Contact.User__c` lookup rather than owner plus last name. A contact without that lookup set is still matched by owner and stamped with it, so an existing org converges after one sync per user. See the deployment notes in the README.
- `@future` replaced by a `Queueable`. Same reason for going asynchronous (`User` is a setup object), but the job is now traceable in Apex Jobs, carries its configuration rather than re-reading statics, and can be chained.
- A save that changes none of the mirrored user fields no longer queues a job. A last login, a permission set assignment, or a password reset used to queue one.
- The trigger declares only `after insert, after update`. It previously declared all seven contexts and did nothing in five of them.
- The company account is read with `Employee_Contact_Setting__mdt.getInstance()` instead of SOQL, which costs no query and needs no test data.
- The owner is only written when it has drifted, so re-syncing a departed employee no longer needs **Update Records with Inactive Owners** for a write that changes nothing.
- `Database.upsert(records, false)` with the rejects logged, so one bad record no longer discards the batch silently.
- `UpsertUserContact.execute(Set<Id>)` is now `UpsertUserContact.enqueue(Set<Id>)`.

### Added

- Apex tests: 15 of them, covering the field mapping, the active flag, updates, the manager lookup, adoption of a pre-existing contact, the bypass, an unconfigured and a malformed setting, and bulk safety. There were none before, which meant the repo could not be deployed to a production org at all. Coverage is 90% to 100% per class.
- The custom fields and custom metadata type the Apex references. `Extension__c` and `No_Longer_There__c` were not in the repo and not in the README's prerequisites either, so a deploy into a fresh org failed to compile.
- `UserContactSync.bypass`, to suppress the sync during a data load.
- GitHub Actions CI: prettier and Salesforce Code Analyzer on every push, plus an opt-in scratch org test run.
- An MIT license.

### Housekeeping

- Converted from the metadata API `src/` layout to SFDX source format with an `sfdx-project.json`.
- API version 50.0 (Winter '21) to 67.0 (Summer '26).
- Prettier with the Apex plugin, and a Code Analyzer run that fails on anything at Moderate or worse.

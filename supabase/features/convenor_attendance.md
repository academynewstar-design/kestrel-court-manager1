# Convenor attendance

Location grants live in private `kestrel_attendance.convenors`; clients cannot assign themselves.
Senthilkumar Somasundaram (`senthil.s911@gmail.com`) is assigned to Gaetan Gervais, Oakville. Grant provisioned separately by verified email and location; no generated IDs in schema migration.

`My Team → Confirm attendance` appears only after `get_my_convenor_locations` confirms access. Admin accounts can access all locations through the same RPCs. Rejected or banned accounts have no convenor access. Convenors receive player names, court, Season/Drop-in classification and Not Going status, without payment data or contact details.

Activities combine all open, available rows with the same location, sport, date, start and end. Season assignments take priority over duplicate registrations and respect dated court overrides. Confirmed Drop-ins are included; cancelled Drop-ins and waitlists are excluded. Season cancellations and recorded Not Going are excused. Rejected/banned players are excluded. The same user appears once per activity. This pilot does not change registration, payment or absence votes.

Lists cover seven days before and after today in Toronto. Ticks can be saved starting one hour before play until seven days after the session. Final confirmation requires the session to have ended and every roster player to have a boolean mark. The UI displays unticked unexcused players and requires an acknowledgement before confirmation. It does not automatically infer nonattendance from uncompleted sheets.

Saves use a canonical activity ID, roster fingerprint and optimistic revision. Roster changes or another window's edits require reload. Draft saves do not send email. Finalization freezes the roster, records an audit history entry and queues one email to academynewstar@gmail.com if unexcused absences exist. Repeating confirmation returns the same final sheet without a second email. The existing email dispatcher delivers the queue. Corrections go to Admin through Messages; confirmed sheets are immutable in this initial version.

All tables are private, RLS enabled and deny direct client access. Four public RPCs have authenticated-only execute grants and enforce location authorization on the server. `allowed` checks the database profile and Auth ban state, not user-editable metadata. No scheduled job or new email provider is required.

Validation: `npm test`, `npm run build`, and rollback-only SQL checks in `convenor_attendance_checks.sql`. Those checks exercise authorization, court roster deduplication, cancellation and Not Going exclusions, invalid marks, stale tokens/revisions, draft save, complete finalization, email recipient/content, retry idempotency and private grants. Test emails never commit.

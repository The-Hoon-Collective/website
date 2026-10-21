# THC Supabase production deployment

Project: aqdgadheudbzvsblfvuy

1. In Supabase Dashboard > SQL Editor, execute the SQL in migrations/20261022_membership_applications.sql.
2. Deploy supabase/functions/submit-application/index.ts as an Edge Function named submit-application.
3. Set Verify JWT to OFF for this public application function. The function must have the SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables available as server-side secrets (Supabase-hosted functions commonly inject these automatically).
4. Test a valid adult application from the website. Confirm a row appears in Table Editor > membership_applications.
5. Test invalid DOB, unchecked declarations, malformed email and unexpected origins. Verify no row is created.
6. Before announcing public applications, add bot protection/rate limiting (e.g. Turnstile with server-side verification), a published privacy notice, and a documented data-retention process. The Origin check is not authentication or anti-spam protection.
7. Do not publish database secrets, service-role keys, or applicants' records in GitHub. Do not expose the private table through public RLS policies.
8. Only staff with approved Supabase dashboard access should view applications until an authenticated admin portal exists.
9. Prospect starts and full membership approvals/payments must be handled by authorised admins, not the public form. Never treat form submission as automatic membership approval.

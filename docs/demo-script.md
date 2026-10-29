# Demo Script (about 8 minutes)

Record with OBS Studio or the Windows Snipping Tool (Record). Keep the browser at 100% zoom and close unrelated tabs.

## Before you press Record

- Wake the database: run `tests/test-apim.ps1` once, about 2 minutes before recording, so the first live call is fast.
- Open these tabs in order:
  1. `docs/architecture.svg`
  2. Resource group `rg-feemgmt-demo`
  3. FeeDB > Query editor
  4. APIM > Fee API (Design tab)
  5. Entra ID > App registrations > `fee-api` > App roles
  6. Logic App `la-fee-reminders` > designer
  7. Gmail inbox (search "Fee reminder")
  8. Application Insights > Failures
- VS Code open on the project folder, with a terminal ready.
- Keys and secrets in Notepad **off screen**. Never show them in the recording.

## Script

| Time | Show | Say (in your own words) |
| --- | --- | --- |
| 0:00 | Architecture diagram | "A serverless fee system: students check fees through an API, admins update records securely, and overdue students get daily email reminders. Every call goes through API Management." |
| 0:45 | Resource group | "Everything is in one resource group in Central India: SQL database, Function App, API Management, Logic App, Application Insights." |
| 1:15 | Query editor: tables, `vw_OverdueStudents` | "Students, Administrators and an audit log. CHECK constraints stop negative fees or overpayment at the database level. The overdue view is the single definition of overdue." |
| 2:00 | VS Code: `fees.js` (scroll briefly) | "Three Node.js functions. Status is computed, not stored, so it never goes stale. Parameterised queries prevent SQL injection, and connections retry while the serverless database wakes up." |
| 2:45 | Terminal: `tests/test-apim.ps1` | "Valid key: 200, Diya Patel, Overdue. No key or wrong key: 401. Ten calls a minute, then 429 Too Many Requests: that's the APIM rate limit." |
| 3:45 | APIM: All operations policy, Subscriptions | "Subscription required on the API; the rate-limit policy on all operations; separate keys for the student app and admin tool." |
| 4:15 | Entra ID: `Fee.Admin` app role, admin client API permissions | "Admin endpoints need an Entra ID token with the Fee.Admin app role. The admin client was granted that role; the viewer client wasn't." |
| 4:45 | APIM: `admin_update_fee` policy | "validate-jwt checks the signature, expiry, audience and the roles claim before the function is called, and passes the caller's app ID on for the audit log." |
| 5:15 | Terminal: `tests/test-admin.ps1`, then jwt.ms (Claims tab) | "Admin token: list overdue, update a record, overpayment rejected with 400. Viewer token and no token: 401. Here's the token: roles = Fee.Admin." |
| 6:00 | Query editor: `SELECT * FROM dbo.FeeAuditLog` | "Every admin change is logged with who made it, old and new values, and when." |
| 6:20 | Logic App designer, retry settings, Run, run history | "Daily at 9 AM IST: query the overdue view, loop, send an email. SQL and email steps retry 4 times with exponential backoff." |
| 7:00 | Gmail inbox | "Seven reminders, one per overdue student, with name, balance, course and days overdue." |
| 7:20 | Application Insights: Failures, Performance, Logs query | "API Management and the Functions log here: 401s, 429s, 400s, response times. The KQL query breaks calls down by component, endpoint and result." |
| 7:45 | Query editor: `SELECT COUNT(*) FROM dbo.Students` (5,020) | "Tested with 5,000 extra students. Lookups use the primary key, the overdue view uses an index, and the admin list is paginated." |
| 8:00 | Back to the diagram | "Next steps for production: managed identity and Key Vault instead of passwords, private endpoints, CI/CD with GitHub Actions, a verified email domain, and student sign-in so each student sees only their own record." |

## If something fails while recording

- **500 or a long wait on the first call:** the database was asleep. Say so ("serverless auto-resume, the code retries") and run it again.
- **Rate limit triggers at call 11 or 12:** APIM's counters are distributed and approximate; mention it.

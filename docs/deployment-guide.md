# Deployment Guide: Fee Management System on Azure

This guide rebuilds the whole solution from an empty Azure subscription using the Azure portal and VS Code.
Total time is about 3 hours. Everything runs in one resource group in **Central India**.

![Architecture](architecture.svg)

## Resources created

| Resource | Name | Plan / tier | Purpose |
| --- | --- | --- | --- |
| Resource group | `rg-feemgmt-demo` | n/a | Holds everything; delete it to remove the solution |
| Azure SQL server + database | `sql-feemgmt-kaif` / `FeeDB` | General Purpose serverless, free offer | Students, Administrators, FeeAuditLog, overdue view |
| Storage account | `stfeemgmtkaif` | Standard LRS | Azure Functions runtime state (`AzureWebJobsStorage`) |
| Function App | `func-feemgmt-kaif` | Consumption (Windows), Node.js 22 | The three API endpoints |
| Application Insights | `func-feemgmt-kaif` | Workspace-based | Telemetry for the Function App and API Management |
| Logic App | `la-fee-reminders` | Consumption | Daily overdue reminders |
| API Management | `apim-feemgmt-kaif` | Consumption | Gateway: keys, rate limit, JWT validation |
| App registrations (Entra ID) | `fee-api`, `fee-admin-client`, `fee-viewer-client` | Free | `Fee.Admin` app role and client apps for testing |

## Prerequisites

- An Azure subscription (a free trial works with the plans above).
- VS Code with the **Azure Functions** and **Azure Resources** extensions (publisher: Microsoft).
- Node.js 20 or later, and Azure Functions Core Tools v4.
- PowerShell 5.1 or later for the test scripts.

## 1. Database

1. Create a resource group `rg-feemgmt-demo` in Central India.
2. Create **SQL database** `FeeDB` with a new server `sql-feemgmt-<name>`:
   - Apply the **free offer**; choose *auto-pause until next month* when the free limit is reached.
   - Authentication: **SQL and Microsoft Entra**; set a SQL admin login and password.
   - Networking: public endpoint, **Allow Azure services to access this server = Yes**, add your client IP.
3. Open **Query editor** and run, one at a time:
   1. `database/01_schema.sql`: tables, constraints, index
   2. `database/02_overdue_view.sql`: `CREATE VIEW` must run on its own
   3. `database/03_seed_data.sql`: 20 students (6 Paid, 7 Partially Paid, 7 Overdue) and 3 admins
4. Check: `SELECT * FROM dbo.vw_OverdueStudents;` returns 7 rows.

Due dates in the seed data are relative to the day you run it, so the mix of statuses is the same on any date.

## 2. Function App

1. Create a **Storage account** `st<name>` (Standard, LRS). Keep **storage account key access** enabled.
2. Create a **Function App** on the **Consumption** plan, runtime **Node.js 22**, Application Insights **on**.
   - Flex Consumption is not available on free-trial subscriptions, and Windows Consumption has no Python, hence Node.js.
3. Function App > **Settings > Environment variables > App settings**, add:

   | Name | Value |
   | --- | --- |
   | `AzureWebJobsStorage` | Storage account > Access keys > key1 **connection string** |
   | `SqlConnectionString` | `Server=<server>.database.windows.net;Database=FeeDB;User Id=<login>;Password=<password>;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30` |

   Click **Apply** on the panel *and* at the bottom of the page, then **Restart** the app.
4. Deploy the code: in VS Code open the `functions` folder, then right-click the Function App in the Azure panel > **Deploy to Function App**.
5. Check: the Function App lists `get_student_fee`, `admin_list_students`, `admin_update_fee`.
   `Code + Test` > **Test/Run** on `get_student_fee` with `studentId = 1002` returns `"status": "Overdue"`.

### Endpoints

| Method | Route (Function App) | Function |
| --- | --- | --- |
| GET | `/api/students/{studentId}/fee` | `get_student_fee` |
| GET | `/api/manage/students?status=&page=&pageSize=` | `admin_list_students` |
| PUT | `/api/manage/students/{studentId}/fee` | `admin_update_fee` |

Admin routes start with `manage/` because the Functions host reserves routes that start with `admin`.

## 3. Logic App (overdue reminders)

1. Create a **Logic App** (Consumption) `la-fee-reminders`.
2. In the designer:
   1. **Recurrence**: every 1 day, time zone *(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi*, hour 9, minute 0.
   2. **SQL Server > Execute a SQL query (V2)**: connection with SQL authentication; query
      `SELECT StudentID, Name, Email, Course, Balance, DueDate, DaysOverdue FROM dbo.vw_OverdueStudents;`
      (Pick the action under the **SQL Server** connector, not *Azure SQL Data Warehouse*.)
   3. **For each** over `body('Execute_a_SQL_query_(V2)')?['resultsets']?['Table1']`.
   4. Inside the loop, **Outlook.com > Send an email (V2)** with `To = items('For_each')?['Email']`.
   5. On both the SQL and email actions: **Settings > Retry policy = Exponential**, count 4, interval `PT10S`,
      minimum `PT5S`, maximum `PT1H`.
3. **Run** the workflow; the run history shows 7 iterations and 7 emails are delivered.

The exported definition is in `logicapp/fee-reminder-logicapp.json` (connections are stored separately; no secrets).

## 4. API Management (keys and rate limit)

1. Create **API Management** `apim-<name>`, pricing tier **Consumption**.
2. **APIs > Add API > Function App** > select the Function App and all three functions. Display name `Fee API`, URL suffix `fees`.
   APIM stores the function key as a named value and sends it to the backend.
3. **Fee API > All operations > Inbound processing**: add `apim/api-policy.xml`'s `rate-limit` line after `<base />`.
4. **Fee API > Settings**: *Subscription required* on.
5. **Subscriptions**: create `student-app` and `admin-tool`, scope **API: Fee API**.

Public base URL: `https://apim-<name>.azure-api.net/fees`.

## 5. Microsoft Entra ID (admin RBAC)

1. **App registrations > New registration** `fee-api` (single tenant):
   - **Expose an API**: set the Application ID URI to `api://<fee-api client id>`.
   - **App roles**: create `Fee Admin`, value `Fee.Admin`, allowed member types **Both**.
   - **Manifest**: `"requestedAccessTokenVersion": 2`.
2. Register `fee-admin-client`: add a **client secret**; **API permissions > My APIs > fee-api > Application permissions > Fee.Admin**;
   **Grant admin consent**.
3. Register `fee-viewer-client` with a client secret and **no** API permissions (used to show rejection).
4. In APIM, for the operations `admin_list_students` and `admin_update_fee`, add the `validate-jwt` and `set-header`
   policies from `apim/admin-operation-policy.xml` after `<base />`, keeping the generated `set-backend-service` line.
   Do **not** add them to `get_student_fee`.

## 6. Monitoring

1. APIM > **Monitoring > Application Insights > Add**: choose the Function App's Application Insights instance,
   *Use as default and enable basic logging for all APIs* on.
2. Fee API > **Settings > Diagnostics Logs > Application Insights**: enabled, sampling 100%.
3. In Application Insights: **Live metrics**, **Failures** (401 / 429 / 400), **Performance**, and **Logs**:

   ```kusto
   requests
   | where timestamp > ago(24h)
   | summarize calls = count(), avgMs = round(avg(duration), 1), failures = countif(success == false) by cloud_RoleName, name, resultCode
   | order by cloud_RoleName, calls desc
   ```

## 7. Verify

Run from the project folder (each script prompts for keys and secrets; nothing is stored):

| Script | Checks |
| --- | --- |
| `tests/test-functions-direct.ps1` | Function App directly: statuses, 404, overdue list, 400 validation, 401 without key |
| `tests/test-apim.ps1` | Through APIM: 200 with key, 401 without / wrong key, 429 after 10 calls a minute |
| `tests/test-admin.ps1` | Admin token: list (7 overdue), update, 400 validation; viewer token 401; no token 401 |

Scalability: run `database/04_load_test_5000.sql` (adds 5,000 students due in the future with `@example.com` emails, so
no reminders are sent). The overdue list and lookups stay fast. Remove them with
`DELETE FROM dbo.Students WHERE Email LIKE 'loadtest%@example.com';`

## Troubleshooting (issues hit during the build)

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Free trial subscription is not supported for Flex Consumption" | Plan restriction | Use the Consumption plan |
| Python missing from the runtime list | Windows Consumption has no Python | Use Node.js |
| Every route returns 404; log says "Unable to create client for AzureWebJobsStorage" | Function App had no storage setting | Create a storage account, add `AzureWebJobsStorage`, restart, redeploy |
| Admin routes return 404 while the student route works | Routes beginning with `admin` are reserved by the Functions host | Use `manage/...` |
| First call after idle returns 500 or takes ~30-60 s | Serverless SQL auto-resume | Retry with exponential backoff (implemented); disable auto-pause in production |
| Reminder emails land in spam | Gmail address sent through Outlook servers | Use a verified domain (Azure Communication Services Email with SPF/DKIM) in production |

## Clean-up

Delete the resource group `rg-feemgmt-demo`, then delete the three app registrations under **Entra ID > App registrations**.

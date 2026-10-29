const { app } = require('@azure/functions');
const sql = require('mssql');

// SQL errors worth retrying: serverless DB waking up, failover, throttling, network blips.
const TRANSIENT_ERRORS = ['40613', '40197', '40501', '49918', '49919', '49920'];
const TRANSIENT_CODES = ['ETIMEOUT', 'ESOCKET', 'ECONNRESET', 'ECONNCLOSED'];

const STUDENT_COLUMNS = 'StudentID, Name, Course, TotalFee, PaidAmount, DueDate';

// Fixed SQL snippets per status. User input never goes into SQL text, only as @parameters.
const STATUS_FILTERS = {
    'Paid': 'PaidAmount >= TotalFee',
    'Partially Paid': 'PaidAmount < TotalFee AND DueDate >= @today',
    'Overdue': 'PaidAmount < TotalFee AND DueDate < @today',
};

const EDITABLE_FIELDS = { totalFee: 'TotalFee', paidAmount: 'PaidAmount', dueDate: 'DueDate' };

// One connection pool per instance, reused across calls (opening a SQL connection is slow).
let poolPromise = null;

// A paused serverless database reports 40613 "not currently available" until it has resumed (up to ~1 minute).
function isTransient(err) {
    const number = String(err.number ?? err.originalError?.number ?? err.originalError?.info?.number ?? '');
    const text = `${err.message} ${err.originalError?.message ?? ''}`;
    return TRANSIENT_CODES.includes(err.code)
        || TRANSIENT_ERRORS.includes(number)
        || TRANSIENT_ERRORS.some((code) => text.includes(code))
        || /not currently available|please retry the connection later/i.test(text);
}

async function getPool(context, attempts = 6) {
    if (poolPromise) return poolPromise;
    for (let attempt = 1; attempt <= attempts; attempt++) {
        try {
            poolPromise = new sql.ConnectionPool(process.env.SqlConnectionString).connect();
            return await poolPromise;
        } catch (err) {
            poolPromise = null;
            if (attempt === attempts || !isTransient(err)) throw err;
            const wait = 2 ** attempt * 1000; // 2s, 4s, 8s, 16s, 32s (about a minute in total)
            context.warn(`SQL connection failed (attempt ${attempt}), retrying in ${wait / 1000}s: ${err.message}`);
            await new Promise((resolve) => setTimeout(resolve, wait));
        }
    }
}

// Today's date as 'YYYY-MM-DD' (UTC, same clock as Azure SQL).
function today() {
    return new Date().toISOString().slice(0, 10);
}

function paymentStatus(totalFee, paidAmount, dueDate) {
    if (paidAmount >= totalFee) return 'Paid';
    if (dueDate < today()) return 'Overdue';
    return 'Partially Paid';
}

function feeDetails(row) {
    const dueDate = row.DueDate.toISOString().slice(0, 10);
    return {
        studentId: row.StudentID,
        name: row.Name,
        course: row.Course,
        totalFee: row.TotalFee,
        paidAmount: row.PaidAmount,
        balance: Math.round((row.TotalFee - row.PaidAmount) * 100) / 100,
        dueDate,
        status: paymentStatus(row.TotalFee, row.PaidAmount, dueDate),
    };
}

function error(status, message) {
    return { status, jsonBody: { error: message } };
}

function parseField(name, value) {
    if (name === 'dueDate') {
        const valid = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
            && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
        if (!valid) throw new Error('dueDate must be a real date in YYYY-MM-DD format');
        return { type: sql.Date, value: new Date(value) };
    }
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
        throw new Error(`${name} must be a number, 0 or more`);
    }
    return { type: sql.Decimal(10, 2), value };
}

app.http('get_student_fee', {
    methods: ['GET'],
    authLevel: 'function', // needs the function key; API Management holds it, callers never see it
    route: 'students/{studentId:int}/fee',
    handler: async (request, context) => {
        const studentId = Number(request.params.studentId);
        const pool = await getPool(context);
        const result = await pool.request()
            .input('id', sql.Int, studentId)
            .query(`SELECT ${STUDENT_COLUMNS} FROM dbo.Students WHERE StudentID = @id`);
        const row = result.recordset[0];
        if (!row) return error(404, `Student ${studentId} not found`);
        return { jsonBody: feeDetails(row) };
    },
});

app.http('admin_list_students', {
    methods: ['GET'],
    authLevel: 'function',
    route: 'manage/students', // routes starting with "admin" are reserved by the Functions host
    handler: async (request, context) => {
        const status = request.query.get('status');
        if (status && !Object.hasOwn(STATUS_FILTERS, status)) {
            return error(400, `status must be one of: ${Object.keys(STATUS_FILTERS).join(', ')}`);
        }
        const page = Number(request.query.get('page') ?? 1);
        const pageSize = Number(request.query.get('pageSize') ?? 50);
        if (!Number.isInteger(page) || !Number.isInteger(pageSize)) {
            return error(400, 'page and pageSize must be whole numbers');
        }
        const safePage = Math.max(page, 1);
        const safeSize = Math.min(Math.max(pageSize, 1), 200);
        const where = status ? `WHERE ${STATUS_FILTERS[status]}` : '';

        const pool = await getPool(context);
        const result = await pool.request()
            .input('today', sql.Date, new Date(today()))
            .input('offset', sql.Int, (safePage - 1) * safeSize)
            .input('size', sql.Int, safeSize)
            .query(`SELECT ${STUDENT_COLUMNS} FROM dbo.Students ${where} `
                + 'ORDER BY StudentID OFFSET @offset ROWS FETCH NEXT @size ROWS ONLY');

        return {
            jsonBody: {
                page: safePage,
                pageSize: safeSize,
                count: result.recordset.length,
                students: result.recordset.map(feeDetails),
            },
        };
    },
});

app.http('admin_update_fee', {
    methods: ['PUT'],
    authLevel: 'function',
    route: 'manage/students/{studentId:int}/fee',
    handler: async (request, context) => {
        const studentId = Number(request.params.studentId);
        let body;
        try {
            body = await request.json();
        } catch {
            return error(400, 'Body must be valid JSON');
        }
        const keys = body && typeof body === 'object' && !Array.isArray(body) ? Object.keys(body) : [];
        if (keys.length === 0 || keys.some((k) => !Object.hasOwn(EDITABLE_FIELDS, k))) {
            return error(400, `Send one or more of: ${Object.keys(EDITABLE_FIELDS).join(', ')}`);
        }
        let values;
        try {
            values = keys.map((k) => [k, parseField(k, body[k])]);
        } catch (err) {
            return error(400, `Invalid value: ${err.message}`);
        }
        const setClause = values.map(([k]) => `${EDITABLE_FIELDS[k]} = @${k}`).join(', ');
        // Set by API Management from the verified Entra token, so the caller can't fake it.
        const changedBy = request.headers.get('x-changed-by') ?? 'unknown';

        const pool = await getPool(context);
        const transaction = new sql.Transaction(pool);
        await transaction.begin();
        try {
            const update = new sql.Request(transaction).input('id', sql.Int, studentId);
            for (const [k, field] of values) update.input(k, field.type, field.value);
            const result = await update.query(
                `UPDATE dbo.Students SET ${setClause}, LastUpdated = SYSUTCDATETIME() `
                + 'OUTPUT deleted.TotalFee AS OldTotalFee, deleted.PaidAmount AS OldPaidAmount, '
                + 'deleted.DueDate AS OldDueDate, inserted.StudentID, inserted.Name, inserted.Course, '
                + 'inserted.TotalFee, inserted.PaidAmount, inserted.DueDate '
                + 'WHERE StudentID = @id');
            const row = result.recordset[0];
            if (!row) {
                await transaction.rollback();
                return error(404, `Student ${studentId} not found`);
            }

            await new sql.Request(transaction)
                .input('id', sql.Int, row.StudentID)
                .input('changedBy', sql.NVarChar(200), changedBy)
                .input('oldTotal', sql.Decimal(10, 2), row.OldTotalFee)
                .input('newTotal', sql.Decimal(10, 2), row.TotalFee)
                .input('oldPaid', sql.Decimal(10, 2), row.OldPaidAmount)
                .input('newPaid', sql.Decimal(10, 2), row.PaidAmount)
                .input('oldDue', sql.Date, row.OldDueDate)
                .input('newDue', sql.Date, row.DueDate)
                .query('INSERT INTO dbo.FeeAuditLog (StudentID, ChangedBy, OldTotalFee, NewTotalFee, '
                    + 'OldPaidAmount, NewPaidAmount, OldDueDate, NewDueDate) '
                    + 'VALUES (@id, @changedBy, @oldTotal, @newTotal, @oldPaid, @newPaid, @oldDue, @newDue)');

            await transaction.commit(); // update + audit row saved together, or neither
            context.log(`Fee record ${studentId} updated by ${changedBy}: ${JSON.stringify(body)}`);
            return { jsonBody: feeDetails(row) };
        } catch (err) {
            await transaction.rollback().catch(() => {});
            // 547 = CHECK constraint violated (paid more than the total, or a negative fee)
            if (err.number === 547) return error(400, 'Paid amount cannot exceed total fee');
            throw err;
        }
    },
});

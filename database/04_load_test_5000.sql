-- Adds 5,000 extra students for the scalability test.
-- Due dates are all in the future and emails are @example.com, so no reminder emails go out.
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS date);

WITH n AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Students (Name, Email, Course, TotalFee, PaidAmount, DueDate)
SELECT CONCAT('Load Test Student ', i),
       CONCAT('loadtest', i, '@example.com'),
       CHOOSE(i % 5 + 1, 'BCA', 'BBA', 'B.Com', 'MBA', 'B.Sc CS'),
       90000,
       (i % 4) * 30000,
       DATEADD(day, i % 60 + 1, @today)
FROM n;

SELECT COUNT(*) AS TotalStudents FROM dbo.Students;

-- Remove the test rows afterwards:
-- DELETE FROM dbo.Students WHERE Email LIKE 'loadtest%@example.com';

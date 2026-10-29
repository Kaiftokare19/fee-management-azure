-- The single definition of "overdue", read by the Logic App.
CREATE VIEW dbo.vw_OverdueStudents AS
SELECT StudentID, Name, Email, Course, TotalFee, PaidAmount,
       TotalFee - PaidAmount AS Balance,
       DueDate,
       DATEDIFF(day, DueDate, CAST(SYSUTCDATETIME() AS date)) AS DaysOverdue
FROM dbo.Students
WHERE PaidAmount < TotalFee
  AND DueDate < CAST(SYSUTCDATETIME() AS date);

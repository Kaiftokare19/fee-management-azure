-- Run this first. Then run 02_overdue_view.sql separately (CREATE VIEW must run on its own).

CREATE TABLE dbo.Students (
    StudentID   INT IDENTITY(1001, 1) PRIMARY KEY,
    Name        NVARCHAR(100)  NOT NULL,
    Email       NVARCHAR(255)  NOT NULL,   -- not in the brief, needed for reminders
    Course      NVARCHAR(100)  NOT NULL,
    TotalFee    DECIMAL(10, 2) NOT NULL,
    PaidAmount  DECIMAL(10, 2) NOT NULL CONSTRAINT DF_Students_Paid DEFAULT 0,
    DueDate     DATE           NOT NULL,
    LastUpdated DATETIME2      NOT NULL CONSTRAINT DF_Students_Updated DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Students_Fee  CHECK (TotalFee >= 0),
    CONSTRAINT CK_Students_Paid CHECK (PaidAmount >= 0 AND PaidAmount <= TotalFee)
);

-- Speeds up overdue / status searches when there are thousands of students
CREATE INDEX IX_Students_DueDate ON dbo.Students (DueDate) INCLUDE (TotalFee, PaidAmount);

CREATE TABLE dbo.Administrators (
    AdminID INT IDENTITY(1, 1) PRIMARY KEY,
    Name    NVARCHAR(100) NOT NULL,
    Role    NVARCHAR(50)  NOT NULL CONSTRAINT CK_Admin_Role CHECK (Role IN ('FeeAdmin', 'FeeViewer'))
);

-- Every admin change is recorded: who, when, old value, new value
CREATE TABLE dbo.FeeAuditLog (
    AuditID       INT IDENTITY(1, 1) PRIMARY KEY,
    StudentID     INT            NOT NULL REFERENCES dbo.Students (StudentID),
    ChangedBy     NVARCHAR(200)  NOT NULL,
    OldTotalFee   DECIMAL(10, 2) NOT NULL,
    NewTotalFee   DECIMAL(10, 2) NOT NULL,
    OldPaidAmount DECIMAL(10, 2) NOT NULL,
    NewPaidAmount DECIMAL(10, 2) NOT NULL,
    OldDueDate    DATE           NOT NULL,
    NewDueDate    DATE           NOT NULL,
    ChangedAt     DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

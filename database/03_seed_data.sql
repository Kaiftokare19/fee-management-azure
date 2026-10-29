-- 20 sample students. Due dates are relative to today, so the demo always shows
-- 6 Paid, 7 Partially Paid and 7 Overdue whichever day it runs.
-- Emails use Gmail "+" addresses, so every reminder lands in one inbox.
DECLARE @g NVARCHAR(50) = 'kaiftokare19';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS date);

INSERT INTO dbo.Students (Name, Email, Course, TotalFee, PaidAmount, DueDate) VALUES
('Aarav Sharma',    CONCAT(@g, '+s01@gmail.com'), 'BCA',     85000,  85000,  DATEADD(day, -30, @today)),
('Diya Patel',      CONCAT(@g, '+s02@gmail.com'), 'BBA',     90000,  45000,  DATEADD(day, -15, @today)),
('Rohan Mehta',     CONCAT(@g, '+s03@gmail.com'), 'B.Com',   60000,  20000,  DATEADD(day,  20, @today)),
('Ananya Iyer',     CONCAT(@g, '+s04@gmail.com'), 'MBA',    150000, 150000,  DATEADD(day,  -5, @today)),
('Kabir Singh',     CONCAT(@g, '+s05@gmail.com'), 'B.Sc CS', 95000,      0,  DATEADD(day,  -7, @today)),
('Ishita Rao',      CONCAT(@g, '+s06@gmail.com'), 'BCA',     85000,  60000,  DATEADD(day,  10, @today)),
('Vivaan Gupta',    CONCAT(@g, '+s07@gmail.com'), 'MBA',    150000,  75000,  DATEADD(day, -20, @today)),
('Meera Nair',      CONCAT(@g, '+s08@gmail.com'), 'B.Com',   60000,  60000,  DATEADD(day,  15, @today)),
('Arjun Reddy',     CONCAT(@g, '+s09@gmail.com'), 'BBA',     90000,  30000,  DATEADD(day,  30, @today)),
('Saanvi Joshi',    CONCAT(@g, '+s10@gmail.com'), 'B.Sc CS', 95000,  95000,  DATEADD(day, -45, @today)),
('Aditya Kulkarni', CONCAT(@g, '+s11@gmail.com'), 'BCA',     85000,  40000,  DATEADD(day,  -3, @today)),
('Myra Desai',      CONCAT(@g, '+s12@gmail.com'), 'MBA',    150000, 100000,  DATEADD(day,  25, @today)),
('Reyansh Shah',    CONCAT(@g, '+s13@gmail.com'), 'B.Com',   60000,      0,  DATEADD(day,  40, @today)),
('Kiara Menon',     CONCAT(@g, '+s14@gmail.com'), 'BBA',     90000,  90000,  DATEADD(day, -10, @today)),
('Dhruv Chopra',    CONCAT(@g, '+s15@gmail.com'), 'B.Sc CS', 95000,  50000,  DATEADD(day,  -1, @today)),
('Anika Bose',      CONCAT(@g, '+s16@gmail.com'), 'BCA',     85000,  85000,  DATEADD(day,   5, @today)),
('Ayaan Khan',      CONCAT(@g, '+s17@gmail.com'), 'MBA',    150000, 120000,  DATEADD(day, -12, @today)),
('Navya Pillai',    CONCAT(@g, '+s18@gmail.com'), 'B.Com',   60000,  30000,  DATEADD(day,  12, @today)),
('Arnav Verma',     CONCAT(@g, '+s19@gmail.com'), 'BBA',     90000,  10000,  DATEADD(day, -25, @today)),
('Tara Malhotra',   CONCAT(@g, '+s20@gmail.com'), 'B.Sc CS', 95000,  70000,  DATEADD(day,  18, @today));

INSERT INTO dbo.Administrators (Name, Role) VALUES
('Priya Kapoor',   'FeeAdmin'),
('Rahul Jain',     'FeeAdmin'),
('Sneha Kulkarni', 'FeeViewer');

/*
		Initial EDA
*/
-- Overview of Dataset
SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
--WHERE PCN = 'N.030028'
--WHERE Department = 'PAR' AND Salary <=10000
--WHERE Salary < 10000 -- Can infer that the majority of workers working in this lower income bracket are Non Exempt Staff having an hourly wage
--WHERE Salary >= 10000
ORDER BY Salary DESC

-- Investigating NULL values and 0 Values, possibility to request for data for PCN N.030010 & N.030141 from REA 011 Board of Equalization and GRD 010 Voter Registration and Elections respectively
SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary IS NULL OR SALARY = 0

-- Checking on department of 'Activity Center Assistant Leader', which has the highest count of non-exempt employees
SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary >= 10000
AND FLSA_Status = 'Non Exempt'
ORDER BY Salary DESC

-- Concluding that 'Lower Income Bracket' actually consists of hourly salaried workers with 'Clerk Cashier'
SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Position_Title = 'Clerk Cashier'
ORDER BY Salary DESC

/*
		SQL Query to create categorical column "Hourly_Annual_Salaried_Employee". For Salary <=10000 we use "Hourly Salaried Employee" and for  Salary > 10000 we use "Annual Salaried Employee"
*/
-- Run this to drop self-created categorical column
ALTER TABLE EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
DROP COLUMN IF EXISTS Hourly_Annual_Salaried_Employee;

-- Adds an empty column name called 'Hourly_Annual_Salaried_Employee'
ALTER TABLE EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
ADD Hourly_Annual_Salaried_Employee VARCHAR(50);

-- Updates 'Hourly_Annual_Salaried_Employee' column with 'Hourly Salaried Employee' & 'Annual Salaried Employee' based on salary
UPDATE EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
SET Hourly_Annual_Salaried_Employee = 
    CASE 
        WHEN Salary <= 10000 THEN 'Hourly Salaried Employee'
        WHEN Salary > 10000 THEN 'Annual Salaried Employee'
    END;

-- Sanity Check for added columns
SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ 
WHERE Salary <= 10000
ORDER BY Salary DESC -- We see that first few rows of Salary <= 10,000 is correctly labelled as 'Hourly Salaried Employee'

SELECT *
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ 
WHERE Salary > 10000
ORDER BY Salary DESC -- We see that first few rows of Salary > 10,000 is correctly labelled as 'Hourly Salaried Employee'

-- Sanity Check for duplicates within PCN. Duplicates are present within dataset but duplicate PCN were confirmed to have mostly same salary values & the same department for duplicate PCN rows. This means that we can proceed with building our SQL query without much worry. I.E. In a 'dirtier' dataset, the same unique PCN ID employee might be incorrectly listed that he/she is present in 2/3 more departments without changing position title and having a wide spread of salary range.
SELECT PCN, Department, Department_Division, Position_Title, FLSA_Status, Initial_Hire_date, Date_in_Title, Salary, COUNT(PCN) OVER (PARTITION BY PCN) AS Count_of_PCN_ID
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
GROUP BY PCN, Department, Department_Division, Position_Title, FLSA_Status, Initial_Hire_date, Date_in_Title, Salary
HAVING COUNT(PCN) > 1
ORDER BY PCN

/*
		Iteratively building upon queries to obtain our final query which has:
		Coefficient of Variation [CV], Dept Avg Salary, Dept Std Dev, Outlier Count,
		in order to identify departments with strong salary disparity
*/
-- Group by department and obtain the Standard Deviation and Average [via CTE]. Filter out all salaries <= 10,000 as confirmed in initial EDA that a significant number of employees whose salaries fall in the lower income bracket of <=$10,000 are mainly made up of non-exempt staff (~1124 employees) as compared to exempt staff (~13 employees) as found in the corresponding EDA in the accompanying JupyterNotebook
WITH DepartmentStats AS
(SELECT Department,
	   STDEV(salary) AS Dept_Std_Dev_Salary,
	   AVG(salary) AS Dept_Avg_Salary
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary > 10000
GROUP BY Department)
SELECT *
FROM DepartmentStats

-- Creation of Department Outliers, based on Z-Score. Join DepartmentStats w/ original table
WITH DepartmentStats AS
(SELECT Department,
	   STDEV(salary) AS Dept_Std_Dev_Salary,
	   AVG(salary) AS Dept_Avg_Salary
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary > 10000
GROUP BY Department)
SELECT emp.Department, emp.Salary, ds.Dept_Std_Dev_Salary, ds.Dept_Avg_Salary,
		(emp.Salary - ds.Dept_Avg_Salary)/ds.Dept_Std_Dev_Salary AS Z_Score
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ AS emp
INNER JOIN DepartmentStats AS ds ON emp.Department = ds.Department
ORDER BY Department ASC

-- Z-Score Calculation
WITH DepartmentStats AS
(SELECT Department,
	   STDEV(salary) AS Dept_Std_Dev_Salary,
	   AVG(salary) AS Dept_Avg_Salary
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary > 10000
GROUP BY Department)
SELECT emp.Department, emp.Salary, ds.Dept_Std_Dev_Salary, ds.Dept_Avg_Salary,
		(emp.Salary - ds.Dept_Avg_Salary)/ds.Dept_Std_Dev_Salary AS Z_Score
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ AS emp
INNER JOIN DepartmentStats AS ds ON emp.Department = ds.Department
WHERE emp.Salary > 10000
ORDER BY Department ASC

-- Finding Z_Score MIN and MAX
WITH DepartmentStats AS
(SELECT Department,
	   STDEV(salary) AS Dept_Std_Dev_Salary,
	   AVG(salary) AS Dept_Avg_Salary
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary > 10000
GROUP BY Department
),
Z_Score_Table AS (
SELECT emp.Department,
(Salary - ds.Dept_Avg_Salary)/ds.Dept_Std_Dev_Salary AS Z_Score
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ AS emp
INNER JOIN DepartmentStats AS ds ON emp.Department = ds.Department
WHERE emp.Salary > 10000)
SELECT MIN(Z_Score) AS Z_Score_Min, MAX(Z_Score) AS Z_Score_Max
FROM DepartmentStats AS ds
INNER JOIN Z_Score_Table AS z ON ds.Department = z.Department

/*
		FINAL QUERY USED FOR ANALYSIS: Dept Std Dev, Avg Salary, CV, Outlier Count based off Z-Score values
*/
WITH DepartmentStats AS
(SELECT Department,
	   STDEV(salary) AS Dept_Std_Dev_Salary,
	   AVG(salary) AS Dept_Avg_Salary
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$
WHERE Salary > 10000
GROUP BY Department
),
DepartmentOutliers AS (
SELECT emp.Department, emp.Salary, ds.Dept_Std_Dev_Salary, ds.Dept_Avg_Salary,
		(emp.Salary - ds.Dept_Avg_Salary)/ds.Dept_Std_Dev_Salary AS Z_Score
FROM EmployeeSalaries_Disparity_Dataset.dbo.Employee_Salaries$ AS emp
INNER JOIN DepartmentStats AS ds ON emp.Department = ds.Department
WHERE emp.Salary > 10000
)
SELECT ds.Department,
	   ROUND(ds.Dept_Std_Dev_Salary,2) AS Dept_Std_Dev_Salary,
	   ROUND(ds.Dept_Avg_Salary,2) AS Dept_Avg_Salary,
	   ROUND((ds.Dept_Std_Dev_Salary / ds.Dept_Avg_Salary),2)*100 AS CoefficientOfVariation, -- % Coefficient of variation measures the relative variability of data; lower values indicate less variability, while higher values indicate more variability.
	   SUM(CASE WHEN (do.Z_Score > 1.96 OR do.Z_Score < -1.96) THEN 1 ELSE 0 END) AS Outlier_Count -- Tweakable Z_Score Threshold Values
FROM DepartmentStats AS ds
LEFT JOIN DepartmentOutliers AS do ON ds.Department = do.Department
GROUP BY ds.Department, ds.Dept_Std_Dev_Salary, ds.Dept_Avg_Salary, (ds.Dept_Std_Dev_Salary / ds.Dept_Avg_Salary)
ORDER BY Outlier_Count DESC, CoefficientOfVariation DESC
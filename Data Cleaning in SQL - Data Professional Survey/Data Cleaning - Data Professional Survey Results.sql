-- PREREQUISITES
-- Create a schema to which the table is created in

-- Raw data: Do not modify
CREATE TABLE dps_raw (
	unique_id TEXT,
    email TEXT,
    date_taken TEXT,
    time_taken TEXT,
    browser TEXT,
    os TEXT,
    city TEXT,
    country TEXT,
    referrer TEXT,
    time_spent_answering TEXT,
    current_role TEXT,
    switched_career_to_data TEXT,
    annual_salary_usd TEXT,
    current_industry TEXT,
    favorite_programming_language TEXT,
    satisfaction_salary TINYINT UNSIGNED,
    satisfaction_worklife_balance TINYINT UNSIGNED,
    satisfaction_coworkers TINYINT UNSIGNED,
    satisfaction_management TINYINT UNSIGNED,
    satisfaction_upward_mobility TINYINT UNSIGNED,
    satisfaction_learning TINYINT UNSIGNED,
    difficulty_breaking_to_data TEXT,
    priority_in_new_job TEXT,
    gender TEXT,
    age TINYINT UNSIGNED,
    country_of_residence TEXT,
    education TEXT,
    ethnicity TEXT
);

-- After table 'dps_raw' is created, the CSV data needs to be imported to it. I used the
-- table data import wizard in MySQL Workbench for this.

-- Working copy
CREATE TABLE dps LIKE dps_raw;

-- Copy data from the raw table to the working copy
INSERT INTO dps (SELECT * FROM dps_raw);

SELECT * FROM dps;

-- --------------------------------------------------------------------------------------------------
-- CHECKING FOR AND REMOVING ANY REDUNDANT DUPLICATES

-- Using time details and basic deomgraphics to initially search for duplicates: No duplicates found.
SELECT *
FROM (
	SELECT
		*,
		ROW_NUMBER() OVER(PARTITION BY date_taken, time_taken, time_spent_answering,
									   gender, age, country_of_residence)
			AS row_num
	FROM
		dps)
	AS subquery
WHERE subquery.row_num > 1;

-- --------------------------------------------------------------------------------------------------
-- BREAKING ANNUAL SALARY RANGE IN TO LOWER AND UPPER BOUNDS

-- By default, salaries are given as ranges. That's fine, but let's also extract the lower and upper
-- bounds of the ranges into separate columns.
SELECT DISTINCT annual_salary_usd
FROM dps
ORDER BY 1;

ALTER TABLE dps
	ADD COLUMN annual_salary_lower_bound TINYINT UNSIGNED,
    ADD COLUMN annual_salary_upper_bound TINYINT UNSIGNED;

-- Using a CTE to create a reference table for lower and upper bounds of each predefined salary range,
-- and populating the newly created column using the reference CTE
WITH bounds AS (
	SELECT
		sub.annual_salary_usd AS salary_range,
		CASE
			WHEN sub.ind <> 0 THEN
				TRIM(TRAILING 'k' FROM LEFT(sub.annual_salary_usd, sub.ind - 1))
			ELSE
				TRIM(TRAILING 'k+' FROM RIGHT(sub.annual_salary_usd,
					 LENGTH(sub.annual_salary_usd) - sub.ind))
		END AS lower_bound,
		CASE
			WHEN sub.ind <> 0 THEN
				TRIM(TRAILING 'k' FROM RIGHT(sub.annual_salary_usd,
					 LENGTH(sub.annual_salary_usd) - sub.ind))
			ELSE NULL
		END AS upper_bound
	FROM (
		SELECT
			annual_salary_usd,
			POSITION('-' IN annual_salary_usd) AS ind
		FROM dps
		GROUP BY annual_salary_usd
	) AS sub
)
UPDATE dps
	SET
		annual_salary_lower_bound = 
			(SELECT bounds.lower_bound FROM bounds
			 WHERE dps.annual_salary_usd = bounds.salary_range),
        annual_salary_upper_bound =
			(SELECT bounds.upper_bound FROM bounds
             WHERE dps.annual_salary_usd = bounds.salary_range);

-- Now all records include the corresponding lower and upper bounds of the salary range
SELECT annual_salary_usd, annual_salary_lower_bound, annual_salary_upper_bound
FROM dps;

-- --------------------------------------------------------------------------------------------------
-- STANDARDIZING DATA

-- Splitting columns where any type of Other option was a choice in such a way, that only
-- predefined values are left to their original columns. For records where the aforementioned other
-- option was used, the respondent specified value, i.e. the freely written answers in these columns
-- are copied to a new column and the original is set as 'Other'.

-- STANDARDIZING 'current_role'

ALTER TABLE dps
ADD COLUMN current_role_specified TEXT;

-- Let's check the values
SELECT current_role, COUNT(current_role)
FROM dps
GROUP BY current_role
ORDER BY 2 DESC;

-- There seems to be quite many instances of Business Analysts in the custom answers, so let's
-- create a new category 'Business Analyst' in the main column, i.e. 'current_role'.
SELECT current_role
FROM dps
WHERE current_role LIKE '%business analys%';

UPDATE dps
	SET current_role = 'Business Analyst'
WHERE current_role LIKE '%business analys%';

-- Copy rest of the custom answers to the newly created column, removing the prefix in the
-- process
UPDATE dps
	SET current_role_specified = TRIM(REPLACE(current_role, 'Other (Please Specify):', ''))
WHERE current_role LIKE 'Other (Please Specify):%';

-- In 'current_role', change the custom answers to 'Other'
UPDATE dps
	SET current_role = 'Other'
WHERE current_role LIKE 'Other (Please Specify)%';

-- Just so that everything is similarily formatted
UPDATE dps
	SET
		current_role = UPPER(current_role),
        current_role_specified = UPPER(current_role_specified);

SELECT current_role, COUNT(current_role)
FROM dps
GROUP BY current_role
ORDER BY 2 DESC;

-- As seen here, the custom answers could be cleaned quite a bit, but that is a little
-- project for another time for now
SELECT current_role_specified, COUNT(current_role_specified)
FROM dps
GROUP BY current_role_specified
ORDER BY 2 DESC;

-- --------------------------------------------------------------------------------------------------
-- STANDARDIZING 'current_industry'

ALTER TABLE dps
ADD COLUMN current_industry_specified TEXT;

-- Checking answers again
SELECT current_industry, COUNT(current_industry)
FROM dps
GROUP BY current_industry
ORDER BY 2 DESC;

-- There are some custom answers that pop-up frequently, and with slightly different names, but
-- let's not make any new categories to the main column other than 'Other' category. Let's move
-- all the custom answers to the newly created column for now.
SELECT current_industry, COUNT(current_industry)
FROM dps
GROUP BY current_industry
ORDER BY 2 DESC;

-- Copy the custom answers to the newly column
UPDATE dps
	SET current_industry_specified = TRIM(REPLACE(current_industry, 'Other (Please Specify):', ''))
WHERE current_industry LIKE 'Other (Please Specify):%';

-- In the main column, change custom answers to 'Other'
UPDATE dps
	SET current_industry = 'Other'
WHERE current_industry LIKE 'Other (Please Specify):%';

-- Industry isn't specified: Set to NULL
UPDATE dps
	SET current_industry = NULL
WHERE current_industry = 'Other (Please Specify)';

UPDATE dps
	SET 
		current_industry = UPPER(current_industry),
		current_industry_specified = UPPER(current_industry_specified);

-- Main column after changes
SELECT current_industry, COUNT(current_industry)
FROM dps
GROUP BY current_industry
ORDER BY 2 DESC;

-- As seen here aswell, the custom answers could be cleaned quite a bit, but that is a little
-- project for another time for now
SELECT current_industry_specified, COUNT(current_industry_specified)
FROM dps
GROUP BY current_industry_specified
ORDER BY 2 DESC;

-- --------------------------------------------------------------------------------------------------
-- STANDARDIZING 'country_of_residence'
-- For this one, the custom answers will not be moved to a new column and instead, the prefix
-- is just removed in the main column and answers are reformatted

-- Inspect answers
SELECT country_of_residence, COUNT(country_of_residence)
FROM dps
GROUP BY country_of_residence
ORDER BY 2 DESC;

-- Remove prefix
UPDATE dps 
	SET country_of_residence = TRIM(REPLACE(country_of_residence, 'Other (Please Specify):', ''))
WHERE country_of_residence LIKE 'Other (Please Specify):%';

-- Removing prefix where no specification was given, i.e. field is essentially empty
UPDATE dps
	SET country_of_residence = TRIM(REPLACE(country_of_residence, 'Other (Please Specify)', ''))
WHERE country_of_residence LIKE 'Other (Please Specify)%';

-- Setting blank values as NULL and otherwise changing values to uppercase
UPDATE dps
	SET country_of_residence = CASE
		WHEN LENGTH(TRIM(country_of_residence)) = 0 THEN NULL
		ELSE UPPER(TRIM(country_of_residence))
	END;

-- After changes. Includes spelling mistakes and unidentifiable values, but cleaning these will
-- have to wait for now.
SELECT country_of_residence, COUNT(country_of_residence)
FROM dps
GROUP BY country_of_residence
ORDER BY 2 DESC;
    
-- --------------------------------------------------------------------------------------------------
-- STANDARDIZING 'priority_in_new_job'

-- Inspect inital values
SELECT priority_in_new_job, COUNT(priority_in_new_job)
FROM dps
GROUP BY priority_in_new_job
ORDER BY 2 DESC;

ALTER TABLE dps
ADD COLUMN priority_in_new_job_specified TEXT;

-- Let's group all these in to a new category: Learning/Development
-- Note: THis category is not one of the predefined ones, and likely due to this does not have
-- nearly as much occurances as the other predefined categories.
SELECT priority_in_new_job
FROM dps
WHERE 
	priority_in_new_job LIKE '%learn%' OR
	priority_in_new_job LIKE '%grow%' OR
    priority_in_new_job LIKE '%develop%';

-- Create new category 'Learning/Development'
UPDATE dps
	SET priority_in_new_job = 'Learning/Development'
WHERE 
	priority_in_new_job LIKE '%learn%' OR
	priority_in_new_job LIKE '%grow%' OR
    priority_in_new_job LIKE '%develop%';

-- Copy rest of the freely written answers to the newly created column
UPDATE dps
	SET priority_in_new_job_specified = 
		TRIM(REPLACE(priority_in_new_job, 'Other (Please Specify):', ''))
WHERE priority_in_new_job LIKE 'Other (Please Specify):%';

-- In the main column, set freely written answers to Other category
UPDATE dps
	SET priority_in_new_job = 'Other'
WHERE priority_in_new_job LIKE 'Other (Please Specify):%';

-- Format both columns
UPDATE dps SET
	priority_in_new_job = UPPER(priority_in_new_job),
    priority_in_new_job_specified = UPPER(priority_in_new_job_specified);

-- Main column after changes
SELECT priority_in_new_job, COUNT(priority_in_new_job)
FROM dps
GROUP BY priority_in_new_job
ORDER BY 2 DESC;

-- These are quite a mess and could be cleaned up, but let's leave them as is for now
SELECT priority_in_new_job_specified, COUNT(priority_in_new_job_specified)
FROM dps
GROUP BY priority_in_new_job_specified
ORDER BY 2 DESC;

-- --------------------------------------------------------------------------------------------------
-- STANDARDIZING 'favorite_programming_languge'

ALTER TABLE dps
ADD COLUMN favorite_programming_language_specified TEXT;

-- Let's check the responses:
-- In freely written answers, SQL is frequently mention. Let's inspect this more next.
SELECT favorite_programming_language, COUNT(favorite_programming_language)
FROM dps
GROUP BY favorite_programming_language
ORDER BY 2 DESC;

-- There are some instances where SQL and Excel are both mentioned, so let's leave these cases
-- untouched
SELECT favorite_programming_language, COUNT(favorite_programming_language)
FROM dps
GROUP BY favorite_programming_language
HAVING favorite_programming_language LIKE '%SQL%';

-- Let's create a new category: SQL
UPDATE dps
	SET favorite_programming_language = 'SQL'
WHERE
	favorite_programming_language LIKE '%SQL%' AND
    favorite_programming_language NOT LIKE '%EXCEL%';
    
-- Copy rest of the freely written answers to the newly created column
UPDATE dps
	SET favorite_programming_language_specified = 
		TRIM(REPLACE(favorite_programming_language, 'Other:', ''))
WHERE favorite_programming_language LIKE 'Other:%';

-- Removing prefix where no specification was given, i.e. field is essentially empty: Change these
-- to NULL (these are cases where 'favorite_programming_language' is set as 'Other' without the
-- trailing colon)
UPDATE dps
	SET favorite_programming_language = NULL
WHERE TRIM(favorite_programming_language) LIKE 'Other';

-- In the main column, set rest of the freely written answers to category Other
UPDATE dps
	SET favorite_programming_language = 'Other'
WHERE favorite_programming_language LIKE 'Other:%';


-- Reformat both columns
UPDATE dps SET
	favorite_programming_language = UPPER(favorite_programming_language),
    favorite_programming_language_specified = UPPER(favorite_programming_language_specified);

-- Main column after changes
SELECT favorite_programming_language, COUNT(favorite_programming_language)
FROM dps
GROUP BY favorite_programming_language
ORDER BY 2 DESC;

-- Custom answers. Could do with some further cleaning aswell.
SELECT favorite_programming_language_specified, COUNT(favorite_programming_language_specified)
FROM dps
GROUP BY favorite_programming_language_specified
ORDER BY 2 DESC;

-- --------------------------------------------------------------------------------------------------
-- Set blank values in 'education' as NULL
UPDATE dps
	SET education = NULL
WHERE LENGTH(TRIM(education)) = 0;

-- --------------------------------------------------------------------------------------------------
-- FORMATTING REST OF THE COLUMNS SIMILARILY TO THE PREVIOUS ONES
UPDATE dps SET
	gender = UPPER(gender),
    switched_career_to_data = UPPER(switched_career_to_data),
    difficulty_breaking_to_data = UPPER(difficulty_breaking_to_data);
    
-- --------------------------------------------------------------------------------------------------
-- REMOVING UNNECESSARY COLUMNS: unique_id, email, date_taken, time_taken, browser, os, city, country,
 -- referrer, time_spent_answering, ethnicity,

ALTER TABlE dps
	DROP COLUMN	unique_id,
    DROP COLUMN	email,
    DROP COLUMN date_taken,
    DROP COLUMN time_taken,
    DROP COLUMN	browser,
    DROP COLUMN	os,
    DROP COLUMN	city,
    DROP COLUMN	country,
    DROP COLUMN	referrer,
    DROP COLUMN	time_spent_answering,
    DROP COLUMN	ethnicity;
    
-- --------------------------------------------------------------------------------------------------
-- THE FINAL RESULT: CLEANED SURVEY RESULT READY FOR EXPLORATORY DATA ANALYSIS 
SELECT *
FROM dps;

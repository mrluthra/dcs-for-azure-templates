-- This file includes the queries from the following scripts:
-- * V2024.01.01.0__create_initial_tables
-- * V2024.04.18.0__add_adls_to_adls_support
-- * V2024.05.02.0__update_adls_to_adls_support
-- * V2024.06.04.0__add_logging_and_reset_flags
-- The contents of each of those files will


-- source: V2024.01.01.0__create_initial_tables
CREATE TABLE discovered_ruleset(
   dataset VARCHAR(255) NOT NULL,
   specified_database VARCHAR(255) NOT NULL,
   specified_schema VARCHAR(255) NOT NULL,
   identified_table VARCHAR(255) NOT NULL,
   identified_column VARCHAR(255) NOT NULL,
   identified_column_type VARCHAR(100) NOT NULL,
   identified_column_max_length INT NOT NULL,
   ordinal_position INT NOT NULL,
   row_count BIGINT,
   metadata NVARCHAR(MAX),
   profiled_domain VARCHAR(100),
   profiled_algorithm VARCHAR(100),
   confidence_score DECIMAL(6,5),
   rows_profiled BIGINT DEFAULT 0,
   assigned_algorithm VARCHAR(100),
   last_profiled_updated_timestamp DATETIME
);
ALTER TABLE
   discovered_ruleset ADD CONSTRAINT discovered_ruleset_pk
   PRIMARY KEY ("dataset", "specified_database", "specified_schema", "identified_table", "identified_column");

CREATE TABLE adf_data_mapping(
   source_dataset VARCHAR(255) NOT NULL,
   source_database VARCHAR(255) NOT NULL,
   source_schema VARCHAR(255) NOT NULL,
   source_table VARCHAR(255) NOT NULL,
   sink_dataset VARCHAR(255) NOT NULL,
   sink_database VARCHAR(255) NOT NULL,
   sink_schema VARCHAR(255) NOT NULL,
   sink_table VARCHAR(255) NOT NULL
);
ALTER TABLE
   adf_data_mapping ADD CONSTRAINT adf_data_mapping_pk
   PRIMARY KEY ("source_dataset", "source_database", "source_schema", "source_table");

CREATE TABLE adf_type_mapping(
   dataset VARCHAR(255) NOT NULL,
   dataset_type VARCHAR(255) NOT NULL,
   adf_type VARCHAR(255) NOT NULL
);
ALTER TABLE
   adf_type_mapping ADD CONSTRAINT adf_type_mapping_pk
   PRIMARY KEY ("dataset", "dataset_type");
INSERT INTO adf_type_mapping(dataset, dataset_type, adf_type)
   VALUES
   ('SNOWFLAKE', 'ARRAY', 'string'),
   ('SNOWFLAKE', 'BINARY', 'binary'),
   ('SNOWFLAKE', 'BOOLEAN','boolean'),
   ('SNOWFLAKE', 'DATE', 'date'),
   ('SNOWFLAKE', 'FLOAT', 'float'),
   ('SNOWFLAKE', 'GEOGRAPHY', 'string'),
   ('SNOWFLAKE', 'GEOMETRY', 'string'),
   ('SNOWFLAKE', 'NUMBER', 'float'),
   ('SNOWFLAKE', 'OBJECT', 'string'),
   ('SNOWFLAKE', 'TEXT', 'string'),
   ('SNOWFLAKE', 'TIME', 'string'),
   ('SNOWFLAKE', 'TIMESTAMP_LTZ', 'timestamp'),
   ('SNOWFLAKE', 'TIMESTAMP_NTZ', 'timestamp'),
   ('SNOWFLAKE', 'TIMESTAMP_TZ', 'timestamp'),
   ('SNOWFLAKE', 'VARIANT', 'string'),
   ('DATABRICKS', 'BOOLEAN', 'boolean'),
   ('DATABRICKS', 'INT', 'integer'),
   ('DATABRICKS', 'DOUBLE', 'double'),
   ('DATABRICKS', 'STRUCT', 'string'),
   ('DATABRICKS', 'LONG', 'long'),
   ('DATABRICKS', 'BINARY', 'binary'),
   ('DATABRICKS', 'TIMESTAMP', 'timestamp'),
   ('DATABRICKS', 'INTERVAL', 'string'),
   ('DATABRICKS', 'DECIMAL', 'integer'),
   ('DATABRICKS', 'ARRAY', 'string'),
   ('DATABRICKS', 'SHORT', 'integer'),
   ('DATABRICKS', 'DATE', 'date'),
   ('DATABRICKS', 'MAP', 'string'),
   ('DATABRICKS', 'FLOAT', 'float'),
   ('DATABRICKS', 'STRING', 'string')
;
-- source: V2024.04.18.0__add_adls_to_adls_support
CREATE PROCEDURE get_columns_from_adls_file_structure_sp
	@adf_file_structure NVARCHAR(MAX),
	@database NVARCHAR(MAX),
	@schema NVARCHAR(MAX),
	@table NVARCHAR(MAX),
	@column_delimiter NVARCHAR(1),
	@row_delimiter NVARCHAR(4),
	@quote_character NVARCHAR(1),
	@escape_character NVARCHAR(2),
	@first_row_as_header BIT,
	@null_value NVARCHAR(MAX)
AS
BEGIN
	IF @adf_file_structure IS NOT NULL AND LEN(@adf_file_structure) > 0
		-- Check if the input adf_file_structure is not NULL or empty
		BEGIN
			MERGE discovered_ruleset AS rs
			USING (
				SELECT 'ADLS' AS dataset,
					@database AS specified_database,
					@schema AS specified_schema,
					@table AS identified_table,
					structure.identified_column,
					structure.identified_column_type,
					-1 AS identified_column_max_length,
					with_idx.[key] AS ordinal_position,
					0 AS row_count,
					JSON_OBJECT(
						'metadata_version': 1,
						'column_delimiter': @column_delimiter,
						'row_delimiter': @row_delimiter,
						'quote_character': @quote_character,
						'escape_character': @escape_character,
						'first_row_as_header': @first_row_as_header,
						'null_value': @null_value,
						'persist_file_names': 'true'
					) AS metadata
				FROM
					OPENJSON(@adf_file_structure) with_idx
					CROSS APPLY OPENJSON(with_idx.[value], '$')
				WITH
					(
						[identified_column] VARCHAR(255) '$.name',
						[identified_column_type] VARCHAR(255) '$.type'
					)
				structure
			) AS adls_schema
			ON
			(
				rs.dataset = adls_schema.dataset
				AND rs.specified_database = adls_schema.specified_database
				AND rs.specified_schema = adls_schema.specified_schema
				AND rs.identified_table = adls_schema.identified_table
				AND rs.identified_column = adls_schema.identified_column
			)
			WHEN MATCHED THEN
				UPDATE
					SET 
						rs.identified_column_type = adls_schema.identified_column_type,
						rs.row_count = adls_schema.row_count,
						rs.metadata = adls_schema.metadata
			WHEN NOT MATCHED THEN 
				INSERT (
					dataset,
					specified_database,
					specified_schema,
					identified_table,
					identified_column,
					identified_column_type,
					identified_column_max_length,
					ordinal_position,
					row_count,
					metadata
				)
				VALUES (
					adls_schema.dataset,
					adls_schema.specified_database,
					adls_schema.specified_schema,
					adls_schema.identified_table,
					adls_schema.identified_column,
					adls_schema.identified_column_type,
					adls_schema.identified_column_max_length,
					adls_schema.ordinal_position,
					adls_schema.row_count,
					adls_schema.metadata
				);
		END
	ELSE
		-- Handle NULL or empty adf_file_structure input
		BEGIN
			PRINT 'adf_file_structure is NULL or empty';
		END
END;
INSERT INTO adf_type_mapping(dataset, dataset_type, adf_type)
   VALUES
   ('ADLS', 'String', 'string');
-- source: V2024.05.02.0__update_adls_to_adls_support
ALTER PROCEDURE get_columns_from_adls_file_structure_sp
	@adf_file_structure NVARCHAR(MAX),
	@database NVARCHAR(MAX),
	@schema NVARCHAR(MAX),
	@table NVARCHAR(MAX),
	@column_delimiter NVARCHAR(1),
	@quote_character NVARCHAR(1),
	@escape_character NVARCHAR(2),
	@null_value NVARCHAR(MAX)
AS
BEGIN
	IF @adf_file_structure IS NOT NULL AND LEN(@adf_file_structure) > 0
		-- Check if the input adf_file_structure is not NULL or empty
		BEGIN
			MERGE discovered_ruleset AS rs
			USING (
				SELECT 'ADLS' AS dataset,
					@database AS specified_database,
					@schema AS specified_schema,
					@table AS identified_table,
					structure.identified_column,
					structure.identified_column_type,
					-1 AS identified_column_max_length,
					with_idx.[key] AS ordinal_position,
					-1 AS row_count,
					JSON_OBJECT(
						'metadata_version': 2,
						'column_delimiter': @column_delimiter,
						'quote_character': @quote_character,
						'escape_character': @escape_character,
						'null_value': @null_value
					) AS metadata
				FROM
					OPENJSON(@adf_file_structure) with_idx
					CROSS APPLY OPENJSON(with_idx.[value], '$')
				WITH
					(
						[identified_column] VARCHAR(255) '$.name',
						[identified_column_type] VARCHAR(255) '$.type'
					)
				structure
			) AS adls_schema
			ON
			(
				rs.dataset = adls_schema.dataset
				AND rs.specified_database = adls_schema.specified_database
				AND rs.specified_schema = adls_schema.specified_schema
				AND rs.identified_table = adls_schema.identified_table
				AND rs.identified_column = adls_schema.identified_column
			)
			WHEN MATCHED THEN
				UPDATE
					SET
						rs.identified_column_type = adls_schema.identified_column_type,
						rs.row_count = adls_schema.row_count,
						rs.metadata = adls_schema.metadata
			WHEN NOT MATCHED THEN
				INSERT (
					dataset,
					specified_database,
					specified_schema,
					identified_table,
					identified_column,
					identified_column_type,
					identified_column_max_length,
					ordinal_position,
					row_count,
					metadata
				)
				VALUES (
					adls_schema.dataset,
					adls_schema.specified_database,
					adls_schema.specified_schema,
					adls_schema.identified_table,
					adls_schema.identified_column,
					adls_schema.identified_column_type,
					adls_schema.identified_column_max_length,
					adls_schema.ordinal_position,
					adls_schema.row_count,
					adls_schema.metadata
				);
		END
	ELSE
		-- Handle NULL or empty adf_file_structure input
		BEGIN
			PRINT 'adf_file_structure is NULL or empty';
		END
END;

--source: V2024.06.04.0__add_logging_and_reset_flags

ALTER TABLE discovered_ruleset add
   is_profiled char(1), 
   last_update_pipeline_id varchar(100);

ALTER TABLE adf_data_mapping add
   is_masked char(1), 
   last_update_pipeline_id varchar(100);

-- ADF/Synapse Execution Log

CREATE TABLE adf_execution_log (
pipeline_name VARCHAR(100), 
pipeline_run_id VARCHAR(100) NOT NULL, 
activity_run_id VARCHAR(100) NOT NULL, 
pipeline_status VARCHAR(20), 
error_message VARCHAR(MAX), 
input_parameters VARCHAR(MAX), 
execution_start_time DATETIME, 
execution_end_time DATETIME, 
src_dataset VARCHAR(255),
src_file_format VARCHAR(255), 
src_db_name VARCHAR(100), 
src_table_name VARCHAR(100), 
src_schema_name VARCHAR(100), 
sink_dataset VARCHAR(255), 
sink_file_format VARCHAR(255), 
sink_db_name VARCHAR(100), 
sink_table_name VARCHAR(100), 
sink_schema_name VARCHAR(100), 
last_inserted DATETIME DEFAULT getdate(), 
CONSTRAINT adf_execution_log_pk PRIMARY KEY (pipeline_run_id, activity_run_id));

-- procedure to capture logs

create or alter procedure capture_adf_execution_sp
(
@pipeline_name varchar(100),
@pipeline_run_id varchar(100),
@activity_run_id varchar(100),
@pipeline_status varchar(20),
@error_message varchar(max),
@input_parameters varchar(max),
@execution_start_time datetime,
@execution_end_time datetime,
@src_dataset varchar(255),
@src_file_format varchar(255),
@src_db_name varchar(100),
@src_table_name varchar(100),
@src_schema_name varchar(100),
@sink_dataset varchar(255),
@sink_file_format varchar(255),
@sink_db_name varchar(100),
@sink_table_name varchar(100),
@sink_schema_name varchar(100)
)
as
begin
insert into adf_execution_log (pipeline_name, pipeline_run_id, activity_run_id, pipeline_status, error_message, input_parameters, src_dataset, 
src_file_format, src_db_name, src_table_name, src_schema_name, sink_dataset, sink_file_format, sink_db_name, sink_table_name, sink_schema_name, execution_start_time, execution_end_time)
values
(@pipeline_name, @pipeline_run_id, @activity_run_id, @pipeline_status, @error_message, @input_parameters, @src_dataset, @src_file_format, @src_db_name,
@src_table_name, @src_schema_name, @sink_dataset, @sink_file_format, @sink_db_name, @sink_table_name, @sink_schema_name, @execution_start_time, @execution_end_time)

---------------------------------------------------------------------------
------------------------------------------- For Masking Pipelines
---------------------------------------------------------------------------

if @pipeline_name like 'dcsazure_%_mask_pl%'

-- for ADLS Parquet

if @src_dataset = 'ADLS' and @src_file_format = 'PARQUET' and @sink_dataset = 'ADLS' and @sink_file_format = 'PARQUET' and @pipeline_status = 'Succeeded'
   update adls_adf_data_mapping set is_masked = 'Y', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_folder = @src_table_name and source_path = @src_schema_name and source_container = @src_db_name and source_fileformat = @src_file_format
   and sink_dataset = @sink_dataset and  sink_folder = @sink_table_name and sink_path = @sink_schema_name and sink_container = @sink_db_name and sink_fileformat = @sink_file_format;

else if @src_dataset = 'ADLS' and @src_file_format = 'PARQUET' and @sink_dataset = 'ADLS' and @sink_file_format = 'PARQUET' and @pipeline_status = 'Failed'
   update adls_adf_data_mapping set is_masked = 'N', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_folder = @src_table_name and source_path = @src_schema_name and source_container = @src_db_name and source_fileformat = @src_file_format
   and sink_dataset = @sink_dataset and  sink_folder = @sink_table_name and sink_path = @sink_schema_name and sink_container = @sink_db_name and sink_fileformat = @sink_file_format;

-- for ADLS Delimited

if @src_dataset = 'ADLS' and @src_file_format = 'DELIMITED' and @sink_dataset = 'ADLS' and @sink_file_format = 'DELIMITED' and @pipeline_status = 'Succeeded'
   update adf_data_mapping set is_masked = 'Y', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

else if @src_dataset = 'ADLS' and @src_file_format = 'DELIMITED' and @sink_dataset = 'ADLS' and @sink_file_format = 'DELIMITED' and @pipeline_status = 'Failed'
   update adf_data_mapping set is_masked = 'N', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

-- for Snowflake

if @src_dataset = 'Snowflake' and @sink_dataset = 'Snowflake' and @pipeline_status = 'Succeeded'
   update adf_data_mapping set is_masked = 'Y', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

else if @src_dataset = 'Snowflake' and @sink_dataset = 'Snowflake' and @pipeline_status = 'Failed'
   update adf_data_mapping set is_masked = 'N', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

-- for SqlServer to ADLS

if @src_dataset = 'SqlServer' and @sink_dataset = 'ADLS' and @pipeline_status = 'Succeeded'
   update adf_data_mapping set is_masked = 'Y', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

else if @src_dataset = 'SqlServer' and @sink_dataset = 'ADLS' and @pipeline_status = 'Failed'
   update adf_data_mapping set is_masked = 'N', last_update_pipeline_id = @pipeline_run_id
   where source_dataset = @src_dataset and  source_table = @src_table_name and source_schema = @src_schema_name and source_database = @src_db_name
   and sink_dataset = @sink_dataset and  sink_table = @sink_table_name and sink_schema = @sink_schema_name and sink_database = @sink_db_name;

---------------------------------------------------------------------------
------------------------------------------- For Profiling Pipelines
---------------------------------------------------------------------------

else if @pipeline_name like 'dcsazure_%_prof_pl%'

if @src_dataset = 'ADLS' and @src_file_format = 'PARQUET' and @pipeline_status = 'Succeeded'
   update adls_discovered_ruleset set is_profiled = 'Y', last_update_pipeline_id = @pipeline_run_id
   where dataset = @src_dataset and  identified_folder = @src_table_name and specified_path = @src_schema_name and specified_container = @src_db_name and file_format = @src_file_format;

else if @src_dataset = 'ADLS' and @src_file_format = 'PARQUET' and @pipeline_status = 'Failed'
   update adls_discovered_ruleset set is_profiled = 'N', last_update_pipeline_id = @pipeline_run_id
   where dataset = @src_dataset and  identified_folder = @src_table_name and specified_path = @src_schema_name and specified_container = @src_db_name and file_format = @src_file_format;

-- for ADLS Delimited

if @src_dataset = 'ADLS' and @src_file_format = 'DELIMITED' and @pipeline_status = 'Succeeded'
   update discovered_ruleset set is_profiled = 'Y', last_update_pipeline_id = @pipeline_run_id
   where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

else if @src_dataset = 'ADLS' and @src_file_format = 'DELIMITED' and @sink_dataset = 'ADLS' and @sink_file_format = 'DELIMITED' and @pipeline_status = 'Failed'
   update discovered_ruleset set is_profiled = 'N', last_update_pipeline_id = @pipeline_run_id
where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

-- for Snowflake

if @src_dataset = 'Snowflake' and @src_file_format = 'N/A' and @pipeline_status = 'Succeeded'
   update discovered_ruleset set is_profiled = 'Y', last_update_pipeline_id = @pipeline_run_id
   where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

else if @src_dataset = 'Snowflake' and @src_file_format = 'N/A'  and @pipeline_status = 'Failed'
   update discovered_ruleset set is_profiled = 'N', last_update_pipeline_id = @pipeline_run_id
where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

-- for Snowflake

if @src_dataset = 'SqlServer' and @src_file_format = 'N/A' and @pipeline_status = 'Succeeded'
   update discovered_ruleset set is_profiled = 'Y', last_update_pipeline_id = @pipeline_run_id
   where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

else if @src_dataset = 'SqlServer' and @src_file_format = 'N/A'  and @pipeline_status = 'Failed'
   update discovered_ruleset set is_profiled = 'N', last_update_pipeline_id = @pipeline_run_id
where dataset = @src_dataset and  identified_table = @src_table_name and specified_schema = @src_schema_name and specified_database = @src_db_name;

end;
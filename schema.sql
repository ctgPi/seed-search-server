CREATE TABLE host (
    host_id SERIAL NOT NULL,
    host_name TEXT NOT NULL,
    host_secret_sha384 BYTEA NOT NULL,
    PRIMARY KEY (host_id),
    UNIQUE (host_name),
    UNIQUE (host_secret_sha384),
    CHECK (BIT_LENGTH(host_secret_sha384) = 384)
);

CREATE TABLE version (
    version_id SERIAL NOT NULL,
    version_name TEXT NOT NULL,
    PRIMARY KEY (version_id),
    UNIQUE (version_name)
);

CREATE TYPE task_state AS ENUM ('open', 'assigned', 'closed');

CREATE TABLE task (
    task_id SERIAL NOT NULL,
    version_id INT NOT NULL,
    task_chunk INT NOT NULL,
    task_state task_state NOT NULL,

    host_id INT,
    task_token_sha384 BYTEA,
    task_deadline TIMESTAMP,
    task_result_sha384 BYTEA,

    PRIMARY KEY (task_id),
    FOREIGN KEY (version_id) REFERENCES version,
    FOREIGN KEY (host_id) REFERENCES host,
    UNIQUE (task_token_sha384),
    UNIQUE (task_result_sha384),

    CHECK (0 <= task_chunk AND task_chunk < 65536),
    CHECK (task_token_sha384 IS NULL OR BIT_LENGTH(task_token_sha384) = 384),
    CHECK (task_result_sha384 IS NULL OR BIT_LENGTH(task_result_sha384) = 384),

    CHECK (task_state != 'open' OR host_id IS NULL),
    CHECK (task_state != 'open' OR task_token_sha384 IS NULL),
    CHECK (task_state != 'open' OR task_deadline IS NULL),
    CHECK (task_state != 'open' OR task_result_sha384 IS NULL),

    CHECK (task_state != 'assigned' OR host_id IS NOT NULL),
    CHECK (task_state != 'assigned' OR task_token_sha384 IS NOT NULL),
    CHECK (task_state != 'assigned' OR task_deadline IS NOT NULL),
    CHECK (task_state != 'assigned' OR task_result_sha384 IS NULL),

    CHECK (task_state != 'closed' OR host_id IS NOT NULL),
    CHECK (task_state != 'closed' OR task_token_sha384 IS NOT NULL),
    CHECK (task_state != 'closed' OR task_deadline IS NULL),
    CHECK (task_state != 'closed' OR task_result_sha384 IS NOT NULL)
);

-- close task

SELECT task_id
FROM task
WHERE task_state = 'assigned' AND
      task_token_sha384 = $1;

UPDATE task
SET task_state = 'closed',
    task_token_sha384 = NULL,
    task_deadline = NULL,
    task_result_sha384 = $2
WHERE task_id = $1;

-- reap expired assignments

UPDATE task
SET task_state = 'open',
    host_id = NULL,
    task_token_sha384 = NULL,
    task_deadline = NULL
WHERE task_state = 'assigned' AND
      task_deadline < CURRENT_TIMESTAMP;

-- assign job

SELECT task_id
FROM task
WHERE task_state = 'open' AND
      version_id = (SELECT version_id FROM version WHERE version_name = $1)
LIMIT 1
FOR UPDATE SKIP LOCKED;

UPDATE task
SET task_state = 'assigned',
    host_id = $2,
    task_token_sha384 = $3,
    task_deadline = CURRENT_TIMESTAMP + INTERVAL '24 hours'
WHERE task_id = $1
RETURN task_chunk;

-- create version

INSERT INTO version (version_name)
VALUES ('0.6.114');

-- create tasks

INSERT INTO task (version_id, task_chunk, task_state) 
SELECT (SELECT version_id FROM version WHERE version_name = $1) AS version_id, task_chunk, 'open' AS task_state
FROM GENERATE_SERIES(0, 65535) AS task_chunk(task_chunk)
ORDER BY RANDOM();

-- create host

INSERT INTO host (host_name, host_secret_sha384)
VALUES ($1, SHA384($2))

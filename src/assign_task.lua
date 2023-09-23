local util = require('util')
local database = require('database')
local resty_sha384 = require('resty.sha384')
local resty_random = require('resty.random')

local function get_host_id(host_name, host_secret)
    if host_name == nil or host_secret == nil then
        return nil
    end

    if string.len(host_secret) ~= 96 or not string.match(host_secret, '^[0-9a-f]*$') then
        return nil
    end

    local host_secret_sha384
    do
        local sha384 = resty_sha384:new()
        sha384:update(util.from_hex(host_secret))
        host_secret_sha384 = sha384:final()
    end

    local result, err = database:query([[
    SELECT host_id
    FROM host
    WHERE host_name = $1 AND
          host_secret_sha384 = DECODE($2, 'hex')
    ]], host_name, util.to_hex(host_secret_sha384))

    if result == nil or #result == 0 then
        return nil
    end

    return result[1].host_id
end

local function get_version_id(version_name)
    if version_name == nil then
        return nil
    end

    local result, err = database:query([[
    SELECT version_id
    FROM version
    WHERE version_name = $1
    ]], version_name)

    if result == nil or #result == 0 then
        return nil
    end

    return result[1].version_id
end

local function get_open_task_id(version_id)
    local result, err = database:query([[
    SELECT task_id
    FROM task
    WHERE task_state = 'open' AND
          version_id = $1
    LIMIT 1
    FOR UPDATE SKIP LOCKED
    ]], version_id)

    if result == nil or #result == 0 then
        return nil
    end

    return result[1].task_id
end

local function assign_task(task_id, host_id)
    local task_token
    while task_token == nil do
        task_token = resty_random.bytes(48, true)
    end

    local task_token_sha384
    do
        local sha384 = resty_sha384:new()
        sha384:update(task_token)
        task_token_sha384 = sha384:final()
    end

    local result, err = database:query([[
    UPDATE task
    SET task_state = 'assigned',
        host_id = $2,
        task_token_sha384 = DECODE($3, 'hex'),
        task_deadline = CURRENT_TIMESTAMP + INTERVAL '24 hours'
    WHERE task_id = $1
    RETURNING task_chunk;
    ]], task_id, host_id, util.to_hex(task_token_sha384))

    if result == nil or #result == 0 then
        return nil
    end

    return result[1].task_chunk, task_token
end

ngx.req.read_body()
local post_args = ngx.req.get_post_args()

database:connect()
database:query('BEGIN')

local host_id = get_host_id(post_args.host_name, post_args.host_secret)
if host_id == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local version_id = get_version_id(post_args.version_name)
if version_id == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local task_id = get_open_task_id(version_id)
if task_id == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_NOT_FOUND)
end

local task_chunk, task_token = assign_task(task_id, host_id)
if task_chunk == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

database:query('COMMIT')

ngx.print('{"task_chunk": ' .. tostring(task_chunk) .. ', "task_token": "' .. util.to_hex(task_token) .. '"}\n')

database:keepalive()

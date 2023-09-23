local util = require('util')
local database = require('database')
local resty_sha384 = require('resty.sha384')

local function get_task_id(task_token)
    if string.len(task_token) ~= 96 or not string.match(task_token, '^[0-9a-f]*$') then
        return nil
    end

    local task_token_sha384
    do
        local sha384 = resty_sha384:new()
        sha384:update(util.from_hex(task_token))
        task_token_sha384 = sha384:final()
    end

    local result, err = database:query([[
    SELECT task_id
    FROM task
    WHERE task_token_sha384 = DECODE($1, 'hex')
    ]], util.to_hex(task_token_sha384))

    if result == nil or #result == 0 then
        return nil
    end

    return result[1].task_id
end

local function return_task(task_id, task_result)
    if task_result == nil then
        return nil
    end

    local task_result_sha384
    do
        local sha384 = resty_sha384:new()
        sha384:update(task_result)
        task_result_sha384 = sha384:final()
    end

    do
        local result_file, err = io.open('/home/factorio/www/upload/' .. util.to_hex(task_result_sha384) .. '.bin', 'wb')
        if result_file == nil then
            ngx.say(err)
            return nil
        end
        if result_file:write(task_result) == nil then
            result_file:close()
            return nil
        end
        result_file:close()
    end

    local result, err = database:query([[
    UPDATE task
    SET task_state = 'closed',
        task_deadline = NULL,
        task_result_sha384 = DECODE($2, 'hex')
    WHERE task_id = $1
    RETURNING task_id
    ]], task_id, util.to_hex(task_result_sha384))

    if result == nil or #result == 0 then
        ngx.say(err)
        return nil
    end

    return true
end

database:connect()
database:query('BEGIN')

local task_token = ngx.var.task_token
local task_token = string.sub(ngx.var.uri, 7, 102)
local task_id = get_task_id(task_token)
if task_id == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_NOT_FOUND)
end

ngx.req.read_body()
local task_result = ngx.req.get_body_data()

local success = return_task(task_id, task_result)
if success == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

database:query('COMMIT')
database:keepalive()

ngx.print('{"task_state": "closed"}')

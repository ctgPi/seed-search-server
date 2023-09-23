local util = require('util')
local database = require('database')
local resty_sha384 = require('resty.sha384')

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

local function get_task_state(version_id)
    local result, err = database:query([[
    SELECT task_chunk,
           CASE WHEN task_deadline < CURRENT_TIMESTAMP THEN 'overdue' ELSE task_state::TEXT END,
           task_result_sha384
    FROM task
    WHERE version_id = $1
    ]], version_id)

    if result == nil then
        return nil
    end

    return result
end

ngx.req.read_body()
local post_args = ngx.req.get_post_args()

database:connect()
database:query('BEGIN')

local version_name = ngx.var.version_name
local version_id = get_version_id(version_name)
if version_id == nil then
    database:query('ROLLBACK')
    database:keepalive()
    ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local task_state = {}
local task_result_sha384 = {}
for _, task in pairs(get_task_state(version_id)) do
    task_state[task.task_chunk] = task.task_state
    task_result_sha384[task.task_chunk] = task.task_result_sha384
end

database:query('ROLLBACK')
database:keepalive()

ngx.print("<!DOCTYPE html>\n")
ngx.print("<title>Space Exploration " .. version_name .. "</title>\n")
ngx.print([[<style>
ul {
    display: flex;
    flex-wrap: wrap;
    list-style: none;
    margin: 0 auto;
    padding: 0;
    width: 1024px;
}

li {
    margin: 0;
    padding: 0;
    display: block;
    width: 4px;
    height: 4px;
    background-color: #000;
}

li.closed { background-color: #0BB; }
li.assigned { background-color: #999; }
li.overdue { background-color: #F90; }
li.open { background-color: #000; }

p {
    font-family: monospace;
    text-align: center;
    margin: 1ch;
    padding: 0.5ch;
    background-color: #FF9;
}

a {
    display: block;
    width: 4px;
    height: 4px;
}
</style>
]])

ngx.print('<p>last update: <span id="last-update">' .. os.date('!%Y-%m-%dT%H:%M:%S%z') .. '</span></p>\n')
ngx.print([[<script>
function toIsoString(date) {
  var tzo = -date.getTimezoneOffset(),
      dif = tzo >= 0 ? '+' : '-',
      pad = function(num) {
          return (num < 10 ? '0' : '') + num;
      };

  return date.getFullYear() +
      '-' + pad(date.getMonth() + 1) +
      '-' + pad(date.getDate()) +
      'T' + pad(date.getHours()) +
      ':' + pad(date.getMinutes()) +
      ':' + pad(date.getSeconds()) +
      dif + pad(Math.floor(Math.abs(tzo) / 60)) +
      ':' + pad(Math.abs(tzo) % 60);
}

const lastUpdate = document.getElementById('last-update');
lastUpdate.textContent = toIsoString(new Date(lastUpdate.textContent));
</script>]])

ngx.print('<ul>')
for i = 0, 255 do
    for j = 0, 255 do
        local task_chunk = 256 * i + j

        if task_state[task_chunk] == 'closed' then
            ngx.print('<li class="closed"><a href="/upload/' .. util.to_hex(task_result_sha384[task_chunk]).. '.bin"></a></li>\n')
        elseif task_state[task_chunk] == 'assigned' then
            ngx.print('<li class="assigned"></li>\n')
        elseif task_state[task_chunk] == 'overdue' then
            ngx.print('<li class="overdue"></li>\n')
        else
            ngx.print('<li class="open"></li>\n')
        end
    end
end
ngx.print('</ul>')

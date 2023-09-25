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
           CASE WHEN task_deadline < CURRENT_TIMESTAMP THEN 'overdue' ELSE task_state::TEXT END AS task_state,
           task_result_sha384
    FROM task
    WHERE version_id = $1
    ]], version_id)

    if result == nil then
        return nil
    end

    return result
end

local function get_task_overview(version_id)
    local result, err = database:query([[
    SELECT task_state,
           COUNT(task_chunk) AS task_count
    FROM (SELECT task_chunk,
                 CASE WHEN task_deadline < CURRENT_TIMESTAMP THEN 'overdue' ELSE task_state::TEXT END AS task_state
          FROM task
          WHERE version_id = $1)
    GROUP BY task_state;
    ]], version_id)

    if result == nil then
        return nil
    end

    return result
end

local function get_host_leaderboard(version_id)
    local result, err = database:query([[
    SELECT host_name,
           COALESCE(task_count, 0) AS task_count
    FROM host NATURAL LEFT JOIN (
         SELECT host_name,
                COUNT(*) as task_count
         FROM task NATURAL INNER JOIN
              host
         WHERE task_state = 'closed' AND
               version_id = $1
         GROUP BY host_name)
    ORDER BY task_count DESC
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

local task_overview = get_task_overview(version_id)
local host_leaderboard = get_host_leaderboard(version_id)

database:query('ROLLBACK')
database:keepalive()

ngx.print("<!DOCTYPE html>\n")
ngx.print("<title>Space Exploration " .. version_name .. "</title>\n")
ngx.print([[<style>
body {
    font-family: monospace;
}

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
li.overdue { background-color: #F90; }
li.assigned { background-color: #999; }
li.open { background-color: #000; }

p {
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

table {
    border-spacing: 3ch 0.5ch;
}

div.task_summary {
    width: 1024px;
    height: 32px;
    display: flex;
    margin: 0 auto;
}

div.task_summary div {
    height: 32px;
}

div.task_summary div.closed { background-color: #0BB; }
div.task_summary div.overdue { background-color: #F90; }
div.task_summary div.assigned { background-color: #999; }
div.task_summary div.open { background-color: #000; }
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

ngx.print('<h2>Task Summary</h2>')

local task_fraction = { closed = '0.00%', overdue = '0.00%', assigned = '0.00%', open = '0.00%' }
for _, row in pairs(task_overview) do
    local task_state = row.task_state
    local task_count = row.task_count
    task_fraction[task_state] = string.format('%.2f%%', 100 * task_count / 65536)
end

ngx.print('<div class="task_summary">')
for _, task_state in ipairs({ 'closed', 'overdue', 'assigned', 'open' }) do
    ngx.print('<div class="' .. task_state .. '" style="width: ' .. task_fraction[task_state] .. '" title="' .. task_fraction[task_state] .. '"></div>')
end
ngx.print('</div>')

ngx.print('<h2>Host Leaderboard</h2>')

ngx.print('<table>')
for _, host in pairs(host_leaderboard) do
    ngx.print('<tr>')
    ngx.print('<td>')
    ngx.print(host.host_name)
    ngx.print('</td>')
    ngx.print('<td>')
    ngx.print(tostring(host.task_count))
    ngx.print('</td>')
    ngx.print('</tr>')
end
ngx.print('</table>')

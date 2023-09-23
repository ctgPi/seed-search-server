local pgmoon = require('pgmoon')
local config = require('_config')
local database = pgmoon.new({
    host = config.database_host,
    port = config.database_port,
    database = config.database_name,
    user = config.database_user,
    password = config.database_password,
})

return database

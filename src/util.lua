local util = {}

local hex_to_char = {}
for i = 0, 255 do
    hex_to_char[string.format('%02x', i)] = string.char(i)
end

function util.from_hex(s)
    assert(string.len(s) % 2 == 0)
    return string.gsub(s, '(..)', hex_to_char)
end

function util.to_hex(s)
    local r = {}
    for i = 1, string.len(s) do
        table.insert(r, string.format('%02x', string.byte(s, i)))
    end
    return table.concat(r)
end

return util

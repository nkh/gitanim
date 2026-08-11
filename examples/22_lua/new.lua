local M = {}

local default_greeting = "Hello"

function M.greet(name, greeting)
    greeting = greeting or default_greeting
    print(greeting .. ", " .. name .. "!")
end

function M.greet_table(names)
    for _, name in ipairs(names) do
        M.greet(name)
    end
end

return M

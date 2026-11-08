local Messages = {}

local current_message = ""
local message_timer = 0

function Messages.show(text, duration)
    current_message = text
    message_timer = duration or 2.5
end

function Messages.update(dt)
    if message_timer > 0 then
        message_timer = message_timer - dt

        if message_timer <= 0 then
            current_message = ""
        end
    end
end

function Messages.draw(pass, x, y, z, yaw, pitch)
    if current_message == "" then return end

    pass:push("transform")
    pass:translate(x, y, z)
    pass:rotate(yaw, 0, 1, 0)
    pass:rotate(pitch, 1, 0, 0)

    pass:setDepthTest("none")

    pass:setColor(1, 1, 1, 1)
    pass:text(current_message, 0, 0, -2, 0.08)

    pass:setDepthTest("less")

    pass:pop()
    pass:setColor(1, 1, 1, 1)
end

return Messages
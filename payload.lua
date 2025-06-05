-- First we wrap the monitor peripheral
local monitor = peripheral.find("monitor")

-- Let's clear the monitor
monitor.clear()

-- And reset the cursor position
monitor.setCursorPos(1,1)

-- Then we can write whatever we want
monitor.write("Hello, World")

monitor.setCursorPos(1,2)

monitor.write("Second Line")

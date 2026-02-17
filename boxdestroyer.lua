--[[
Copyright (c) 2014, Seth VanHeulen
All rights reserved.

boxdestroyer:
- Ashita v3 addon originally by Seth VanHeulen (Acacia@Odin)
- Maintained/ported for Ashita v3 by Zechs6437 (Maarek@Fenrir)
- Changed some behaviour & updated for Ashita v4 (beta final) by Scarface
--]]

addon = {
    name    = 'boxdestroyer',
    version = '2.0.0',
    author  = 'Seth VanHeulen (Acacia@Odin); Zechs6437 (Maarek@Fenrir); Scarface for this Ashita v4 port'
}

require('common')
require('messages')

local ffi  = require('ffi')
local core = AshitaCore
local mm   = core:GetMemoryManager()

math.randomseed(os.time())

local function send_system_message(msg)
    core:GetChatManager():AddChatMessage(207, false, msg)
end

local function packet_to_string(e)
    if type(e.data_raw) == 'string' then
        return e.data_raw
    end
    return ffi.string(e.data_raw, e.size)
end

default = {
    10,11,12,13,14,15,16,17,18,19,
    20,21,22,23,24,25,26,27,28,29,
    30,31,32,33,34,35,36,37,38,39,
    40,41,42,43,44,45,46,47,48,49,
    50,51,52,53,54,55,56,57,58,59,
    60,61,62,63,64,65,66,67,68,69,
    70,71,72,73,74,75,76,77,78,79,
    80,81,82,83,84,85,86,87,88,89,
    90,91,92,93,94,95,96,97,98,99
}

box = {}

-- Track current chest to prevent mix ups
local active_box    = nil
local unlocked       = {}
local last_hint_sig  = {}

local function initialize_box(id)
    if box[id] == nil then
        box[id] = default
    end
end

local function reset_box(id)
    box[id] = nil
    initialize_box(id)
    unlocked[id] = false
    last_hint_sig[id] = nil
end

function greater_less(id, greater, num)
    initialize_box(id)
    local new = {}
    for _, v in pairs(box[id]) do
        if (greater and v > num) or (not greater and v < num) then
            table.insert(new, v)
        end
    end
    return new
end

function even_odd(id, div, rem)
    initialize_box(id)
    local new = {}
    for _, v in pairs(box[id]) do
        if (math.floor(v / div) % 2) == rem then
            table.insert(new, v)
        end
    end
    return new
end

function equal(id, first, num)
    initialize_box(id)
    local new = {}
    for _, v in pairs(box[id]) do
        if (first and math.floor(v / 10) == num) or (not first and (v % 10) == num) then
            table.insert(new, v)
        end
    end
    return new
end

-- Find the best guess to split remaining numbers evenly
local function best_guess(cands)
    if not cands or #cands == 0 then return nil end

    local best = cands[math.ceil(#cands / 2)]
    local best_score = math.huge

    for g = 10, 99 do
        local less, greater = 0, 0
        for _, v in ipairs(cands) do
            if v < g then less = less + 1
            elseif v > g then greater = greater + 1 end
        end
        local score = (less * less + greater * greater) / #cands
        if score < best_score then
            best_score = score
            best = g
        end
    end

    return best
end

function display(id, chances)
    initialize_box(id)

    if not box[id] or #box[id] == 0 then
        send_system_message('Possible combinations: (none)')
        send_system_message('Best guess: (unknown)')
        return
    end

    if #box[id] == 90 then
        send_system_message('Possible combinations: 10~99')
    else
        send_system_message('Possible combinations: ' .. table.concat(box[id], ' '))
    end

    local count = #box[id]
    local pct = 100.0 / count

    if count == 2 or (chances == 1 and count > 1) then
        if chances == 1 then
            send_system_message(string.format(
                'Final attempt! The numbers listed above all have an equal chance of being correct (%.0f%% each). Your choice.',
                pct
            ))
        else
            send_system_message(string.format(
                'The numbers listed above all have an equal chance of being correct (%.0f%% each). Your choice.',
                pct
            ))
        end
        return
    end

    local guess = best_guess(box[id])
    send_system_message(string.format('Best guess: %s (%.0f%%)', tostring(guess), pct))
end

function get_id(zone_id, str)
    return messages[zone_id] + offsets[str]
end

local function get_remaining_attempts(data)
    for _, o in ipairs({9,10,11,12,13}) do
        local v = data:byte(o)
        if v and v >= 1 and v <= 6 then return v end
    end
    return 0
end

ashita.events.register('packet_in', 'boxdestroyer_packet_in', function(e)
    local data = packet_to_string(e)
    local zone_id = mm:GetParty():GetMemberZone(0)
    if not messages[zone_id] then return false end

    if e.id == 0x0B then
        box = {}
        active_box = nil
        unlocked = {}
        last_hint_sig = {}
        return false
    end

    if e.id == 0x5B then
        local despawn_id = struct.unpack('I', data, 17)
        box[despawn_id] = nil
        unlocked[despawn_id] = nil
        last_hint_sig[despawn_id] = nil
        if active_box == despawn_id then active_box = nil end
        return false
    end

    if e.id == 0x34 then
        local box_id = struct.unpack('H', data, 41)

        if active_box ~= box_id then
            active_box = box_id
            reset_box(box_id)
        else
            active_box = box_id
            initialize_box(box_id)
        end

        local chances = get_remaining_attempts(data)
        if chances > 0 and chances < 7 then
            display(box_id, chances)
        end
        return false
    end

    if e.id == 0x2A then
        local box_id = struct.unpack('H', data, 25)
        if active_box == nil or box_id ~= active_box then return false end

        local p0 = struct.unpack('I', data, 9)
        local p1 = struct.unpack('I', data, 13)
        local p2 = struct.unpack('I', data, 17)
        local msg = bit.band(struct.unpack('H', data, 27), 0x7FFF)
        local sig = msg .. ':' .. p0 .. ':' .. p1 .. ':' .. p2
		
        if last_hint_sig[box_id] == sig then return false end
        last_hint_sig[box_id] = sig

        if get_id(zone_id,'greater_less') == msg then
            box[box_id] = greater_less(box_id, p1 == 0, p0)
            send_system_message(string.format('Hint applied: %s than %d', (p1 == 0) and 'greater' or 'less', p0))

        elseif get_id(zone_id,'second_even_odd') == msg then
            box[box_id] = even_odd(box_id, 1, p0)
            send_system_message(string.format('Hint applied: second digit is %s', (p0 == 0) and 'even' or 'odd'))

        elseif get_id(zone_id,'first_even_odd') == msg then
            box[box_id] = even_odd(box_id, 10, p0)
            send_system_message(string.format('Hint applied: first digit is %s', (p0 == 0) and 'even' or 'odd'))

        elseif get_id(zone_id,'range') == msg then
            box[box_id] = greater_less(box_id, true, p0)
            box[box_id] = greater_less(box_id, false, p1)
            send_system_message(string.format('Hint applied: range %d-%d', p0 + 1, p1 - 1))

        elseif get_id(zone_id,'less') == msg then
            box[box_id] = greater_less(box_id, false, p0)
            send_system_message(string.format('Hint applied: less than %d', p0))

        elseif get_id(zone_id,'greater') == msg then
            box[box_id] = greater_less(box_id, true, p0)
            send_system_message(string.format('Hint applied: greater than %d', p0))

        elseif get_id(zone_id,'equal') == msg then
            local new = equal(box_id, true, p0)
            local duplicate = p0 * 10 + p0
            for k, v in pairs(new) do
                if v == duplicate then
                    table.remove(new, k)
                end
            end
            for _, v in pairs(equal(box_id, false, p0)) do table.insert(new, v) end
            table.sort(new)
            box[box_id] = new
            send_system_message(string.format('Hint applied: one digit is %d', p0))

        elseif get_id(zone_id,'second_multiple') == msg then
            local new = {}
            for _, v in pairs(box[box_id] or default) do
                local d = v % 10
                if d == p0 or d == p1 or d == p2 then table.insert(new, v) end
            end
            table.sort(new)
            box[box_id] = new
            send_system_message(string.format('Hint applied: second digit is %d, %d, or %d', p0, p1, p2))

        elseif get_id(zone_id,'first_multiple') == msg then
            local new = {}
            for _, v in pairs(box[box_id] or default) do
                local d = math.floor(v / 10)
                if d == p0 or d == p1 or d == p2 then table.insert(new, v) end
            end
            table.sort(new)
            box[box_id] = new
            send_system_message(string.format('Hint applied: first digit is %d, %d, or %d', p0, p1, p2))

        elseif get_id(zone_id,'success') == msg or get_id(zone_id,'failure') == msg then
            unlocked[box_id] = true
            box[box_id] = nil
            send_system_message((get_id(zone_id,'success') == msg) and 'Lock opened!' or 'Unlock failed.')
        end

        return false
    end

    return false
end)

ashita.events.register('packet_out', 'boxdestroyer_packet_out', function(e)
    if e.id ~= 0x5B then return false end
    if not active_box or unlocked[active_box] then return false end

    local guess = struct.unpack('H', packet_to_string(e), 11)
    if guess >= 10 and guess <= 99 then
        send_system_message('You guessed: ' .. guess)
    end

    return false
end)

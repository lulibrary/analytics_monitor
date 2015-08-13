#! /usr/bin/lua

local datafile = 'alma_analytics.log'
local html_template = 'paal_template.html'
local html_file = 'paal.html'
local ss = string.sub

--[[
some code (spairs, tprint, compute_mode, compute_median) nicked from
various lua tutorial sites
--]]

-- return table sorted by the index
local function spairs(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end


-- return epoch seconds from date, time
local function ts2secs(Y, M, D, h, m, s)
    return os.time({
        year = Y, month = M, day = D, hour = h, min = m, sec = s
    })
end


-- return epoch seconds from date, time
local function dt2secs(d, t)
    local Y, M, D = ss(d, 1, 4), ss(d, 5, 6), ss(d, 7, 8)
    local h, m, s = ss(t, 1, 2), ss(t, 3, 4), ss(t, 5, 6)
    return ts2secs(Y, M, D, h, m, s)
end


-- for debugging
local function tprint(tbl, indent)
    if not indent then indent = 4 end
    for k, v in spairs(tbl) do
        local formatting = string.rep('  ', indent) .. k .. ': '
        if type(v) == 'table' then
            print(formatting)
            tprint(v, indent + 1)
        elseif type(v) == 'boolean' then
            print(formatting .. tostring(v))
        else
            print(formatting .. v)
        end
    end
end


local function compute_mode(t)
    local counts = {}
    for _, v in pairs(t) do
        if counts[v] == nil then
            counts[v] = 1
        else
            counts[v] = counts[v] + 1
        end
    end
    local biggestCount = 0
    for _, v in pairs(counts) do
        if v > biggestCount then
            biggestCount = v
        end
    end
    local mode = 0
    for k, v in pairs(counts) do
        if v == biggestCount then
            mode = k
        end
    end
    return mode
end


local function compute_median(t)
    table.sort(t)
    local mt_sz = #t
    if (mt_sz % 2) == 0 then
        return t[mt_sz / 2] + t[mt_sz / 2 + 1]
    else
        return t[math.ceil(mt_sz / 2)]
    end
end


local function compute_averages(u)
    local daily_averages = {}
    for date, day_data in spairs(u) do
        local sum, c, min, max = 0, 0, 999, 0
        local mm_table = {}
        for _, data in spairs(day_data) do
            local rt = tonumber(data['resp_time'])
            sum = sum + rt
            c = c + 1
            mm_table[#mm_table + 1] = rt
            if (rt <= min) then min = rt end
            if (rt >= max) then max = rt end
        end
        daily_averages[date] = {
            mean = sum / c,
            median = compute_median(mm_table),
            min = min,
            max = max,
            range = max - min,
            mode = compute_mode(mm_table)
        }
    end
    return daily_averages
end


local function sum_state_secs(u, d, a, state)
    local up, down = u, d
    if state == 'down' then
        down = d + a
    else
        up = u + a
    end
    return up, down
end


local function compute_state_times(u)
    local daily_uptime = {}
    for date, day_date in spairs(u) do
        local up, down = 0, 0
        local last_es, first = nil, true
        local last_time, last_state
        for time, data in spairs(day_date) do
            local state = data['state']
            local es = data['seconds']
            if first then
                first = false
                es = dt2secs(date, '000000')
                last_es = es
            end
            up, down = sum_state_secs(up, down, es - last_es, state)
            last_es = es
            last_time = time
            last_state = state
        end
        last_es = day_date[last_time]['seconds']
        local midnight = dt2secs(date, '235959') + 1
        up, down = sum_state_secs(up, down,
            midnight - last_es, last_state)
        daily_uptime[date] = {
            up = up,
            down = down,
            up_hours = up / 60 / 60,
            down_hours = down / 60 / 60
        }
    end
    return (daily_uptime)
end


local function readfile(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end


local function get_uptimes()
    local uptimes = {}
    local uptimes_day = {}
    local first = true
    local current_date
    local current_state

    for l in io.lines(datafile) do
        local lt = {}
        for w in string.gmatch(l, '%S+') do
            lt[#lt + 1] = w
        end
        local ts, state, resp_time = lt[1], lt[2], ss(lt[3], 6, -2)
        local Y, M, D = ss(ts, 1, 4), ss(ts, 5, 6), ss(ts, 7, 8)
        local h, m, s = ss(ts, 10, 11), ss(ts, 12, 13), ss(ts, 14, 15)
        local date = Y .. M .. D
        local time = h .. m .. s
        local seconds = ts2secs(Y, M, D, h, m, s)
        if first then
            first = false
            current_date = date
        end
        if not (current_date == date) then
            uptimes[current_date] = uptimes_day
            uptimes_day = {}
            current_date = date
        end
        uptimes_day[time] = {
            state = state,
            seconds = seconds,
            resp_time = resp_time
        }
        uptimes[current_date] = uptimes_day
        current_state = state
    end
    return current_state, uptimes
end


local function repeat_s(s, n)
    local ns = ''
    for _ = 1, n do
        --noinspection StringConcatenationInLoops
        ns = ns .. s .. ', '
    end
    ns = string.gsub(ns, ', $', '')
    return ns
end


local function mkjs(date_data, fields)
    local precisions = {
        mean = 2, median = 1, mode = 3,
        range = 1, max = 1, min = 1,
        up_hours = 2, down_hours = 2
    }
    local js = ''
    local nfields = #fields
    for d, data in spairs(date_data) do
        local data_list = {}
        local Y, M, D = ss(d, 1, 4), ss(d, 5, 6) - 1, ss(d, 7, 8)
        for _, f in pairs(fields) do
            local format = '%.' .. precisions[f] .. 'f'
            data_list[#data_list + 1] = string.format(format, data[f])
        end
        local fmt = '[new Date(%s, %s, %s), ' ..
                repeat_s('%s', nfields) .. '],\n'
        local line = string.format(fmt, Y, M, D, table.unpack(data_list))
        --noinspection StringConcatenationInLoops
        js = js .. line
    end
    return js
end


-- main
local current_state, uptimes = get_uptimes()
local daily_averages = compute_averages(uptimes)
local daily_uptimes = compute_state_times(uptimes)
local t_html = readfile(html_template)
local js = mkjs(daily_uptimes, { 'up_hours' })
local html = string.gsub(t_html, '//DATA1', js)
js = mkjs(daily_averages, { 'mean', 'median' })
html = string.gsub(html, '//DATA2', js)
js = mkjs(daily_averages, { 'mode' })
html = string.gsub(html, '//DATA3', js)
js = mkjs(daily_averages, { 'range', 'max', 'min' })
html = string.gsub(html, '//DATA4', js)
local state_s
if current_state == 'up' then
    state_s = '<span style="color: ForestGreen;">up</span>'
else
    state_s = '<span style="color: OrangeRed;">down</span>'
end
html = string.gsub(html, 'AA_STATE', state_s)
io.output(html_file)
io.write(html)


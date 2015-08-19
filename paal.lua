#! /usr/bin/lua

local datafile = 'alma_analytics.log'
local html_template = 'paal_template.html'
local html_file = 'paal.html'
local ss = string.sub
local unpack = unpack or table.unpack


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
        local mean, mode, sum, c, min, max = 0, 0, 0, 0, 999, 0
        local mm_table = {}
        for _, data in spairs(day_data) do
            local rt = tonumber(data['resp_time'])
            sum = sum + rt
            c = c + 1
            mm_table[#mm_table + 1] = rt
            if (rt <= min) then min = rt end
            if (rt >= max) then max = rt end
        end
        mean = sum / c
        mode = compute_mode(mm_table)
        daily_averages[date] = {
            mean = mean,
            median = compute_median(mm_table),
            min = min,
            max = max,
            range = max - min,
            mode = mode
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
    for date, day_data in spairs(u) do
        local up, down = 0, 0
        local last_es, first = nil, true
        local last_time, last_state
        for time, data in spairs(day_data) do
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
        last_es = day_data[last_time]['seconds']
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
    local num_dp = 0
    local uptimes_day = {}
    local first = true
    local current_date, current_state, current_resp
    local current_state_start_time, current_state_time = 0, 0
    local current_state_start_time_str
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
        if not (date == '20150806') then -- ignoring first day of partial data
            local seconds = ts2secs(Y, M, D, h, m, s)
            if first then
                first = false
                current_date = date
                current_state = state
                current_state_start_time_str = string.format(
                    '%02d/%02d/%04d, %02d:%02d:%02d',
                    D, M, Y, h, m, s
                )
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
            if not (current_state == state) then
                current_state_start_time = seconds
                current_state = state
                current_state_start_time_str = string.format(
                    '%02d/%02d/%04d, %02d:%02d:%02d',
                    D, M, Y, h, m, s)
            end
            current_state = state
            current_state_time = seconds - current_state_start_time
            current_resp = string.format("%.3f", resp_time)
            num_dp = num_dp + 1
        end
    end
    return current_resp, current_state, current_state_start_time_str,
        current_state_time, uptimes, num_dp
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
        local line = string.format(fmt, Y, M, D, unpack(data_list))
        --noinspection StringConcatenationInLoops
        js = js .. line
    end
    return js
end


local function mk_downtime_table(u, min_len)
    local dt_table = {}
    local current_state, first = nil , true
    local start_date, start_time, end_date, end_time
    for date, day_data in spairs(u) do
        for time, data in spairs(day_data) do
            local state = data['state']
            if first then
                first = false
                current_state = state
                if current_state == 'down' then
                    start_date = date
                    start_time = time
                end
            end
            if not (current_state == state) then
                if state == 'down' then
                    start_date = date
                    start_time = time
                else
                    end_date = date
                    end_time = time
                    local i_length = dt2secs(end_date, end_time)
                            - dt2secs(start_date, start_time)
                    if (i_length >= (min_len * 60)) then
                        dt_table[#dt_table + 1] = {
                            start_dt = start_date .. ':' .. start_time,
                            end_dt = end_date .. ':' .. end_time
                        }
                    end
                end
            end
            current_state = state
        end
    end
    return dt_table
end


local function mkjs_dt_table(dt)
    local js = ''
    for _, incident in pairs(dt) do
        local sd = incident['start_dt']
        local ed = incident['end_dt']
        local stY, stM, stD = ss(sd, 1, 4), ss(sd, 5, 6), ss(sd, 7, 8)
        local sth, stm, sts = ss(sd, 10, 11), ss(sd, 12, 13), ss(sd, 14, 15)
        local edY, edM, edD = ss(ed, 1, 4), ss(ed, 5, 6), ss(ed, 7, 8)
        local edh, edm, eds = ss(ed, 10, 11), ss(ed, 12, 13), ss(ed, 14, 15)
        local start_secs = ts2secs(stY, stM, stD, sth, stm, sts)
        local end_secs = ts2secs(edY, edM, edD, edh, edm, eds)
        local out_s = end_secs - start_secs
        local out_label = string.format("%02d:%02d:%02d",
            out_s/(60*60), out_s/60%60, out_s%60)
        local fmt = '[new Date(%4d, %02d, %02d, %02d, %02d, %02d), ' ..
                'new Date(%4d, %02d, %02d, %02d, %02d, %02d), {v:%d, f:\'%s\'}],\n'
        local line = string.format(
            fmt,
            stY, stM - 1, stD, sth, stm, sts,
            edY, edM - 1, edD, edh, edm, eds,
            out_s, out_label
        )
        --noinspection StringConcatenationInLoops
        js = js .. line
    end
    return js
end

-- main
local out_mins = 2
local current_resp, current_state, current_state_start,
    current_state_seconds, uptimes, num_dp = get_uptimes()
local daily_averages = compute_averages(uptimes)
local daily_uptimes = compute_state_times(uptimes)
local downtimes = mk_downtime_table(uptimes, out_mins)
local t_html = readfile(html_template)
local js = mkjs(daily_uptimes, {'up_hours'})
local html = string.gsub(t_html, '//DATA1', js)
js = mkjs(daily_averages, {'mean', 'median'})
html = string.gsub(html, '//DATA2', js)
js = mkjs(daily_averages, {'mode'})
html = string.gsub(html, '//DATA3', js)
js = mkjs(daily_averages, {'max', 'min'})
html = string.gsub(html, '//DATA4', js)
js = mkjs_dt_table(downtimes)
html = string.gsub(html, '//DATA7', js)
html = string.gsub(html, '//OUTMINS', out_mins)
local state_s, bg_colour, heading_colour
if current_state == 'up' then
    bg_colour = '#f8fff4'
    state_s = 'up'
    heading_colour = 'DarkGreen'
else
    bg_colour = '#fffaf9'
    state_s = 'down'
    heading_colour = 'DarkRed'
end
html = string.gsub(html, '//AA_STATE', state_s)
html = string.gsub(html, '//HEADING_COLOUR', heading_colour)
local date_s = os.date("%A, %d/%m/%Y %H:%M", os.time())
html = string.gsub(html, '//CURRENT_DT', date_s)
html = string.gsub(html, '//BG_COLOUR', bg_colour)
html = string.gsub(html, '//AA_RESPONSE', current_resp)
local logo_img_uri = 'http://www.lancaster.ac.uk/media/wdp/' ..
        'style-assets/images/library/library.png'
html = string.gsub(html, '//LOGO_IMG_URI', logo_img_uri)
local logo_link_uri = 'http://lancaster.ac.uk/library'
html = string.gsub(html, '//LOGO_LINK_URI', logo_link_uri)
local institution = 'Lancaster'
html = string.gsub(html, '//INSTITUTION', institution)
local alma_instance = 'EU00'
html = string.gsub(html, '//ALMA_INSTANCE', alma_instance)
local css_str = string.format("%02d:%02d:%02d",
    current_state_seconds/(60*60),
    current_state_seconds/60%60,
    current_state_seconds%60)
html = string.gsub(html, '//CURRENT_STATE_TIME', css_str)
html = string.gsub(html, '//CURRENT_STATE_START', current_state_start)
html = string.gsub(html, '//NUM_DATA_POINTS', num_dp)
io.output(html_file)
io.write(html)


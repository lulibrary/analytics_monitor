
local datafile = 'alma_analytics.log'
local html_template = 'paal_template.html'
local html_file = 'paal.html'
local ss = string.sub


function spairs(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]] end
    end
    return iter
end


local function ts2secs(Y, M, D, h, m, s)
    return os.time({year=Y, month=M, day=D, hour=h, min=m, sec=s})
end


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
    local counts={}
    for k, v in pairs(t) do
        if counts[v] == nil then
            counts[v] = 1
        else
            counts[v] = counts[v] + 1
        end
    end
    local biggestCount = 0
    for _, v  in pairs(counts) do
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
    local median
    table.sort(t)
    local mt_sz = #t
    if (mt_sz % 2) == 0 then
        median = t[mt_sz/2] + t[mt_sz/2 + 1]
    else
        median = t[math.ceil(mt_sz/2)]
    end
    return median
end


local function add_averages(u)
    for _, day_data in spairs(u) do
        local sum, c, mean, min, max = 0, 0, 0, 999, 0
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
        day_data['mean_resp'] = mean
        day_data['median_resp'] = compute_median(mm_table)
        day_data['min_resp'] = min
        day_data['max_resp'] = max
        day_data['range_resp'] = max - min
        day_data['mode_resp'] = compute_mode(mm_table)
    end
    return u
end

local function compute_state_seconds(u)
    for _, day_data in spairs(u) do
        local first = true
        local state_secs, up_secs, down_secs, period_start = 0, 0, 0, 0
        local current_state
        for _, data in spairs(day_data) do
            local es = data['seconds']
            local st = data['state']
            if first then
                first = false
                current_state = st
                period_start = es
            end
            if not (current_state == state) then
                print('state_change', current_state, state)
                state_secs = es - period_start
                current_state = state
                if state == 'down' then
                    down_secs = down_secs + state_secs
                else
                    up_secs = up_secs + state_secs
                end
            end
            state_secs = es - period_start
        end
        day_data['time_up'] = up_secs
        day_data['time_down'] = down_secs
    end
    return u
end


local uptimes = {}
local uptimes_day = {}
local first = true
local current_date


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
    uptimes_day[time] = {state=state, seconds=seconds, resp_time=resp_time}
end

--uptimes = add_averages(uptimes)
uptimes = compute_state_seconds(uptimes)
tprint(uptimes)

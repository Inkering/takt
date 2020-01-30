-- takt v2
-- @its_your_bedtime
--
-- parameter locking sequencer
--

local engines = include('lib/engines')
local ui = include('lib/ui')
local linn = include('lib/linn')
local beatclock = require 'beatclock'
local music = require 'musicutil'
local fileselect = require('fileselect')
local textentry = require('textentry')
local midi_clock
local hold_time = 0
local down_time = 0

-- midi 
local midi_in_device
local REC_CC = 38
-- 
local blink = 1
local ALT, SHIFT, MOD, PATTERN_REC = false, false, false, false
local hold, holdmax, first, second = {}, {}, {}, {}
local copy = { false, false }
local ptn_copy = false

local g = grid.connect()

local data = {
  pattern = 1,
  ui_index = 1,
  selected = { 1, false }, 
  settings = {},
  in_l = 0,
  in_r = 0,
  sampling = {
    source = 1,
    mode = 1,
    play = false,
    rec = false,
    start = 0,
    length = 60,
    slot = 1, 
  },

  metaseq = { from = 1, to = 1 },

}


local view = { steps_engine = true, notes_input = false, sampling = false, patterns = false } 

local choke = { 1, 2, 3, 4, 5, 6, 7 }

local param_ids = {
      ['sr'] = "quality",  
      --['mode'] = "play_mode", 
      ['start'] = "start_frame", 
      ['s_end'] = "end_frame",
      ['freq_lfo1'] = "freq_mod_lfo_1", 
      ['freq_lfo2'] = "freq_mod_lfo_2", 
      ['ftype'] = "filter_type", 
      ['cutoff'] = "filter_freq", 
      ['resonance'] = "filter_resonance", 
      ['cut_lfo1'] = "filter_freq_mod_lfo_1", 
      ['cut_lfo2'] = "filter_freq_mod_lfo_2", 
      ['pan'] = "pan",
      ['vol'] = "amp", 
      ['amp_lfo1'] = "amp_mod_lfo_1", 
      ['amp_lfo2'] = "amp_mod_lfo_2",
      ['attack'] = "amp_env_attack",
      ['decay'] = "amp_env_decay", 
      ['sustain'] = "amp_env_sustain", 
      ['release'] = "amp_env_release",
}


local locks_defaults = {
  
        offset = 0,
        sample = l,
        note = 60,
        retrig = 0,
        mode = 3,
        start = 0,
        s_end = 999999,
        vol = 0,
        pan = 0,
        attack = 0,
        decay = 1,
        sustain = 1,
        release = 0,
        ftype = 1,
        cutoff = 20000,
        resonance = 0,
        sr = 4,
        freq_lfo1 = 0,
        freq_lfo2 = 0,
        amp_lfo1 = 0,
        amp_lfo2 = 0,
        cut_lfo1 = 0,
        cut_lfo2 = 0,
        lock = 0,
        rule = 0,
        retrig = 0,
    }
    


local rule = {
  [0] =  { 'OFF', function() return true end },
  [1] =  { '10%', function() return 10 >= math.random(100) and true or false end },
  [2] =  { '20%', function() return 20 >= math.random(100) and true or false end },
  [3] =  { '30%', function() return 30 >= math.random(100) and true or false end },
  [4] =  { '50%', function() return 50 >= math.random(100) and true or false end },
  [5] =  { '60%', function() return 60 >= math.random(100) and true or false end },
  [6] =  { '70%', function() return 70 >= math.random(100) and true or false end },
  [7] =  { '90%', function() return 90 >= math.random(100) and true or false end },
  [8] =  {'/ 2', function(tr, step) return data[data.pattern].track.cycle[tr] % 2 == 0 and true or false  end },
  [9] =  {'/ 3', function(tr, step) return data[data.pattern].track.cycle[tr] % 3 == 0 and true or false  end },
  [10] = {'/ 4', function(tr, step) return data[data.pattern].track.cycle[tr] % 4 == 0 and true or false  end },
  [11] = {'/ 5', function(tr, step) return data[data.pattern].track.cycle[tr] % 5 == 0 and true or false  end },
  [12] = {'/ 6', function(tr, step) return data[data.pattern].track.cycle[tr] % 6 == 0 and true or false  end },
  [13] = {'/ 7', function(tr, step) return data[data.pattern].track.cycle[tr] % 7 == 0 and true or false  end },
  [14] = {'/ 8', function(tr, step) return data[data.pattern].track.cycle[tr] % 8 == 0 and true or false  end },
  [15] = {'RND NOTE', function(tr, step) 
    data[data.pattern][tr].params[step].note = math.random(20,120) return true end },
  [16] = {'+- NOTE', function(tr, step) 
    data[data.pattern][tr].params[step].note = data[data.pattern][tr].params[step].note + math.random(-10,10) return true end },
  [17] = {'RND START', function(tr, step) 
    data[data.pattern][tr].params[step].start = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval) 
    return true end },
  [18] = {'RND ST-EN', function(tr, step) 
    data[data.pattern][tr].params[step].start = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval)
    data[data.pattern][tr].params[step].s_end = math.random(0,params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval)
    return true end },
}


local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function reset_positions()
  for i = 1, 7 do
    data[data.pattern].track.pos[i] = 0
    data[data.pattern].track.p_pos[i] = 0
  end
end


local function set_bpm(n)
    data[data.pattern].bpm = n
    sequencer_metro.time = 60 / data[data.pattern].bpm  / 16 --[[ppqn]] / 4 
    midi_clock:bpm_change(data[data.pattern].bpm)
end

local function load_project(pth)
  
  sequencer_metro:stop() 
  midi_clock:stop()
  engine.noteOffAll()
  
  if string.find(pth, '.tkt') ~= nil then
    local saved = tab.load(pth)
    if saved ~= nil then
      print("data found")
      for k,v in pairs(saved[2]) do 
        data[k] = v 
      end
      
      -- refresh metatables ^^
      for t = 1, 16 do
        for l = 1, 7 do
          setmetatable(data[t][l].params['TR'.. l], { __index = locks_defaults })
          for k = 1, 16 do
            data[t][l].params[k] = saved[2][t][l].params[k]
           setmetatable(data[t][l].params[k], {__index =  data[t][l].params['TR'..l]})
          end
        end
      end
      
      -- load pset
      if saved[1] then params:read(norns.state.data .. saved[1] .. ".pset") end
      reset_positions()
    else
      print("no data")
    end
  end
end

local function save_project(txt)
  sequencer_metro:stop() 
  midi_clock:stop()
  engine.noteOffAll()
  if txt then
    tab.save({ txt, data }, norns.state.data .. txt ..".tkt")
    params:write( norns.state.data .. txt .. ".pset")
  else
    print("save cancel")
  end
end

local function get_step(x)
  return (x * 16) - 15
end

local function get_substep(tr, step)
    for s = (step*16) - 15, (step*16) + 15 do
      if data[data.pattern][tr][s] == 1 then
        return true
      end
    end
end

local function set_view(x)
    data.ui_index = 1 
    for k, v in pairs(view) do
      view[k] = k == x and true or false
    end
end

local function sync_tracks(tr)
    for i=1, 7 do
      if data[data.pattern].track.div[i] == data[data.pattern].track.div[tr] then
        data[data.pattern].track.pos[tr] = data[data.pattern].track.pos[i]
      end
    end
end

local function set_loop(tr, start, len)
  
    if start == 1 and len == 16 then
      sync_tracks(tr)
    end
    data[data.pattern].track.start[tr] = get_step(start)
    data[data.pattern].track.len[tr] = get_step(len) + 15
    
end

local function copy_step(src, dst)
  
    for i = 0, 15 do
      data[data.pattern][dst[1]][get_step(dst[2]) + i] = data[data.pattern][src[1]][get_step(src[2]) + i]
    end

    for k,v in pairs(data[data.pattern][src[1]].params[src[2]]) do
      data[data.pattern][dst[1]].params[dst[2]][k]  = v
    end
    
end

local function copy_pattern(src, dst)
    data[dst] = deepcopy(data[src])
end

local function get_params(tr, step, lock)
  
    if not step then
      
      return data[data.pattern][tr].params['TR' .. tr]
    
    else
      
      local res = data[data.pattern][tr].params[step] 
      if lock then 
        res.default = data[data.pattern][tr].params['TR' .. tr]
      end
      
      return data[data.pattern][tr].params[step] -- res
    end
end

local function is_lock()
    local src = data.selected
    if src[2] == false then
      return 'TR' .. src[1]
    else
      return src[2]
    end
end

local function open_sample_settings()
    local p = is_lock()
    norns.menu.toggle(true)
    _norns.enc(1, 1000)
    _norns.enc(2,-9999999)
    _norns.enc(2, 25 +(( data[data.pattern][data.selected[1]].params[p].sample - 1 ) * 94 ))
end

local function choke_group(tr, sample)
  if sample == choke[tr] then
      engine.noteOff(tr)
  end
end


local function set_locks(step_param)
    for k, v in pairs(step_param) do
      if param_ids[k] ~= nil then
        params:set(param_ids[k]  .. '_' .. step_param.sample, v)
      end
    end
end

local function place_note(tr, step, note)
  local p_step = math.ceil(step / 16)
  
  data[data.pattern][tr][step] = 1
  data[data.pattern][tr].params[p_step].lock = 1
  data[data.pattern][tr].params[p_step].note = note

end

local function metaseq(counter)
    if data[data.pattern].track.pos[1] >= data[data.pattern].track.len[1] - 1 then
        data.pattern = data.pattern < data.metaseq.to and data.pattern + 1 or data.metaseq.from
        set_bpm(data[data.pattern].bpm)
    end
end

local function seqrun(counter)

  for tr = 1, 7 do

      local start = data[data.pattern].track.start[tr]
      local len = data[data.pattern].track.len[tr]

      if counter % data[data.pattern].track.div[tr]== 0 then

        data[data.pattern].track.pos[tr] = util.clamp((data[data.pattern].track.pos[tr] + 1) % (len ), start, len) -- voice pos
        data[data.pattern].track.p_pos[tr] = math.ceil(data[data.pattern].track.pos[tr] / 16)
        data[data.pattern].track.cycle[tr] = counter % 256 == 0 and data[data.pattern].track.cycle[tr] + 1 or data[data.pattern].track.cycle[tr]  --data[data.pattern].track.cycle[tr]

        local mute = data[data.pattern].track.mute[tr]
        local pos = data[data.pattern][tr][data[data.pattern].track.pos[tr]]
        
        if pos == 1 and not mute then
          
          local step_param = get_params(tr, data[data.pattern].track.p_pos[tr])

          if rule[step_param.rule][2](tr, data[data.pattern].track.p_pos[tr]) then 
            
            if step_param.lock ~= 1 then
              
              ---step_param = get_params(tr, data[data.pattern].track.p_pos[tr])
              --set_locks(step_param)
            -- else
              
              step_param = get_params(tr)
              tab.print(step_param)
            end
            
            set_locks(step_param)
            choke_group(tr, step_param.sample)
            engine.noteOn(tr, music.note_num_to_freq(step_param.note), 1, step_param.sample)
            choke[tr] = step_param.sample
          end
       end
    end
  end
  
end

local function clear_substeps(tr, s )
    local l = get_step(s) 
    for s = l, l + 15 do
      data[data.pattern][tr][s] = 0
    end
end

local function move_substep(tr, step, t)
     for s = step, step + 15 do
      data[data.pattern][tr][s] = (s == t) and 1 or 0 
    end
end

local function make_retrigs(tr, step, t)
    local t = 16 - t 
    local offset = data[data.pattern][tr].params[step].offset
    
    local st = get_step(step) + 1

    for s = st + offset, (st + 14) - offset do
      if t == 16 then
        data[data.pattern][tr][s] = 0
      elseif s % t == 1 then
        data[data.pattern][tr][s] = s - offset == st and 1 or 0
      else
        data[data.pattern][tr][s] = ((s + offset) % t == 0) and 1 or 0
      end
    end
end

local function have_substeps(tr, step)
    local st = get_step(step) 
    for s = st, st + 15 do
      if data[data.pattern][tr][s] == 1 then
        return s
      end
    end
end

local function get_tr_start( tr )
  return math.ceil(data[data.pattern].track.start[tr] / 16)
end

local function get_tr_len( tr )
  return math.ceil(data[data.pattern].track.len[tr] / 16)
end


-- midi in
local function midi_event(d)
  
  local msg = midi.to_msg(d)
  local tr = data.selected[1] 

  local pos = data[data.pattern].track.pos[tr]
  
  -- REC TOGGLE
  if msg.cc == REC_CC and msg.val == 127 then
    PATTERN_REC = not PATTERN_REC
    print(PATTERN_REC)
  -- Note off
  elseif msg.type == "note_off" then
    --engine.noteOff(tr)
  -- Note on
  elseif msg.type == "note_on" then
    engine.noteOff(tr)
    engine.noteOn(tr, music.note_num_to_freq(msg.note), msg.vel / 127, data[data.pattern][tr].params['TR'..tr].sample)
    if sequencer_metro.is_running and PATTERN_REC then
      place_note(tr, pos, msg.note)
    end
  end

end


function init()
  
  math.randomseed(os.time())

    params:add_trigger('save_p', "< Save project" )
    params:set_action('save_p', function(x) textentry.enter(save_project,  'new') end)
    params:add_trigger('load_p', "> Load project" )
    params:set_action('load_p', function(x) fileselect.enter(norns.state.data, load_project) end)
    params:add_trigger('new', "+ New" )
    params:set_action('new', function(x) init() end)
    params:add_separator()


  
  local vu_l, vu_r = poll.set("amp_in_l"), poll.set("amp_in_r")
  vu_l.time, vu_r.time = 1 / 30, 1 / 30
  
  vu_l.callback = function(val) data.in_l = util.clamp(val * 180, 1, 70) end
  vu_r.callback = function(val) data.in_r = util.clamp(val * 180, 1, 70) end
  vu_l:start()
  vu_r:start()

    for i = 1, 7 do
      hold[i] = 0
      holdmax[i] = 0
      first[i] = 0
      second[i] = 0
    end


    --[[ 2do - propper track scaling 
    1/8X, 1/4X, 1/2X, 3/4X, 1X, 3/2X and 2X. 
    A setting of 1/8X will play back the pattern at one-eighth of the set tempo. 
    3/4X plays the pattern back at three-quarters of the tempo; 
    3/2X will play back the pattern twice as fast as the 3/4X setting. 
    2X will make the pattern play at twice the BPM.
    ]]


    for t = 1, 16 do
      data[t] = {
        bpm = 120,
        track = {
            mute = { false, false, false, false, false, false, false },
            pos = { 0, 0, 0, 0, 0, 0, 0 },
            p_pos =  { 0, 0, 0, 0, 0, 0, 0 },
            start =  { 1, 1, 1, 1, 1, 1, 1 },
            len = { 256, 256, 256, 256, 256, 256, 256 },
            div = { 1, 1, 1, 1, 1, 1, 1 },
            cycle = {1, 1, 1, 1, 1, 1, 1 },
          },
    }

      for l = 1, 7 do
  
        data[t][l] = {}
        data[t][l].params = {}
        data[t][l].params['TR'.. l] = {}
    
        setmetatable(data[t][l].params['TR'.. l], { __index = locks_defaults })
        data[t][l].params['TR'.. l].sample = l
        
        for i=0,256 do
          data[t][l][i] = 0
        end
        
        for k = 1, 16 do
          data[t][l].params[k] = {}
         setmetatable(data[t][l].params[k], {__index =  data[t][l].params['TR'..l]})
        end
      end
    end
  

    sequencer_metro = metro.init()
    sequencer_metro.time = 60 / data[data.pattern].bpm  / 16 --[[ppqn]] / 4 
    sequencer_metro.event = function(stage) seqrun(stage) metaseq(stage) end

    redraw_metro = metro.init(function(stage) redraw() g:redraw() blink = (blink + 1) % 17 end, 1/30)
    redraw_metro:start()
    midi_clock = beatclock:new()
    midi_clock.on_step = function() end
    midi_clock:bpm_change(data[data.pattern].bpm)
    midi_clock.send = true

    engines.init()
    ui.init()
    
    midi_in_device = midi.connect(1)
    midi_in_device.event = midi_event

end

local sampling_params = {
  [-1] = function(d) data.sampling.mode = util.clamp(data.sampling.mode + d, 1, 4) engines.set_mode(data.sampling.mode) end,
  [0] = function(d) data.sampling.source = util.clamp(data.sampling.source + d, 1, 2) engines.set_source(data.sampling.source) end,
  [3] = function(d) data.sampling.slot = util.clamp(data.sampling.slot + d, 1, 100) end,
  [4] = function(d) data.sampling.start = util.clamp(data.sampling.start + d / 10, 0, 60) engines.set_start(data.sampling.start) end,
  [5] = function(d) data.sampling.length = util.clamp(data.sampling.length + d / 10, 0.1, 60) engines.set_length(data.sampling.length) end,
  [6] = function(d) end, --play
  [1] = function(d) end, --save
  [2] = function(d) end, --clear
  [7] = function(d) end, --clear

}

local function get_len(tr, s)

   local maxval = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.maxval 
    if (data[data.pattern][tr].params[s].s_end > maxval) then --  and maxval ~= 2000000000) and data[data.pattern][tr].params[s].lock == 0 then 
        data[data.pattern][tr].params[s].s_end = maxval
    end
end

local step_params = {
  [-6] = function(tr, s, d) -- ptn
      data.pattern = (util.clamp(data.pattern + d, 1, 16))
  end,
  [-5] = function(tr, s, d) -- rnd
      data.selected[1] = util.clamp(data.selected[1] + d, 1, 7)
  end,
  [-4] = function(tr, s, d) -- rnd
      set_bpm(util.clamp(data[data.pattern].bpm + d, 1, 999))
  end,
  [-3] = function(tr, s, d) -- rnd
      data[data.pattern].track.div[tr] = util.clamp(data[data.pattern].track.div[tr] + d, 1, 16)
      sync_tracks(tr)
  end,
  [-2] = function(tr, s, d) -- rule
      data[data.pattern][tr].params[s].rule = util.clamp(data[data.pattern][tr].params[s].rule + d, 0, #rule)
  end,
  [-1] = function(tr, s, d) -- retrig
      data[data.pattern][tr].params[s].retrig = util.clamp(data[data.pattern][tr].params[s].retrig + d, 0, 15)
      make_retrigs(tr, s, data[data.pattern][tr].params[s].retrig)
  end,
  [0] = function(tr, s, d) -- offset
      data[data.pattern][tr].params[s].offset = util.clamp(data[data.pattern][tr].params[s].offset + d, 0, 15)
      move_substep(tr, get_step(s), get_step(s) + data[data.pattern][tr].params[s].offset)
      data[data.pattern][tr].params[s].retrig = 0
  end,
  [1] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].sample = util.clamp(data[data.pattern][tr].params[s].sample + d, 1, 100)
      --if data[data.pattern][tr].params[s] then get_len(tr, s) end
      get_len(tr, s)
  end, 
  [2] = function(tr, s, d) -- note
      data[data.pattern][tr].params[s].note = util.clamp(data[data.pattern][tr].params[s].note + d, 25, 127)
      --
  end,
  [3] = function(tr, s, d) -- start
      local sample = data[data.pattern][tr].params[s].sample
      --local start = params:get("start_frame_" .. sample)
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval 
      data[data.pattern][tr].params[s].start = util.clamp(data[data.pattern][tr].params[s].start + ((d) * 1000), 0,  length)
  end,
  [4] = function(tr, s, d) -- len
      local sample = data[data.pattern][tr].params[s].sample
      --local start = params:get("start_frame_" .. sample)
      local length = params:lookup_param("end_frame_" .. sample).controlspec.maxval 
      data[data.pattern][tr].params[s].s_end = util.clamp(data[data.pattern][tr].params[s].s_end + ((d) * 1000), 0, length)

   end,
  [5] = function(tr, s, d) -- freq mod lfo 1 freq_lfo1
        data[data.pattern][tr].params[s].freq_lfo1 = util.clamp(data[data.pattern][tr].params[s].freq_lfo1 + d / 100, 0, 1)
  end,
  [6] = function(tr, s, d) -- freq mod lfo 2
        data[data.pattern][tr].params[s].freq_lfo2 = util.clamp(data[data.pattern][tr].params[s].freq_lfo2 + d / 100, 0, 1)

  end,
  [7] = function(tr, s, d) -- volume
        data[data.pattern][tr].params[s].vol = util.clamp(data[data.pattern][tr].params[s].vol + d / 10  , -48, 16)
  end,
  [8] = function(tr, s, d) -- pan
        data[data.pattern][tr].params[s].pan = util.clamp(data[data.pattern][tr].params[s].pan + d / 10 , -1, 1)
  end,
  [9] = function(tr, s, d) -- atk
    data[data.pattern][tr].params[s].attack = util.clamp(data[data.pattern][tr].params[s].attack + d / 10, 0, 5)
  end,
  [10] = function(tr, s, d) -- dec
      data[data.pattern][tr].params[s].decay = util.clamp(data[data.pattern][tr].params[s].decay + d / 10, 0, 5)
  end,
  [11] = function(tr, s, d) -- sus
      data[data.pattern][tr].params[s].sustain = util.clamp(data[data.pattern][tr].params[s].sustain + d / 10, 0, 1)
  end,
  [12] = function(tr, s, d) -- rel
      data[data.pattern][tr].params[s].release = util.clamp(data[data.pattern][tr].params[s].release + d / 10, 0, 10)
  end,
  [13] = function(tr, s, d) -- amp mod lfo 1
        data[data.pattern][tr].params[s].amp_lfo1 = util.clamp(data[data.pattern][tr].params[s].amp_lfo1 + d / 100, 0, 1)

  end,
  [14] = function(tr, s, d) -- amp mod lfo 2
        data[data.pattern][tr].params[s].amp_lfo2 = util.clamp(data[data.pattern][tr].params[s].amp_lfo2 + d / 100, 0, 1)

  end,
  [15] = function(tr, s, d) -- sample rate
      data[data.pattern][tr].params[s].sr = util.clamp(data[data.pattern][tr].params[s].sr + d, 1, 4)
  end,
  [16] = function(tr, s, d) -- filter type
      data[data.pattern][tr].params[s].ftype = util.clamp(data[data.pattern][tr].params[s].ftype + d, 1, 2)
  end,
  [17] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].cutoff = util.clamp(data[data.pattern][tr].params[s].cutoff + (d * 100), 0, 20000)
  end,
  [18] = function(tr, s, d) -- sample
      data[data.pattern][tr].params[s].resonance = util.clamp(data[data.pattern][tr].params[s].resonance + d / 10, 0, 1)
  end,
  [19] = function(tr, s, d) -- filter cutoff mod lfo 1
        data[data.pattern][tr].params[s].cut_lfo1 = util.clamp(data[data.pattern][tr].params[s].cut_lfo1 + d / 100, 0, 1)

  end,
  [20] = function(tr, s, d) -- filter cutoff mod lfo 2
        data[data.pattern][tr].params[s].cut_lfo2 = util.clamp(data[data.pattern][tr].params[s].cut_lfo2 + d / 100, 0, 1)

  end,
  
}

function enc(n,d)
  norns.encoders.set_sens(1,2)
  norns.encoders.set_sens(2,2)
  norns.encoders.set_accel(1, false)
  norns.encoders.set_accel(2, false)
  norns.encoders.set_accel(3, ((data.ui_index == 3 or data.ui_index == 4) and view.steps_engine) and true or false)

  local tr = data.selected[1]
  local s = data.selected[2] and data.selected[2] or 'TR' .. data.selected[1]
  
  if n == 1 then
    
    data.selected[1] = util.clamp(data.selected[1] + d, 1, 7)
  
  elseif n == 2 then
    
    if not view.sampling then
      if not K1_hold then 
        data.ui_index = util.clamp(data.ui_index + d, not data.selected[2] and 1 or -2, 20)
      else
        data.ui_index = util.clamp(data.ui_index + d, -6, -1)
      end
    else
      if not data.sampling.rec then
        data.ui_index = util.clamp(data.ui_index + d, -1, 6)      
      end
    end
  elseif n == 3 then
    
    if not view.sampling then 
      
      local p = is_lock()
      
      if data.selected[2] then 
        data[data.pattern][tr].params[s].lock = 1 
      end 
      
      step_params[data.ui_index](tr, p, d)
      
     -- if not data.selected[2] then
       --   set_locks(get_params(tr))
      --end
      
    else
      
      sampling_params[data.ui_index](d)
    end
  end
end

function key(n,z)
  if n == 1 then  -- main settings
    K1_hold = z == 1 and true or false
    if z == 1 and not view.sampling then 
      data.ui_index = -4
    elseif z == 0 and not view.sampling then  
      data.ui_index = 1
    end
  end

  if n == 2 and z == 1 then
  
  -- not used
  
  elseif n == 3 then
    -- sampling page
    if view.sampling then
      if data.ui_index == 1 and z == 1  then
        
        data.sampling.rec = not data.sampling.rec
        if data.sampling.rec then data.sampling.start = 0 end
        engines.rec(data.sampling.rec)
      
      elseif data.ui_index == 2 or data.ui_index == 4 or data.ui_index == 5 then
        
        data.sampling.play = not data.sampling.play
        engines.play(z == 1 and true or false)
        
      elseif data.ui_index == 3 and z == 1  then
        
        data.sampling.play = false
        data.sampling.rec = false
        engines.play(false)
        engines.rec(false)
        engines.save_and_load(data.sampling.slot)
        params:set('play_mode_' .. data.sampling.slot, 2)
        
      elseif data.ui_index == 6  and z == 1 then
        
        engines.clear()
        data.sampling.start = 0
      
      end
    else 
      -- main 
      if data.ui_index == 1 then
        open_sample_settings()
      end
    end
  end
end






function redraw()

  local tr = data.selected[1]
  local params_data = get_params(data.selected[1])

  local lockd = data[data.pattern][tr].params[data[data.pattern].track.p_pos[tr]]
  
  if data.selected[2] then
    params_data = get_params(data.selected[1], data.selected[2], true)
  elseif lockd and lockd.lock  == 1 then 
    params_data = get_params(data.selected[1], data[data.pattern].track.p_pos[data.selected[1]], true)
    
  end

  screen.clear()
  
  ui.head(params_data, data, view, K1_hold, rule, PATTERN_REC)
  
  if view.sampling then 
    ui.sampling(params_data, data, engines.get_pos(), engines.get_len(), engines.get_state()) 
  else
    ui.main_screen(params_data, data)
  end

  screen.update()

end

local controls = {
  [1] = function(z) -- start / stop, 
      if z == 1 then
        if sequencer_metro.is_running then 
          sequencer_metro:stop() 
          midi_clock:stop()
          if MOD then engine.noteOffAll() end
        else 
          sequencer_metro:start() 
          midi_clock:start()
        end
        if MOD then
          reset_positions()
        end
      end
    end,
  [3] = function(z)  if view.notes_input and z == 1 and sequencer_metro.is_running then PATTERN_REC = not PATTERN_REC end end,
  [8] = function(z)  if z == 1 then set_view('steps_engine') PATTERN_REC = false end end,
  [9] = function(z)  if z == 1 then set_view(view.notes_input and 'steps_engine' or 'notes_input') end end,
  [10] = function(z) if z == 1 then set_view(view.sampling and 'steps_engine' or 'sampling') end  end,
  [11] = function(z) if z == 1 then set_view(view.patterns and 'steps_engine' or 'patterns') end end,
  [13] = function(z) MOD = z == 1 and true or false if z == 0 then copy = { false, false } end end,
  [15] = function(z) ALT = z == 1 and true or false end,
  [16] = function(z) SHIFT = z == 1 and true or false end,
}


function g.key(x, y, z)
    screen.ping()
    if view.notes_input then
      
        local note = linn.grid_key(x, y, z)
        
        if note then 
            local current = data.selected[2] or 'TR'.. data.selected[1]
            engine.noteOn(data.selected[1], music.note_num_to_freq(note), 1, data[data.pattern][data.selected[1]].params[current].sample)
        end
        
        if sequencer_metro.is_running and note and PATTERN_REC then 
            local tr = data.selected[1]
            local pos = data[data.pattern].track.pos[tr]
            place_note(tr, pos, note)
        end
        
    end    
        
  if y < 8 then
    local held
    local cond = have_substeps(y, x) 

    if z==1 and hold[y] then
      holdmax[y] = 0
    end
    hold[y] = hold[y] + (z * 2 - 1)
    if hold[y] > holdmax[y] then
      holdmax[y] = hold[y]
    end

    if view.steps_engine or view.sampling then
      
      -- mutes, speed divs
      if SHIFT then
        
        if z == 1 then
          if x == 16 then
            data[data.pattern].track.mute[y] = not data[data.pattern].track.mute[y]
            if data[data.pattern].track.mute[y] then 

              engine.noteOff(choke[y])
            end
          else
            data[data.pattern].track.div[y] = x
            sync_tracks(y)
          end
        end
        
      -- track start/end  
      elseif ALT then 

          if hold[y] == 1 then
            first[y] = x
          elseif hold[y] == 2 then
            second[y] = x
            set_loop(y, first[y], second[y])
          end
      
      -- copy mode
      elseif MOD then
        if not copy[1] then 
          copy = { y, x }
        else
          copy_step(copy, {y, x})
        end
        
      -- main 
      else 
        
        data.selected = { y, z == 1 and x or false }
        
        if not data.selected[2] and data.ui_index < 1 then data.ui_index = 1 end

       if z == 1 then
        
          down_time = util.time()

        else
          
          hold_time = util.time() - down_time
          held = hold_time > 0.2 and true or false
          
          if not cond then
            
            data[data.pattern][y][get_step(x)] = 1

          elseif cond and not held then

            clear_substeps(y, x)
            
            data[data.pattern][y].params[x] = {}
            setmetatable(data[data.pattern][y].params[x], {__index =  data[data.pattern][y].params['TR'..y]})

            data.selected = { y, false }
    
          end
        end        
      end
      
      
    elseif view.patterns then
      if y == 1 and z == 1 then
        if MOD then 
            
            if not ptn_copy then 
              ptn_copy = x
            else
              copy_pattern(ptn_copy, x)
            end
            
        else
          
          if hold[y] == 1 then
            first[y] = x
              
            data.pattern = x
            ptn_copy = false
            data.metaseq.from = x
            data.metaseq.to = x
            
          elseif hold[y] == 2 then
            second[y] = x

            data.metaseq.from = first[y]
            data.metaseq.to = second[y]
            
          end
        end
      end
    end
  
  else
    
    if controls[x] then
      controls[x](z)
    end
    
  end
  
end

function g.redraw() 
  g:all(0)
  
  if view.notes_input then 
      linn.grid_redraw(g)
  end
  
  for y = 1, 7 do 
    for x = 1, 16 do 
      if view.notes_input then 
        
      elseif not view.patterns then
        if SHIFT then
          
            g:led(data[data.pattern].track.div[y], y, 15)
            g:led(16, y, data[data.pattern].track.mute[y] and 15 or 6 )

        elseif ALT then
          
            local t_start = get_tr_start(y)
            local t_len  = get_tr_len(y)
            if x >= t_start and x <= t_len then
              g:led(x, y, 3)
            end

          
        else
          
          local p = (x * 16) - 15
          for s = 0, 15 do
            if data[data.pattern][y][p + s] == 1 then
              local level = data.selected[1] == y and data.selected[2] == x and 15 or 10
              g:led(x, y, level ) 
            end
          end
          
        end
      else
        
        for i = 1, 16 do
          
          local level =
          data.pattern == i and sequencer_metro.is_running and  util.clamp(blink, 5, 14)
          or (i >= data.metaseq.from and i <= data.metaseq.to) and 9 
          or data.pattern == i and 15 
          or 3
          
          g:led(i, 1, level)
        end
      end
    end 
  end
  
  if sequencer_metro.is_running and view.steps_engine and not SHIFT then
    for i = 1, 7 do
      local pos = math.ceil(data[data.pattern].track.pos[i] / 16)
      if not data[data.pattern].track.mute[i] then g:led(pos, i, 6 ) end
    end
  end
  
  local glow = util.clamp(blink,5,15)
  
  g:led(1, 8,  sequencer_metro.is_running and 15 or 6 )
  g:led(3, 8,  (view.notes_input and PATTERN_REC) and glow or view.notes_input and 6 or  0)
  g:led(8, 8,  view.steps_engine and 15  or  6)
  g:led(9, 8,  view.notes_input and 15 or  6)
  g:led(10, 8, view.sampling and 15 or 6)
  g:led(11, 8, view.patterns and 15 or 6)

  g:led(13, 8, MOD and glow or 6 )
  g:led(15, 8, ALT and glow  or 6 )
  g:led(16, 8, SHIFT and glow  or 6 )
  
  
  g:refresh()

end
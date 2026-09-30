return function(make_api,patch)
    if rawget(_G,'RapidArcThrowerV1') then return end
    local state={version='0.10',active=false,status='Waiting for first game update',scanned=0,candidates=0,diagnostics={}}
    _G.RapidArcThrowerV1=state
    local previous=update
    local callback
    local function log()
        pcall(function()
            local logger=rawget(_G,'CowboyBingusModLoader')
            local file=logger and logger.open_log and logger.open_log('RapidArcThrower.log')
            if file then
                file:write('RapidArcThrower v0.10\nstatus='..state.status..'\nscanned_bytes='..state.scanned..'\ncandidates='..state.candidates..'\n'..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local deadline=0
    local logged_mb=-1
    local worker=coroutine.create(function()
        local api=make_api()
        api.note=function(message)
            if #state.diagnostics>=16 then table.remove(state.diagnostics,1) end
            state.diagnostics[#state.diagnostics+1]='validation='..message
        end
        api.checkpoint=function(stage,force)
            state.status=stage
            if force or os.clock()>=deadline then coroutine.yield() end
        end
        api.progress=function(scanned,total,candidates)
            state.scanned,state.candidates=scanned,candidates
            local mb=math.floor(scanned/16777216)
            if mb~=logged_mb then logged_mb=mb;log() end
        end
        local exe,game=api.module(nil),api.module('game.dll')
        assert(exe~=nil and game~=nil,'Game modules unavailable')
        assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06','Unsupported executable. No edit applied.')
        assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E','Unsupported game module. No edit applied.')

        state.status='Waiting for game data and companion mods to initialize'
        log()
        local ready_at=api.now()+30000
        repeat coroutine.yield() until api.now()>=ready_at
        for attempt=1,6 do
            state.status='Validating ARC-3 data; attempt '..attempt..'/6'
            log()
            local applied,reason=patch.apply(api,game)
            if applied then return reason end
            if not reason:find('found 0. No edit applied.',1,true) or attempt==6 then error(reason) end
            state.status='ARC-3 data not ready; retrying after loading'
            local until_time=api.now()+10000
            repeat coroutine.yield() until api.now()>=until_time
        end
    end)
    local function init()
        if coroutine.status(worker)=='dead' then return end
        deadline=os.clock()+0.004
        local ok,message=coroutine.resume(worker)
        if not ok or coroutine.status(worker)=='dead' then
            state.active,state.status=ok,tostring(message)
            print('[RapidArcThrower] '..state.status)
            log()
            if update==callback then update=previous or function() end end
        end
    end
    local function finish(...) init();return ... end
    callback=function(...)
        if previous then return finish(previous(...)) end
        init()
    end
    update=callback
    log()
end

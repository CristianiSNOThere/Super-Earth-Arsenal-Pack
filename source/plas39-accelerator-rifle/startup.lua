return function(make_api, patch, native)
    if rawget(_G,'Plas39FireModeV1') then return end
    local state={version='1.1.8',status='Waiting for game data',mode='Reading native selection',
        scanned=0,candidates=0,instances=0,diagnostics={}}
    _G.Plas39FireModeV1=state
    local previous=update
    local callback,plan,api
    local deadline=0
    local last_message
    local function log()
        pcall(function()
            local loader=rawget(_G,'CowboyBingusModLoader')
            local file=loader and loader.open_log and loader.open_log('Plas39FireMode.log')
            if file then
                file:write('Plas39FireMode v'..state.version..'\nstatus='..state.status
                    ..'\nmode='..state.mode..'\nnative_instances='..state.instances
                    ..'\nscanned_bytes=0\nselection_source=native WeaponDataComponent state\n'
                    ..table.concat(state.diagnostics,'\n')..'\n')
                file:close()
            end
        end)
    end
    local worker=coroutine.create(function()
        api=make_api()
        api.checkpoint=function(stage)
            state.status=stage
            if os.clock()>=deadline then coroutine.yield() end
        end
        local exe,game=api.module(nil),api.module('game.dll')
        assert(exe and game,'Game modules unavailable')
        assert(api.module_hash(exe)=='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
            'Unsupported executable; no edit applied')
        assert(api.module_hash(game)=='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
            'Unsupported game module; no edit applied')
        for attempt=1,60 do
            local ok,result=pcall(patch.prepare,api,native)
            if ok then return result end
            local detail=tostring(result)
            local transient=detail:find('Native pointer unavailable',1,true)
                or detail:find('Native data unavailable',1,true)
            if not transient or attempt==60 then error(result) end
            state.status='Waiting for native component tables; attempt '..attempt..'/60'
            log()
            local retry=api.now()+1000
            repeat coroutine.yield() until api.now()>=retry
        end
    end)
    local function synchronize()
        if not plan then return end
        local ok,applied,label,changed,count=pcall(patch.synchronize,api,plan,native)
        local message
        if ok and applied then
            state.mode=label
            state.instances=count
            state.status='Native mode synchronized; left-side selector active'
            message=label
        else
            state.status=ok and label or tostring(applied)
            message=state.status
        end
        if message~=last_message then
            last_message=message
            print('[PLAS-39 Fire Mode] '..message)
            log()
        end
    end
    local function tick()
        if plan then synchronize()
        elseif coroutine.status(worker)~='dead' then
            deadline=os.clock()+0.0007
            local ok,result=coroutine.resume(worker)
            if not ok then
                state.status=tostring(result);log()
                print('[PLAS-39 Fire Mode] '..state.status)
                if update==callback then update=previous or function() end end
            elseif coroutine.status(worker)=='dead' then
                plan=result
                synchronize()
            end
        end
    end
    local function pack(...) return {n=select('#',...),...} end
    callback=function(...)
        tick()
        local results
        if previous then results=pack(previous(...)) end
        -- Read the native selection again after the game processes this frame.
        synchronize()
        if results then return unpack(results,1,results.n) end
    end
    update=callback
    log()
end

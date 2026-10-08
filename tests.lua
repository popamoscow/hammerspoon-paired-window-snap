--[[
Author: Pavel Potasuev
Questions and contact: https://potasuev.ru
License: MIT; see LICENSE. Run with Lua 5.3/5.4; uses fake hs APIs only.
]]
-- Isolated tests: module receives ONLY fake hs APIs. No real window/tap/filter.
local ownPath=debug.getinfo(1,"S").source:sub(2)
local root=ownPath:match("^(.*[/])") or "./"
local file=assert(io.open(root..'paired-window-snap.lua'));local source=file:read('*a');file:close()
local checks={}
local function check(name, value) assert(value,name);checks[#checks+1]=name end
local function copy(t) local n={};for k,v in pairs(t) do n[k]=v end;return n end
local function fixture(full, usable)
 full=full or {x=0,y=0,w=1600,h=1000};usable=usable or {x=0,y=25,w=1600,h=975}
 local f={now=100,queue={},writes={},focuses=0,filters={},tapStarts=0,permission=true}
 f.screen={fullFrame=function()return copy(full)end,frame=function()return copy(usable)end}
 local function window(id, frame)
  local w={rect=frame,visible=true,standard=true,full=false,closed=false}
  function w:id() if self.closed then error('closed')end;return id end
  function w:frame()
   self.frameReads=(self.frameReads or 0)+1
   if self.frameError or self.closed or self.frameFaultAt==self.frameReads then error("frame became invalid")end
   if self.nilFrame then return nil end
   return copy(self.rect)
  end
  function w:setFrame(rect)self.rect=copy(rect);f.writes[#f.writes+1]={id=id,frame=copy(rect)}end
  function w:isVisible()return self.visible end
  function w:isStandard()return self.standard end
  function w:isFullScreen()return self.full end
  function w:screen()return f.screen end
  function w:focus()f.focuses=f.focuses+1 end
  return w
 end
 f.a=window(1,{x=full.x+100,y=full.y+50,w=500,h=600})
 f.b=window(2,{x=full.x+800,y=full.y+50,w=500,h=600});f.focus=f.b
 f.hs={accessibilityState=function()return f.permission end,
  screen={allScreens=function()return {f.screen}end},
  window={focusedWindow=function()return f.focus end,filter={sortByFocusedLast=1,windowFocused='focused'}},
  timer={secondsSinceEpoch=function()return f.now end,doAfter=function(_,fn)
   local t={fn=fn,stopped=false};function t:stop()self.stopped=true end;table.insert(f.queue,t);return t end},
  eventtap={event={types={leftMouseDown=1,leftMouseDragged=2,leftMouseUp=3}},new=function(_,fn)
   f.callback=fn;local t={};function t:start()f.tapStarts=f.tapStarts+1;return self end
   function t:isEnabled()return f.tapEnabled~=false end
   function t:stop()return self end;return t end}}
 function f.hs.window.filter.new()
  local filter={};f.filters[#f.filters+1]=filter
  function filter:setCurrentSpace(v)self.currentSpace=v;return self end
  function filter:getWindows()return {f.a,f.b}end
  function filter:subscribe(_,fn)self.sub=fn;return self end
  function filter:unsubscribe(_,fn)assert(fn==self.sub);self.sub=nil;return self end
  function filter:pause()self.paused=true;return self end
  return filter
 end
 local env={hs=f.hs,assert=assert,pcall=pcall,type=type,tostring=tostring,ipairs=ipairs,pairs=pairs,math=math}
 f.m=assert(load(source,'paired-window-snap.lua','t',env))()
 function f:flush()local q=self.queue;self.queue={};for _,t in ipairs(q)do if not t.stopped then t.fn()end end end
 function f:emit(kind,p)assert(self.callback({getType=function()return kind end,location=function()return p end})==false)end
 function f:start()assert(self.m:start());self.focus=self.a;self.filters[#self.filters].sub(self.a)end
 function f:drag(to,hold,move)
  self:emit(1,{x=full.x+150,y=full.y+60});self:flush()
  if move~=false then self.a.rect.x=self.a.rect.x+50 end
  self:emit(2,to);self.now=self.now+(hold or 0.4);self:emit(3,to);self:flush()
 end
 return f
end
local f=fixture();check('require does not start taps',f.tapStarts==0)
f:start();f.m:start();check('start is idempotent',f.tapStarts==1 and #f.filters==1)
f:drag({x=0,y=400});check('left: dragged half',f.a.rect.x==0 and f.a.rect.w==800 and f.a.rect.y==25)
check('left: previous opposite half',f.b.rect.x==800 and f.b.rect.w==800 and #f.writes==2)
check('current-space filter',f.filters[1].currentSpace==true)
f.m:stop();check('stop unsubscribes and pauses owned filter',f.filters[1].sub==nil and f.filters[1].paused)
f.m:stop();f:start();check('restart creates one fresh filter',#f.filters==2 and f.tapStarts==2);f.m:stop()
f=fixture();f:start();f:drag({x=1599,y=400});check('right pair',f.a.rect.x==800 and f.b.rect.x==0 and #f.writes==2)
f=fixture();f:start();f:drag({x=800,y=0});check('top: only dragged window',f.a.rect.w==1600 and f.a.rect.h==975 and #f.writes==1)
f=fixture();f:start();f:drag({x=0,y=0});check('corner prioritizes side',f.a.rect.w==800 and #f.writes==2)
f=fixture();f:start();f:drag({x=0,y=400},0.29);check('short dwell rejected',#f.writes==0)
f=fixture();f:start();f:drag({x=0,y=400},0.31);check('dwell accepted',#f.writes==2)
f=fixture();f:start();f:drag({x=0,y=400},0.4,false);check('content drag without window motion rejected',#f.writes==0)
f=fixture();f.m:configure({minDrag=5000});f:start();f:drag({x=0,y=400});check('drag threshold enforced',#f.writes==0)
f=fixture();f.m:configure({minFrameChange=100});f:start();f:drag({x=0,y=400});check('frame-change threshold enforced',#f.writes==0)
f=fixture();f:start();f.b.closed=true;f:drag({x=0,y=400});check('closed partner skipped',#f.writes==1)
f=fixture();f:start();f.a.full=true;f:drag({x=0,y=400});check('fullscreen dragged window skipped',#f.writes==0)
f=fixture();f:start();f.b.visible=false;f:drag({x=0,y=400});check('hidden partner skipped',#f.writes==1)
f=fixture({x=-1440,y=-100,w=1440,h=900},{x=-1440,y=-78,w=1440,h=878});f:start();f:drag({x=-1440,y=400})
check('negative-origin monitor geometry',f.a.rect.x==-1440 and f.b.rect.x==-720 and f.a.rect.h==878)
f=fixture();f:start();f:emit(1,{x=150,y=60});f.m:stop();f:flush();check('stop cancels pending capture',#f.writes==0)
f=fixture();f:start();f:emit(1,{x=150,y=60});f:flush();f.a.rect.x=200;f:emit(2,{x=0,y=400});f.now=f.now+1;f:emit(3,{x=0,y=400});f.m:stop();f:flush();check('stop cancels pending release',#f.writes==0)
f=fixture();f:start();f:emit(1,{x=150,y=60});f:flush();f.a.rect.x=200;f:emit(2,{x=0,y=400});f.now=f.now+1;f:emit(3,{x=0,y=400});f:emit(1,{x=150,y=60});f:flush();check('new gesture invalidates old release',#f.writes==0)
f=fixture();check('invalid config rejected',not pcall(function()f.m:configure({dwell=-1})end))
check('unknown config rejected',not pcall(function()f.m:configure({typo=1})end))
check('NaN rejected',not pcall(function()f.m:configure({edge=0/0})end))
check('zero edge rejected',not pcall(function()f.m:configure({edge=0})end))
f.permission=false;local started,message=f.m:start();check('permission denial starts nothing',not started and message and f.tapStarts==0 and #f.filters==0)
f=fixture();f:start();f.a.frameError=true;f:drag({x=0,y=400});check('invalid frame during lookup quietly skips gesture',#f.writes==0)
f=fixture();f:start();f.a.frameFaultAt=2;f:drag({x=0,y=400});check('frame invalidated after lookup quietly skips gesture',#f.writes==0)
f=fixture();f:start();f.a.nilFrame=true;f:drag({x=0,y=400});check('nil frame quietly skips gesture',#f.writes==0)
f=fixture();f.tapEnabled=false;local started,message=f.m:start();check('failed tap start cleans up subscription',not started and message and f.filters[1].paused and f.filters[1].sub==nil and not f.m.running)
print('PASS '..#checks..' isolated Lua checks; no real window/tap/filter used')

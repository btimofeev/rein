local buf = {
  history_len = 128;
}

function buf:new(fname)
  local b = { cur = 1, fname = fname,
    hist = {}, sel = {}, text = {} }
  self.__index = self
  setmetatable(b, self)
  return b
end

function buf:gettext(s, e)
  if s or e then
    local t = ''
    for i = (s or 1), (e or #self.text) do
      t = t .. (self.text[i] or '')
    end
    return t
  end
  return table.concat(self.text, '')
end

function buf:changed(fl)
  local c = self.is_changed
  if fl ~= nil then
    self.is_changed = fl
  end
  return c
end

function buf:history(op, pos, nr)
  self:changed(true)
  pos = pos or self.cur
  nr = nr or 1
  local h = { op = op, pos = pos, nr = nr, cur = self.cur }
  table.insert(self.hist, h)
  if #h > self.history_len then
    table.remove(self.hist, 1)
  end
  if op == 'cut' then
    h.data = {}
    for i = 1, nr do
      table.insert(h.data, self.text[i + pos - 1])
    end
  end
end

function buf:undo()
  if #self.hist == 0 then return end
  self:changed(true)
  local depth = 0
  repeat
    local h = table.remove(self.hist, #self.hist)
    if h.op == 'start' then
      depth = depth + 1
    elseif h.op == 'end' then
      depth = depth - 1
    elseif h.op == 'cut' then
      for i = 1, h.nr do
        table.insert(self.text, h.pos + i - 1, h.data[i])
      end
    elseif h.op == 'input' then
      for _ = 1, h.nr do
        table.remove(self.text, h.pos)
      end
    end
    self.cur = h.cur
  until depth == 0
end

function buf:backspace()
  if self:issel() then
    return self:cut()
  end
  if self.cur <= 1 then return end
  self:history('cut', self.cur - 1)
  table.remove(self.text, self.cur - 1)
  self.cur = self.cur - 1
end

function buf:delete()
  if self:issel() then
    return self:cut()
  end
  if self.cur > #self.text then
    return
  end
  self:right()
  self:backspace()
end

function buf:kill()
  local start = self.cur
  self:lineend()
  if self.cur == start then
    self:delete()
  else
    self:setsel(start, self.cur)
    self:cut()
  end
end

function buf:sel_line()
  self:linestart()
  local start = self.cur
  self:lineend()
  if self.text[self.cur] == '\n' then
    self:setsel(start, self.cur + 1)
  else
    self:setsel(start, self.cur)
  end
end

function buf:newline()
  local cur = self.cur
  self:linestart()
  local c
  local pre = ''
  for i = self.cur, cur do
    c = self.text[i]
    if c == '\t' or c == ' ' then
      pre = pre .. c
    else
      break
    end
  end
  self.cur = cur
  self:input('\n'..pre)
end

function buf:setsel(s, e)
  self.sel.s, self.sel.e = s, e
end

function buf:issel()
  return (self.sel.s and self.sel.s ~= self.sel.e)
end

function buf:getsel()
  return self.sel
end

function buf:range()
  if self:issel() then
    local s, e = self:selrange()
    return s, e - 1
  end
  return self.cur, #self.text
end

function buf:selrange()
  local s, e = self.sel.s, self.sel.e
  if s > e then s, e = e, s end
  return s, e
end

function buf:getseltext()
  local r = ''
  if not self:issel() then return r end
  local s, e = self:selrange()
  for i = s, e - 1 do
    r = r .. self.text[i]
  end
  return r
end

function buf:resetsel()
  self.sel.s, self.sel.e = nil, nil
end

function buf:searchpos(pos, e, text, back)
  local fail
  local delta = 1
  local ws, we = 1, #text
  if back then
    delta = -1
    ws, we = #text, 1
  end
  for i = pos, e, delta do
    fail = false
    for k = ws, we, delta do
      if self.text[i + k - 1] ~= text[k] then
        fail = true
        break
      end
    end
    if not fail then
      self.cur = i
      self:setsel(i, i + #text)
      return true
    end
  end
end

function buf:search(text, back)
  if type(text) == 'string' then
    text = utf.chars(text)
  end
  if back then
    return self:searchpos(self.cur - 1, 1, text, true)
  end
  return self:searchpos(self.cur, #self.text, text) or
    self:searchpos(1, self.cur, text)
end

function buf:cut(copy)
  if not self:issel() then
    return
  end
  local clip = ''
  local s, e = self:selrange()
  if not copy then
    self:history('cut', s, e - s)
  end
  for i = s, e - 1 do
    clip = clip .. self.text[i]
  end
  if not copy then
    local new = {}
    for i = 1, #self.text do
      if i < s or i >= e then
        table.insert(new, self.text[i])
      end
    end
    self.text = new
  end
  if copy ~= false then
    sys.clipboard(clip)
    self.clipboard = clip
  end
  if not copy then
    self.cur = s
    self:resetsel()
  end
end

function buf:insel(cur)
  if not self:issel() then return end
  cur = cur or self.cur
  local s, e = self:selrange()
  return cur >= s and cur < e
end

function buf:paste()
  local clip = sys.clipboard() or self.clipboard
--  local start = self:issel() and self:selrange() or self.cur
  self:input(clip)
--  self:setsel(start, self.cur)
end

function buf:input(txt)
  self:history 'start'
  if self:issel() then
    self:cut(false)
  end
  if self.cur < 1 then return end
  local u = type(txt) == 'table' and txt or utf.chars(txt)
  self:history('input', self.cur, #u)
  for i = 1, #u do
    table.insert(self.text, self.cur, u[i])
    self.cur = self.cur + 1
  end
  self:history 'end'
end

function buf:nextline(pos)
  for i = (pos or self.cur), #self.text do
    if self.text[i] == '\n' then
      self.cur = i + 1
      break
    end
  end
  return self.cur
end

function buf:linestart(pos)
  for i = (pos or self.cur), 1, -1 do
    self.cur = i
    if self.text[i-1] == '\n' then
      break
    end
  end
  return self.cur
end

function buf:lineend(pos)
  for i = (pos or self.cur), #self.text do
    if self.text[i] == '\n' then
      break
    end
    self.cur = i + 1
  end
  return self.cur
end

function buf:prevline()
  self:linestart()
  self:left()
  self:linestart()
end

function buf:left()
  self.cur = math.max(1, self.cur - 1)
end

function buf:right()
  self.cur = math.min(self.cur + 1, #self.text + 1)
end

function buf:set(text)
  if type(text) == 'string' then
    self.text = utf.chars(text)
  else
    self.text = text
  end
  self:resetsel()
  self.cur = math.min(#self.text + 1, self.cur)
end

function buf:append(text)
  local u = utf.chars(text)
  for i = 1, #u do
    table.insert(self.text, u[i])
  end
  self.cur = #self.text + 1
end

local sel_delim = {
  [" "] = true, [","] = true, ["."] = true,
  [";"] = true, ["!"] = true, ["("] = true,
  ["{"] = true, ["<"] = true, ["["] = true,
  [")"] = true, ["}"] = true, [">"] = true,
  ["]"] = true, ["*"] = true, ["+"] = true,
  ["-"] = true, ["/"] = true, ["="] = true,
  ["\t"] = true, ["\n"] = true, [":"] = true,
}

local left_delim = {
  ["("] = ")", ["{"] = "}",
  ["["] = "]", ["<"] = ">",
  ['"'] = '"', ["'"] = "'",
}

local right_delim = {
  [")"] = "(", ["}"] = "{",
  ["]"] = "[", [">"] = "<",
  ['"'] = '"', ["'"] = "'",
}

function buf:selpar(delim)
  delim = delim or sel_delim

  local ind

  local function ind_match(c, a, b)
    if a == b then
      return c == a
    end
    if c == a then ind = ind + 1
    elseif c == b then ind = ind - 1 end
    return ind == 0
  end

  local function ind_scan(c, delims, pos, dir)
    if not c or not delims[c] then
      return
    end
    ind = 1
    local e = dir == 1 and #self.text or 1
    for i = pos, e, dir do
      if ind_match(self.text[i], c, delims[c]) then
        if dir == 1 then
          self:setsel(pos, i)
        else
          self:setsel(i + 1, pos + 1)
        end
        return true
      end
    end
  end

  if ind_scan(self.text[self.cur-1], left_delim, self.cur, 1) or
    ind_scan(self.text[self.cur], right_delim, self.cur - 1, -1) then
    return
  end

  if self.text[self.cur] == '\n' then -- whole line
    self:sel_line()
    return
  end

  local left, right = 1, #self.text + 1

  for i = self.cur - 1, 1, -1 do
    if delim[self.text[i]] then
      left = i + 1
      break
    end
  end

  for i = self.cur, #self.text, 1 do
    if delim[self.text[i]] then
      right = i
      break
    end
  end

  self:setsel(left, right)
end

function buf:hash()
  local hval = 0x811c9dc5
  for i=1, #self.text do
    hval = bit.band((hval * 0x01000193), 0xffffffff)
    hval = bit.bxor(hval, utf.codepoint(self.text[i]))
  end
  return hval
end

function buf:dirty(fl)
  if fl == nil then -- fast path
    return #self.text ~= self.written_len or
      self:hash() ~= self.written
  end

  local hash = self:hash()
  local last = self.written

  if fl == false then
     self.written = hash
     self.written_len = #self.text
  elseif fl == true then
     self.written = false
     self.written_len = false
  end
  return hash ~= last
end

function buf:save(fname)
  self.fname = fname or self.fname
  local f, e = io.open(self.fname, "wb")
  if not f then
    return f, e
  end
  f:write(self:gettext())
  f:close()
  self:dirty(false)
  return true
end

function buf:load(fname)
  local f, e = io.open(fname, "rb")
  if not f then
    return f, e
  end
  self.fname = fname
  self.text = {}
  for l in f:lines() do
    local u = utf.chars(l)
    for i = 1, #u do
      table.insert(self.text, u[i])
    end
    table.insert(self.text, "\n")
  end
  self:dirty(false)
  f:close()
  return true
end

function buf:loadornew(fname)
  if not self:load(fname) then
    self.fname = fname
    self:dirty(false)
    return false
  end
  return true
end

function buf:line_nr()
  local line = 1
  for i = 1, #self.text do
    if i >= self.cur then return line end
    if self.text[i] == '\n' then line = line + 1 end
  end
  return line
end

function buf:toline(nr)
  local line = 0
  local found
  self.cur = 1
  for i = 1, #self.text do
    if line >= nr then found = true break end
    self.cur = i
    if self.text[i] == '\n' then line = line + 1 end
  end
  self:linestart()
  return found
end

function buf:isfile()
  return self.fname and not self.fname:endswith '/' and not
    self.fname:startswith '+'
end

return buf
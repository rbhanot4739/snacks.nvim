---@class snacks.picker.util
local M = {}

local uv = vim.uv or vim.loop

---@param item snacks.picker.Item
---@return string?
function M.path(item)
  if not (item and item.file) then
    return
  end
  item._path = item._path
    or vim.fs.normalize(item.cwd and item.cwd .. "/" .. item.file or item.file, { _fast = true, expand_env = false })
  return item._path
end

---@param path string
---@param len? number
---@param opts? {cwd?: string}
function M.truncpath(path, len, opts)
  local cwd = vim.fs.normalize(opts and opts.cwd or vim.fn.getcwd(), { _fast = true, expand_env = false })
  local home = vim.fs.normalize("~")
  path = vim.fs.normalize(path, { _fast = true, expand_env = false })

  if path:find(cwd .. "/", 1, true) == 1 and #path > #cwd then
    path = path:sub(#cwd + 2)
  else
    local root = Snacks.git.get_root(path)
    if root and root ~= "" and path:find(root, 1, true) == 1 then
      local tail = vim.fn.fnamemodify(root, ":t")
      path = "⋮" .. tail .. "/" .. path:sub(#root + 2)
    elseif path:find(home, 1, true) == 1 then
      path = "~" .. path:sub(#home + 1)
    end
  end
  path = path:gsub("/$", "")

  if vim.api.nvim_strwidth(path) <= len then
    return path
  end

  local parts = vim.split(path, "/")
  if #parts < 2 then
    return path
  end
  local ret = table.remove(parts)
  local first = table.remove(parts, 1)
  if first == "~" and #parts > 0 then
    first = "~/" .. table.remove(parts, 1)
  end
  local width = vim.api.nvim_strwidth(ret) + vim.api.nvim_strwidth(first) + 3
  while width < len and #parts > 0 do
    local part = table.remove(parts) .. "/"
    local w = vim.api.nvim_strwidth(part)
    if width + w > len then
      break
    end
    ret = part .. ret
    width = width + w
  end
  return first .. "/…/" .. ret
end

---@param cmd string|string[]
---@param cb fun(output: string[], code: number)
---@param opts? {env?: table<string, string>, cwd?: string}
function M.cmd(cmd, cb, opts)
  local output = {} ---@type string[]
  local id = vim.fn.jobstart(
    cmd,
    vim.tbl_extend("force", opts or {}, {
      on_stdout = function(_, data)
        output[#output + 1] = table.concat(data, "\n")
      end,
      on_exit = function(_, code)
        cb(output, code)
        if code ~= 0 then
          Snacks.notify.error(
            ("Terminal **cmd** `%s` failed with code `%d`:\n- `vim.o.shell = %q`\n\nOutput:\n%s"):format(
              cmd,
              code,
              vim.o.shell,
              vim.trim(table.concat(output, ""))
            )
          )
        end
      end,
    })
  )
  if id <= 0 then
    Snacks.notify.error(("Failed to start job `%s`"):format(cmd))
  end
  return id > 0 and id or nil
end

---@param item table<string, any>
---@param keys string[]
function M.text(item, keys)
  local buffer = require("string.buffer").new()
  for _, key in ipairs(keys) do
    if item[key] then
      if #buffer > 0 then
        buffer:put(" ")
      end
      if key == "pos" or key == "end_pos" then
        buffer:putf("%d:%d", item[key][1], item[key][2])
      else
        buffer:put(tostring(item[key]))
      end
    end
  end
  return buffer:get()
end

---@param text? string
---@param width number
---@param opts? {align?: "left" | "right" | "center", truncate?: boolean}
function M.align(text, width, opts)
  text = text or ""
  opts = opts or {}
  opts.align = opts.align or "left"
  local tw = vim.api.nvim_strwidth(text)
  if tw > width then
    return opts.truncate and (vim.fn.strcharpart(text, 0, width - 1) .. "…") or text
  end
  local left = math.floor((width - tw) / 2)
  local right = width - tw - left
  if opts.align == "left" then
    left, right = 0, width - tw
  elseif opts.align == "right" then
    left, right = width - tw, 0
  end
  return (" "):rep(left) .. text .. (" "):rep(right)
end

---@param text string
---@param width number
function M.truncate(text, width)
  if vim.api.nvim_strwidth(text) > width then
    return vim.fn.strcharpart(text, 0, width - 1) .. "…"
  end
  return text
end

-- Stops visual mode and returns the selected text
function M.visual()
  local modes = { "v", "V", Snacks.util.keycode("<C-v>") }
  local mode = vim.fn.mode():sub(1, 1) ---@type string
  if not vim.tbl_contains(modes, mode) then
    return
  end
  -- stop visual mode
  vim.cmd("normal! " .. mode)

  local pos = vim.api.nvim_buf_get_mark(0, "<")
  local end_pos = vim.api.nvim_buf_get_mark(0, ">")

  -- for some reason, sometimes the column is off by one
  -- see: https://github.com/folke/snacks.nvim/issues/190
  local col_to = math.min(end_pos[2] + 1, #vim.api.nvim_buf_get_lines(0, end_pos[1] - 1, end_pos[1], false)[1])

  local lines = vim.api.nvim_buf_get_text(0, pos[1] - 1, pos[2], end_pos[1] - 1, col_to, {})
  local text = table.concat(lines, "\n")
  ---@class snacks.picker.Visual
  local ret = {
    pos = pos,
    end_pos = end_pos,
    text = text,
  }
  return ret
end

---@param str string
---@param data table<string, string>
function M.tpl(str, data)
  return (
    str:gsub(
      "(%b{})",
      ---@param w string
      function(w)
        local inner = w:sub(2, -2)
        local key, default = inner:match("^(.-):(.*)$")
        local ret = data[key or inner]
        if ret == "" and default then
          return default
        end
        return ret or w
      end
    )
  )
end

---@param str string
function M.title(str)
  return table.concat(
    vim.tbl_map(function(s)
      return s:sub(1, 1):upper() .. s:sub(2)
    end, vim.split(str, "_")),
    " "
  )
end

function M.rtp()
  local ret = {} ---@type string[]
  vim.list_extend(ret, vim.api.nvim_get_runtime_file("", true))
  if package.loaded.lazy then
    local extra = require("lazy.core.util").get_unloaded_rtp("")
    vim.list_extend(ret, extra)
  end
  return ret
end

---@param str string
---@return string text, string[] args
function M.parse(str)
  -- Format: this is a test -- -g=hello
  local t, a = str:match("^(.-)%s+%-%-%s*(.*)$")
  if not t then
    return str, {}
  end
  t, a = vim.trim(t), vim.trim(a:gsub("%s+", " "))
  local args = {} ---@type string[]
  -- tokenize the args, keeping quoted strings together
  local in_quote = nil ---@type string?
  local c = 1
  for i = 1, #a do
    local char = a:sub(i, i)
    if char == "'" or char == '"' then
      if in_quote == char then
        in_quote = nil
      else
        in_quote = char
      end
    elseif char == " " and not in_quote then
      args[#args + 1] = a:sub(c, i - 1)
      c = i + 1
    end
  end
  if c <= #a then
    args[#args + 1] = a:sub(c)
  end
  return t, args
end

--- Resolves the item if it has a resolve function
---@param item snacks.picker.Item?
function M.resolve(item)
  if item and item.resolve then
    item.resolve(item)
    item.resolve = nil
  end
  return item
end

--- Reads the lines of a file.
--- This is about 8x faster than `vim.fn.readfile`
--- and 3x faster than `io.lines` using a
--- test files of 225KB and 8300 lines.
---@param file string
function M.lines(file)
  local fd = uv.fs_open(file, "r", 438)
  if not fd then
    return {}
  end
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  uv.fs_close(fd)

  local lines, from = {}, 1 --- @type string[], number
  while from <= #data do
    local nl = data:find("\n", from, true)
    if nl then
      local cr = data:byte(nl - 1, nl - 1) == 13 -- \r
      local line = data:sub(from, nl - (cr and 2 or 1))
      lines[#lines + 1] = line
      from = nl + 1
    else
      lines[#lines + 1] = data:sub(from)
      break
    end
  end
  return lines
end

---@param s string
---@param index number
---@param encoding string
function M.str_byteindex(s, index, encoding)
  if vim.lsp.util._str_byteindex_enc then
    return vim.lsp.util._str_byteindex_enc(s, index, encoding)
  elseif vim._str_byteindex then
    return vim._str_byteindex(s, index, encoding == "utf-16")
  end
  return vim.str_byteindex(s, index, encoding == "utf-16")
end

--- Resolves the location of an item to byte positions
---@param item snacks.picker.Item
---@param buf? number
function M.resolve_loc(item, buf)
  if not item or not item.loc or item.loc.resolved then
    return item
  end

  local lines = {} ---@type string[]
  if item.buf and vim.api.nvim_buf_is_loaded(item.buf) then
    -- valid and loaded buffer
    lines = vim.api.nvim_buf_get_lines(item.buf, 0, -1, false)
  elseif item.buf and vim.uri_from_bufnr(item.buf):sub(1, 4) ~= "file" then
    -- item buffer with a custom uri
    vim.fn.bufload(item.buf)
    lines = vim.api.nvim_buf_get_lines(item.buf, 0, -1, false)
  elseif buf and vim.api.nvim_buf_is_valid(buf) then
    -- custom buffer (typically for preview)
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  elseif item.file then
    -- last resort, read the file
    lines = M.lines(item.file)
  end

  ---@param pos lsp.Position?
  local function resolve(pos)
    if not pos then
      return
    end
    local line = lines[pos.line + 1]
    local col = line and M.str_byteindex(line, pos.character, item.loc.encoding) or pos.character
    return { pos.line + 1, col }
  end
  item.pos = resolve(item.loc.range["start"])
  item.end_pos = resolve(item.loc.range["end"]) or item.end_pos
  item.loc.resolved = true
  return item
end

--- Returns the relative time from a given time
--- as ... ago
---@param time number in seconds
function M.reltime(time)
  local delta = os.time() - time
  local tpl = {
    { 1, 60, "just now", "just now" },
    { 60, 3600, "a minute ago", "%d minutes ago" },
    { 3600, 3600 * 24, "an hour ago", "%d hours ago" },
    { 3600 * 24, 3600 * 24 * 7, "yesterday", "%d days ago" },
    { 3600 * 24 * 7, 3600 * 24 * 7 * 4, "a week ago", "%d weeks ago" },
  }
  for _, v in ipairs(tpl) do
    if delta < v[2] then
      local value = math.floor(delta / v[1] + 0.5)
      return value == 1 and v[3] or v[4]:format(value)
    end
  end
  return os.date("%b %d, %Y", time) ---@type string
end

---@generic T: table
---@param t T
---@return T
function M.shallow_copy(t)
  local ret = {}
  for k, v in pairs(t) do
    ret[k] = v
  end
  return setmetatable(ret, getmetatable(t))
end

---@param opts? {main?: number, float?:boolean, filter?: fun(win:number, buf:number):boolean?}
function M.pick_win(opts)
  opts = Snacks.config.merge({
    filter = function(win, buf)
      return not vim.bo[buf].filetype:find("^snacks")
    end,
  }, opts)

  local overlays = {} ---@type snacks.win[]
  local chars = "asdfghjkl"
  local wins = {} ---@type number[]
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local keep = (opts.float or vim.api.nvim_win_get_config(win).relative == "")
      and (not opts.filter or opts.filter(win, buf))
    if keep then
      wins[#wins + 1] = win
    end
  end
  if #wins == 1 then
    return wins[1]
  elseif #wins == 0 then
    return
  end
  for _, win in ipairs(wins) do
    local c = chars:sub(1, 1)
    chars = chars:sub(2)
    overlays[c] = Snacks.win({
      backdrop = false,
      win = win,
      focusable = false,
      enter = false,
      relative = "win",
      width = 7,
      height = 3,
      text = ("       \n   %s   \n       "):format(c),
      wo = {
        winhighlight = "NormalFloat:SnacksPickerPickWin" .. (win == opts.main and "Current" or ""),
      },
    })
  end
  vim.cmd([[redraw!]])
  local char = vim.fn.getcharstr()
  for _, overlay in pairs(overlays) do
    overlay:close()
  end
  local win = (char == Snacks.util.keycode("<cr>")) or overlays[char]
  if win and type(win) == "table" then
    return win.opts.win
  elseif win then
    return opts.main
  end
end

---@param path string
---@param cwd? string
---@return fun(): string?
function M.parents(path, cwd)
  cwd = cwd or uv.cwd()
  if not (cwd and path:sub(1, #cwd) == cwd and #path > #cwd) then
    return function() end
  end
  local to = #cwd + 1 ---@type number?
  return function()
    to = path:find("/", to + 1, true)
    return to and path:sub(1, to - 1) or nil
  end
end

--- Checks if the path is a directory,
--- if not it returns the parent directory
---@param item string|snacks.picker.Item
function M.dir(item)
  local path = type(item) == "table" and M.path(item) or item
  ---@cast path string
  path = vim.fs.normalize(path)
  return vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
end

---@param paths string[]
---@param dir string
function M.copy(paths, dir)
  dir = vim.fs.normalize(dir)
  paths = vim.tbl_map(vim.fs.normalize, paths) ---@type string[]
  for _, path in ipairs(paths) do
    local name = vim.fn.fnamemodify(path, ":t")
    local to = dir .. "/" .. name
    M.copy_path(path, to)
  end
end

---@param from string
---@param to string
function M.copy_path(from, to)
  if not uv.fs_stat(from) then
    Snacks.notify.error(("File `%s` does not exist"):format(from))
    return
  end
  if vim.fn.isdirectory(from) == 1 then
    M.copy_dir(from, to)
  else
    M.copy_file(from, to)
  end
end

---@param from string
---@param to string
function M.copy_file(from, to)
  if vim.fn.filereadable(from) == 0 then
    Snacks.notify.error(("File `%s` is not readable"):format(from))
    return
  end
  if uv.fs_stat(to) then
    Snacks.notify.error(("File `%s` already exists"):format(to))
    return
  end
  local dir = vim.fs.dirname(to)
  vim.fn.mkdir(dir, "p")
  local ok, err = uv.fs_copyfile(from, to, { excl = true, ficlone = true })
  if not ok then
    Snacks.notify.error(("Failed to copy file:\n - from: `%s`\n- to: `%s`\n%s"):format(from, to, err))
  end
end

---@param from string
---@param to string
function M.copy_dir(from, to)
  if vim.fn.isdirectory(from) == 0 then
    Snacks.notify.error(("Directory `%s` does not exist"):format(from))
    return
  end
  vim.fn.mkdir(to, "p")
  for fname in vim.fs.dir(from, { follow = false }) do
    local path = from .. "/" .. fname
    M.copy_path(path, to .. "/" .. fname)
  end
end

---@param buf number
---@return (vim.bo|vim.wo)?
function M.modeline(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, vim.o.modelines, false)
  vim.list_extend(lines, vim.api.nvim_buf_get_lines(buf, -vim.o.modelines, -1, false))
  for _, line in ipairs(lines) do
    local m, options = line:match("%S*%s+(%w+):%s*(.-)%s*$")
    if vim.tbl_contains({ "vi", "vim", "ex" }, m) and options then
      local set = vim.split(options, "[:%s]+")
      local ret = {} ---@type table<string, any>
      for _, v in ipairs(set) do
        if v ~= "" then
          local k, val = v:match("([^=]+)=(.+)")
          if k then
            ret[k] = tonumber(val) or val
          else
            ret[v:gsub("^no", "")] = v:find("^no") and false or true
          end
        end
      end
      return ret
    end
  end
end

return M

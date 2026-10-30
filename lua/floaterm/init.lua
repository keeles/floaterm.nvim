vim.keymap.set('t', '<esc><esc>', '<c-\\><c-n>')

local M = {}

M.state = {
  terms = {}, -- list of terminal buffer numbers
  current = 0, -- index into terms (0 = none yet)
  win = -1, -- the floating window, shared by all terminals
}

-- Drop buffers that no longer exist, keep `current` in range
local function prune()
  local s = M.state
  for i = #s.terms, 1, -1 do -- iterate backwards so table.remove is safe
    if not vim.api.nvim_buf_is_valid(s.terms[i]) then
      table.remove(s.terms, i)
    end
  end
  if #s.terms == 0 then
    s.current = 0
  else
    s.current = math.max(1, math.min(s.current, #s.terms))
  end
end

local function label()
  return (' term %d/%d '):format(M.state.current, #M.state.terms)
end

local function open_float(buf)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  return vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = label(),
  })
end

-- Show terms[index] in the float (opening the float if needed)
local function show(index)
  local s = M.state
  s.current = index
  local buf = s.terms[index]
  if vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_set_buf(s.win, buf)
    vim.api.nvim_win_set_config(s.win, { title = label() })
  else
    s.win = open_float(buf)
  end
  vim.cmd.startinsert()
end

function M.new()
  prune()
  local s = M.state
  table.insert(s.terms, vim.api.nvim_create_buf(false, true))
  show(#s.terms)
  vim.cmd.terminal()
  -- :terminal may hand back a different buffer, so store the real one
  s.terms[s.current] = vim.api.nvim_get_current_buf()
  vim.cmd.startinsert()
end

function M.toggle()
  prune()
  local s = M.state
  if vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_hide(s.win)
  elseif #s.terms == 0 then
    M.new()
  else
    show(s.current)
  end
end

-- dir = 1 for next, -1 for previous
function M.cycle(dir)
  prune()
  local n = #M.state.terms
  if n == 0 then
    return M.new()
  end
  show((M.state.current - 1 + dir) % n + 1)
end

-- move to terminal at given index
function M.select(index)
  prune()
  if index <= #M.state.terms then
    show(index)
  end
end

-- Open the current terminal in a regular split instead of the float
function M.split()
  prune()
  local s = M.state
  local buf = s.terms[s.current]
  if not buf then
    return
  end
  if vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_hide(s.win)
  end
  vim.cmd.split()
  vim.api.nvim_win_set_buf(0, buf)
end

vim.api.nvim_create_autocmd('TermClose', {
  group = vim.api.nvim_create_augroup('floaterm', { clear = true }),
  callback = function(ev)
    -- Defer: buffers can't always be deleted from inside TermClose
    vim.schedule(function()
      local s = M.state
      local was_visible = vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == ev.buf

      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.api.nvim_buf_delete(ev.buf, { force = true })
      end
      prune()

      -- If you were looking at the one that died, land on another
      if was_visible and #s.terms > 0 then
        show(s.current)
      end
    end)
  end,
})

return M

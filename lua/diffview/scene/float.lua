local oop = require("diffview.oop")

local api = vim.api

local M = {}

---Geometry and lifetime of the floating windows a view is drawn in.
---@class FloatFrame : diffview.Object
---@field opt table
---@field backdrop_win integer?
---@field augroup integer?
---@field panel_visible fun(): boolean Whether the file panel takes up space.
---@field relayout fun() Called when the geometry changed.
local FloatFrame = oop.create_class("FloatFrame")

---@param opt table The `view.float` config.
function FloatFrame:init(opt)
  self.opt = opt
  self.panel_visible = function() return true end
  self.relayout = function() end
end

---@private
---@return integer
function FloatFrame:border_size()
  local border = self.opt.border
  if border == nil or border == "none" then return 0 end
  return 2
end

---@private
---@return { row: integer, col: integer, width: integer, height: integer } # Outer bounds.
function FloatFrame:bounds()
  local ui_w = vim.o.columns
  local ui_h = vim.o.lines - vim.o.cmdheight

  local function dim(v, total)
    if v <= 1 then return math.max(1, math.floor(total * v)) end
    return math.min(math.floor(v), total)
  end

  local w, h = dim(self.opt.width, ui_w), dim(self.opt.height, ui_h)

  return {
    row = math.floor((ui_h - h) / 2),
    col = math.floor((ui_w - w) / 2),
    width = w,
    height = h,
  }
end

---@private
---@param row integer
---@param col integer
---@param width integer Outer width.
---@param height integer Outer height.
function FloatFrame:float_config(row, col, width, height)
  local bs = self:border_size()

  return {
    relative = "editor",
    row = row,
    col = col,
    width = math.max(1, width - bs),
    height = math.max(1, height - bs),
    border = self.opt.border,
    zindex = self.opt.zindex,
  }
end

---@private
---@return integer
function FloatFrame:panel_outer_width()
  return self.opt.panel_width + self:border_size()
end

---@return table # Float config of the file panel.
function FloatFrame:panel_config()
  local b = self:bounds()
  local conf = self:float_config(b.row, b.col, self:panel_outer_width(), b.height)
  conf.type = "float"
  return conf
end

---Split the frame into `n` equally wide columns, right of the file panel.
---@param n integer
---@return table[] # One `nvim_open_win()` config per column.
function FloatFrame:window_configs(n)
  local b = self:bounds()
  local offset = self.panel_visible() and self:panel_outer_width() or 0
  local avail = b.width - offset
  local col_w = math.floor(avail / n)
  local ret = {}

  for i = 1, n do
    local w = i == n and (avail - col_w * (n - 1)) or col_w
    ret[i] = self:float_config(b.row, b.col + offset + col_w * (i - 1), w, b.height)
  end

  return ret
end

function FloatFrame:is_open()
  return self.augroup ~= nil
end

function FloatFrame:open()
  if self:is_open() then return end

  self.augroup = api.nvim_create_augroup("diffview_float_" .. tostring(vim.uv.hrtime()), {})

  api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      self:update_backdrop()
      self.relayout()
    end,
  })

  if self.opt.backdrop then
    api.nvim_set_hl(0, "DiffviewFloatBackdrop", { bg = "#000000", default = true })

    local bufnr = api.nvim_create_buf(false, true)
    vim.bo[bufnr].bufhidden = "wipe"
    self.backdrop_win = api.nvim_open_win(bufnr, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = vim.o.columns,
      height = vim.o.lines,
      style = "minimal",
      focusable = false,
      zindex = math.max(1, self.opt.zindex - 1),
    })
    vim.wo[self.backdrop_win].winblend = self.opt.backdrop_blend
    vim.wo[self.backdrop_win].winhighlight = "Normal:DiffviewFloatBackdrop"
  end
end

---@private
function FloatFrame:update_backdrop()
  if self.backdrop_win and api.nvim_win_is_valid(self.backdrop_win) then
    api.nvim_win_set_config(self.backdrop_win, {
      relative = "editor",
      row = 0,
      col = 0,
      width = vim.o.columns,
      height = vim.o.lines,
    })
  end
end

function FloatFrame:close()
  if self.backdrop_win and api.nvim_win_is_valid(self.backdrop_win) then
    api.nvim_win_close(self.backdrop_win, true)
  end

  if self.augroup then
    pcall(api.nvim_del_augroup_by_id, self.augroup)
  end

  self.backdrop_win = nil
  self.augroup = nil
end

M.FloatFrame = FloatFrame
return M

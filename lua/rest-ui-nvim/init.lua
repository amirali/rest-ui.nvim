local uv = vim.uv or vim.loop

local side_buf, side_win
local file_buf, file_win

local collections = {}

local base_lines = {'RestUI', '-- ? for help --'}

local mappings = {
  ['<cr>'] = 'open_file()',
  q = 'close_window()',
  i = 'add_new_file()',
  z = 'expand_collapse_collection()',
  ['?'] = 'show_hide_help()',
  a = 'add_collection()',
}

local show_help = false
local help_lines = {}
for k,v in pairs(mappings) do
  table.insert(help_lines, " *" .. k .. ": " .. v)
end
table.insert(help_lines, "")

local rest_ui_directory = vim.fn.stdpath('data') .. '/rest-ui/'

-- NOTE: Lua, WTF man? no octal what so ever?
local octal_0755 = 493

local function get_parsable_collection(collection)
  collection.expanded = nil
  return collection
end

local function read_collections()
  collections = {}

  local fs, err = uv.fs_scandir(rest_ui_directory)
  if err ~= nil then
    return
  end

  if not fs then
    return
  end

  while true do
    local filename, _ = uv.fs_scandir_next(fs)

    if filename == nil then
      break
    end

    if not string.find(filename, "^.+%.json$") then
      goto continue
    end

    local file = io.open(rest_ui_directory .. filename, "r")

    if not file then break end

    local json_content = file:read("*a")

    local collection = vim.json.decode(json_content)
    table.insert(collections, collection)

    file:close()

    ::continue::
  end
end

local function center(str)
  local width = vim.api.nvim_win_get_width(side_win)
  local shift = math.floor(width / 2) - math.floor(string.len(str) / 2)
  return string.rep(' ', shift) .. str
end

local function open_collections()
  vim.api.nvim_buf_set_option(side_buf, 'modifiable', true)

  for _, collection in ipairs(collections) do
    vim.api.nvim_buf_set_lines(side_buf, -1, -1, false, { collection.name .. ' -' })
  end

  vim.api.nvim_buf_set_option(side_buf, 'modifiable', false)
end

local function write_lines_to_buf(buf, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

local function draw_side_panel()
  local base_lines_mutated = {}
  for _, line in ipairs(base_lines) do
    table.insert(base_lines_mutated, center(line))
  end
  write_lines_to_buf(side_buf, base_lines_mutated)

  read_collections()
  open_collections()
end


local function add_collection()
  local collection_name = vim.fn.input("collection name: ")
  local collection = {}
  collection.name = collection_name
  collection.files = {}
  local collection_json = vim.json.encode(collection)
  local file = io.open(rest_ui_directory .. collection_name .. '.json', 'w')
  if not file then return end
  file:write(collection_json)
  file:close()

  draw_side_panel()
end

local function open_window()
  vim.cmd.tabnew()

  file_buf = vim.api.nvim_get_current_buf()
  file_win = vim.api.nvim_get_current_win()


  vim.cmd("lefta 50vnew")
  side_buf = vim.api.nvim_get_current_buf()
  side_win = vim.api.nvim_get_current_win()


  vim.api.nvim_buf_set_option(side_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(side_buf, 'filetype', 'help')
  vim.api.nvim_win_set_option(side_win, 'number', false)
  vim.api.nvim_win_set_option(side_win, 'relativenumber', false)

  draw_side_panel()

  return side_buf
end

local function find_collection_by_name(name)
  local selected_collection = nil

  for _, collection in ipairs(collections) do
    if collection.name == name then
      selected_collection = collection
    end
  end

  return selected_collection
end

local function get_collection_by_name(collection_name)
  for _, collection in ipairs(collections) do
    if collection.name == collection_name then
      return collection
    end
  end

  return nil
end

---@diagnostic disable-next-line: unused-function
local function get_collection_of_file()
  local line_number, _ = unpack(vim.api.nvim_win_get_cursor(side_win))
  local lines = vim.api.nvim_buf_get_lines(side_buf, 0, vim.api.nvim_buf_line_count(side_buf), false)

  local collection_name = nil
  for i = line_number, 1, -1 do
    if string.find(lines[i], "^(%S+).+$") then
      collection_name = lines[i]
      break
    end
  end

  if not collection_name then
    return nil
  end

  return get_collection_by_name(collection_name:gsub(" %-", ""):gsub(" %+", ""))
end

---@diagnostic disable-next-line: unused-local, unused-function
local function close_window()
  vim.api.nvim_win_close(side_win, true)
end

---@diagnostic disable-next-line: unused-local, unused-function
local function add_new_file()
  local collection = get_collection_of_file()
  if not collection then
    local collection_name = vim.fn.input("collection: ")
    collection = get_collection_by_name(collection_name)
  end

  if not collection then
    return
  end

  local filename = vim.fn.input("filename: ")

  if not filename then
    return
  end

  local _, err = uv.fs_statfs(rest_ui_directory .. collection.name)
  if err ~= nil then
    uv.fs_mkdir(rest_ui_directory .. collection.name, octal_0755)
  end

  local file_table = {
    name = filename,
    path = rest_ui_directory .. collection.name .. '/' .. filename .. '.http'
  }
  table.insert(collection.files, file_table)

  local collection_json = vim.json.encode(get_parsable_collection(collection))

  local collection_file = io.open(rest_ui_directory .. collection.name .. '.json', "w")
  if not collection_file then
    return
  end

  collection_file:write(collection_json)
  collection_file:close()

  vim.api.nvim_win_call(file_win, function()
    vim.cmd.edit(file_table.path)
    vim.cmd.write()
  end)

  vim.api.nvim_set_current_win(file_win)
  draw_side_panel()
end

local function expand_collection(selected_collection)
  local line_number, _ = unpack(vim.api.nvim_win_get_cursor(side_win))
  local lines = vim.api.nvim_buf_get_lines(side_buf, 0, vim.api.nvim_buf_line_count(side_buf), false)

  lines[line_number] = lines[line_number]:gsub(" %-", " %+")

  local index = 1
  for _, file in ipairs(selected_collection.files) do
    table.insert(lines, line_number + index, '  - ' .. file.name)
    index = index + 1
  end

  vim.api.nvim_buf_set_option(side_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(side_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(side_buf, 'modifiable', false)

  selected_collection.expanded = true
end

local function collapse_collection(selected_collection)
  local line_number, _ = unpack(vim.api.nvim_win_get_cursor(side_win))
  local lines = vim.api.nvim_buf_get_lines(side_buf, 0, vim.api.nvim_buf_line_count(side_buf), false)

  lines[line_number] = lines[line_number]:gsub(" %+", " %-")

  for i = #selected_collection.files, 1, -1 do
    table.remove(lines, line_number + i)
  end

  vim.api.nvim_buf_set_option(side_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(side_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(side_buf, 'modifiable', false)

  selected_collection.expanded = false
end

---@diagnostic disable-next-line: unused-local, unused-function
local function expand_collapse_collection()
  local collection_name = vim.api.nvim_get_current_line()
  local pure_collection_name = collection_name:gsub(" %-", ""):gsub(" %+", "")

  local selected_collection = find_collection_by_name(pure_collection_name)

  if selected_collection == nil then
    print("'" .. pure_collection_name .. "' is not a collection")
    return
  end

  if selected_collection.expanded == true then
    collapse_collection(selected_collection)
  else
    expand_collection(selected_collection)
  end
end

---@diagnostic disable-next-line: unused-function
local function get_filepath(collection, filename)
  local filepath = nil
  for _, file in ipairs(collection.files) do
    if file.name == filename then
      filepath = file.path
      break
    end
  end

  return filepath
end

---@diagnostic disable-next-line: unused-local, unused-function
local function open_file()
  local filename = vim.api.nvim_get_current_line()
  local pure_filename = filename:gsub("^  %- ", "")
  if pure_filename == filename then
    print("'" .. filename .. "' is not a file")
    return
  end

  local collection = get_collection_of_file()
  if not collection then
    error "no collection"
    return
  end

  local filepath = get_filepath(collection, pure_filename)
  if not filepath then
    error "no filepath"
    return
  end

  vim.api.nvim_set_current_win(file_win)
  vim.cmd.edit(filepath)
end

---@diagnostic disable-next-line: unused-local, unused-function
local function show_hide_help()
  local lines = vim.api.nvim_buf_get_lines(side_buf, 0, vim.api.nvim_buf_line_count(side_buf), false)

  if not show_help then
    for i, line in ipairs(help_lines) do
      table.insert(lines, #base_lines + i, line)
    end
    show_help = true
  else
    for i = #help_lines, 1, -1 do
      table.remove(lines, #base_lines + i)
    end
    show_help = false
  end

  vim.api.nvim_buf_set_option(side_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(side_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(side_buf, 'modifiable', false)
end

local function set_mappings()
  for k,v in pairs(mappings) do
    vim.api.nvim_buf_set_keymap(side_buf, 'n', k, ':lua require"rest-ui-nvim".' .. v ..'<cr>', {
        nowait = true, noremap = true, silent = true
      })
  end
  local other_chars = {
    'b', 'c', 'd', 'e', 'f', 'g', 'n', 'o', 'p', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
  }
  for _,v in ipairs(other_chars) do
    vim.api.nvim_buf_set_keymap(side_buf, 'n', v, 'echo "undifiend"<cr>', { nowait = true, noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(side_buf, 'n', v:upper(), 'echo "undifiend"<cr>', { nowait = true, noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(side_buf, 'n',  '<c-'..v..'>', 'echo "undifiend"<cr>', { nowait = true, noremap = true, silent = true })
  end
end


local function setup()
  local _, err = uv.fs_statfs(rest_ui_directory)
  if err ~= nil then
    uv.fs_mkdir(rest_ui_directory, octal_0755)
  end

  vim.api.nvim_create_user_command("RestUI", function()
    open_window()
    set_mappings()
    vim.cmd('buffer ' .. side_buf)
  end, {})
  read_collections()
end

return {
  setup = setup,
  open_window = open_window,
  add_new_file = add_new_file,
  close_window = close_window,
  open_collections = open_collections,
  expand_collapse_collection = expand_collapse_collection,
  open_file = open_file,
  show_hide_help = show_hide_help,
  add_collection = add_collection,
  collections = collections,
}

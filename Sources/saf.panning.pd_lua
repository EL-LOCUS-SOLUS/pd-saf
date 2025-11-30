local panning = pd.Class:new():register("saf.panning")

-- ─────────────────────────────────────
function panning:initialize(_, args)
	self.inlets = 1
	self.outlets = 2
	self.repaint_sources = false
	self.selected = false
	self.plan_size = 200
	self.fig_size = 200
	self.sources_size = 3
	self.margin = 5
	self.yzview = false
	self.nspeakers = 4

	-- Define colors with appropriate RGB values
	self.colors = {
		background1 = { 19, 47, 80 },
		background2 = { 27, 55, 87 },
		speakers = { 255, 255, 0 },
		lines = { 46, 73, 102 },
		text = { 127, 145, 162 },
		sources = { 255, 0, 0 },
		source_text = { 230, 230, 240 },
	}

	for i, arg in ipairs(args) do
		if arg == "-size" then
			self.plan_size = type(args[i + 1]) == "number" and args[i + 1] or 200
			self.fig_size = self.plan_size
		elseif arg == "-nsources" then
			self.sources_size = type(args[i + 1]) == "number" and args[i + 1] or 5
		elseif arg == "-yzview" then
			local xzview = type(args[i + 1]) == "number" and args[i + 1] or 0
			if xzview == 1 then
				self.yzview = true
			end
		elseif arg == "-nspeakers" then
			self.nspeakers = args[i + 1]
		end
	end

	self.speakers_pos = {}
	for i = 0, self.nspeakers - 1 do
		local azi = 360 / self.nspeakers * i
		self.speakers_pos[i + 1] = {}
		self.speakers_pos[i + 1].azi = azi
		self.speakers_pos[i + 1].ele = 0
	end

	self.sources = {}
	self:set_size(self.fig_size, self.plan_size)

	for i = 1, self.sources_size do
		self.sources[i] = self:create_newsource(i)
	end

	return true
end

-- ─────────────────────────────────────
function panning:create_newsource(i)
	local center_x, center_y = self:get_size() / 2, self:get_size() / 2
	local margin = self.margin
	local max_radius = (self.plan_size / 2) - margin
	local angle_step = (math.pi * 2) / self.sources_size
	local angle = (i - 1) * angle_step
	local distance = max_radius * 0.9

	-- Start with positions at 0,0 elevation
	local azi_deg = math.deg(angle)
	local ele_deg = 0

	-- Convert to Cartesian coordinates using VST coordinate system
	local x, y, z = self:spherical_to_cartesian(azi_deg, ele_deg, distance)

	return {
		i = i,
		x = x,
		y = y,
		z = z,
		azi = azi_deg,
		ele = ele_deg,
		size = 8,
		color = self.colors.sources,
		fill = false,
		selected = false,
	}
end

-- ─────────────────────────────────────
-- Convert spherical (azi, ele) to Cartesian coordinates using VST coordinate system
-- azi: 0° = front, increasing counterclockwise (90° = left, -90° = right, ±180° = back)
-- ele: 0° = horizontal, +90° = top, -90° = bottom
function panning:spherical_to_cartesian(azi_deg, ele_deg, radius)
	local center = self.plan_size / 2
	local azi_rad = math.rad(azi_deg)
	local ele_rad = math.rad(ele_deg)

	-- VST coordinate system: flip X so +90° appears on left, -90° on right
	local x = -math.cos(ele_rad) * math.sin(azi_rad) * radius
	local y = -math.cos(ele_rad) * math.cos(azi_rad) * radius -- Y is depth (front/back)
	local z = math.sin(ele_rad) * radius -- Z is height

	-- Convert to screen coordinates
	x = x + center
	y = y + center
	z = z + center

	return x, y, z
end

-- ─────────────────────────────────────
-- Convert Cartesian coordinates to spherical using VST coordinate system
function panning:cartesian_to_spherical(x, y)
	local center = self.plan_size / 2
	local max_radius = center - self.margin

	-- Convert to centered coordinates
	local dx = x - center
	local dy = y - center

	-- Apply VST coordinate system: flip X axis
	dx = -dx

	-- Calculate azimuth and elevation
	local r = math.sqrt(dx * dx + dy * dy)
	local azi_rad = math.atan(dx, -dy) -- atan2(x, -y) for VST coordinate system
	local ele_rad = 0 -- Flat for XY view

	local azi_deg = math.deg(azi_rad)
	local ele_deg = math.deg(ele_rad)

	-- Normalize azimuth to -180° to 180°
	if azi_deg > 180 then
		azi_deg = azi_deg - 360
	end
	if azi_deg < -180 then
		azi_deg = azi_deg + 360
	end

	return azi_deg, ele_deg
end

-- ──────────────────────────────────────────
function panning:update_args()
	local args = {}
	table.insert(args, "-size")
	table.insert(args, self.plan_size)
	table.insert(args, "-nsources")
	table.insert(args, self.sources_size)
	if self.yzview == 1 then
		table.insert(args, "-yzview")
		table.insert(args, self.yzview)
	end
	table.insert(args, "-nspeakers")
	table.insert(args, self.nspeakers)
	self:set_args(args)
end

--╭─────────────────────────────────────╮
--│ METHODS │
--╰─────────────────────────────────────╯
function panning:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize("", {})
	self:repaint()
end

-- ─────────────────────────────────────
function panning:in_1_yzview(args)
	if args[1] == 1 then
		self.yzview = true
		self.fig_size = self.plan_size * 2
		self:set_size(self.fig_size, self.plan_size)
		self:update_args()
	else
		self.yzview = false
		self.fig_size = self.fig_size / 2
		self:set_size(self.plan_size, self.fig_size)
	end
end

-- ─────────────────────────────────────
function panning:in_1_numspeakers(args)
	local n = args[1]
	self.nspeakers = n
	self.speakers_pos = {}
	for i = 0, self.nspeakers - 1 do
		local azi = 360 / self.nspeakers * i
		self.speakers_pos[i + 1] = {}
		self.speakers_pos[i + 1].azi = azi
		self.speakers_pos[i + 1].ele = 0
		self:outlet(2, "speaker", { i + 1, azi, 0 })
	end
	self:repaint()
	self:update_args()
end

-- ─────────────────────────────────────
function panning:in_1_source(args)
	local index = args[1]
	local azi_deg = args[2]
	local ele_deg = args[3]
	local dis = 0.8
	if #args >= 4 then
		dis = args[4]
	end

	if index > self.sources_size then
		self.sources_size = index
		self:in_1_sources({ index })
	end

	self:outlet(1, "source", { index, azi_deg, ele_deg })

	-- Convert to Cartesian coordinates using VST system
	local max_radius = (self.plan_size / 2) - self.margin
	local x, y, z = self:spherical_to_cartesian(azi_deg, ele_deg, max_radius * dis)

	for _, source in pairs(self.sources) do
		if source.i == index then
			source.x = x
			source.y = y
			source.z = z
			source.azi = azi_deg
			source.ele = ele_deg
		end
	end

	self:update_args()
	self:repaint(2)
end

-- ─────────────────────────────────────
function panning:in_1_size(args)
	local old_size = self.plan_size
	self:set_size(args[1] * 2, args[1])
	self.plan_size = args[1]
	self.fig_size = self.plan_size * 2
	local relation = self.plan_size / old_size

	for _, source in pairs(self.sources) do
		source.x = source.x * relation
		source.y = source.y * relation
		source.z = source.z * relation
	end

	self:update_args()
	self:repaint()
end

-- ─────────────────────────────────────
function panning:in_1_sources(args)
	local num_circles = args[1]
	self.sources_size = args[1]
	self.sources = {}

	for i = 1, num_circles do
		self.sources[i] = self:create_newsource(i)
	end

	self:repaint(2)
	self:outlet(1, "num_sources", { args[1] })
end

--╭─────────────────────────────────────╮
--│ MOUSE │
--╰─────────────────────────────────────╯
function panning:mouse_drag(x, y)
	local size_x, size_y = self:get_size()

	-- Ignore drags outside the margin
	if x < 5 or x > (size_x - 5) or y < 5 or y > (size_y - 5) then
		return
	end

	for i, source in pairs(self.sources) do
		if source.selected then
			source.x = x
			source.y = y
			source.fill = true

			-- Convert screen position to spherical coordinates using VST system
			local azi_deg, ele_deg = self:cartesian_to_spherical(x, y)

			-- Update source coordinates
			source.azi = azi_deg
			source.ele = ele_deg

			self:outlet(1, "source", { i, azi_deg, ele_deg })
		else
			source.fill = false
		end
	end

	self:repaint(3)
end

-- ─────────────────────────────────────
function panning:mouse_down(x, y)
	local already_selected = false

	for i, source in pairs(self.sources) do
		local cx = source.x
		local cy = source.y
		local radius = source.size / 2
		local dx = x - cx
		local dy = y - cy

		if (dx * dx + dy * dy) <= (radius * radius) then
			self.sources[i].x = x
			self.sources[i].y = y
			self.sources[i].fill = true

			if not already_selected then
				self.sources[i].selected = true
				already_selected = true
			else
				self.sources[i].selected = false
			end
		else
			self.sources[i].fill = false
			self.sources[i].selected = false
		end
	end

	self:repaint(2)
	self:repaint(3)
end

-- ─────────────────────────────────────
function panning:mouse_up(_, _)
	for i, _ in pairs(self.sources) do
		self.sources[i].fill = false
		self.sources[i].selected = false
	end
	self:repaint(2)
	self:repaint(3)
end

--╭─────────────────────────────────────╮
--│ PAINT │
--╰─────────────────────────────────────╯
function panning:paint(g)
	local size_x, size_y = self.plan_size, self.plan_size
	if not self.colors then
		return
	end

	-- Use colors from self.colors
	g:set_color(table.unpack(self.colors.background1))
	g:fill_all()
	g:set_color(table.unpack(self.colors.background2))
	g:fill_ellipse(self.margin, self.margin, size_x - 2 * self.margin, size_y - 2 * self.margin)

	-- Lines
	g:set_color(table.unpack(self.colors.lines))
	local center = size_x / 2

	-- Adjusted vertical and horizontal lines
	g:draw_line(center, self.margin, center, size_y - self.margin, 1)
	g:draw_line(self.margin, center, size_x - self.margin, center, 1)

	-- Lines from center to border (radial lines)
	local base_radius = (math.min(size_x, size_y) / 2) - self.margin
	for angle = 0, 2 * math.pi, math.pi / 8 do
		local x_end = center + math.cos(angle) * base_radius
		local y_end = center + math.sin(angle) * base_radius
		g:draw_line(center, center, x_end, y_end, 1)
	end

	-- Ellipse 1
	local base_size = (math.min(size_x, size_y) / 2) - self.margin
	for i = 0, 3 do
		local scale = math.log(i + 1) / math.log(6)
		local radius_x = base_size * (1 - scale)
		local radius_y = base_size * (1 - scale)
		g:stroke_ellipse(center - radius_x, center - radius_y, radius_x * 2, radius_y * 2, 1)
	end

	-- Draw speakers
	for i = 1, self.nspeakers do
		local s = self.speakers_pos[i]
		local azi_deg = s.azi
		local ele_deg = s.ele
		local dis = s.dis or 1.0

		-- Convert to Cartesian using VST coordinate system
		local x, y, z = self:spherical_to_cartesian(azi_deg, ele_deg, (self.plan_size / 2) - self.margin)

		-- Draw the speaker
		local speaker_size = 6
		g:set_color(table.unpack(self.colors.speakers))
		g:fill_ellipse(x - speaker_size / 2, y - speaker_size / 2, speaker_size, speaker_size)

		-- Calculate text offset to appear "inside the circle"
		local offset = 4
		local text_x_offset = (x < self.plan_size / 2) and offset or -offset - 6
		local text_y_offset = (y < self.plan_size / 2) and offset or -offset - 6
		g:set_color(255, 255, 255)
		g:draw_text(tostring(i), x + text_x_offset, y + text_y_offset, 10, 3)
	end

	-- Text
	local text_x, text_y = 1, 1
	g:set_color(table.unpack(self.colors.text))
	g:draw_text("xy view", text_x, text_y, 50, 1)

	--╭─────────────────────────────────────╮
	--│ WORLD TWO │
	--╰─────────────────────────────────────╯
	if self.yzview then
		g:set_color(table.unpack(self.colors.background2))
		g:fill_ellipse(self.plan_size + self.margin, self.margin, size_x - 2 * self.margin, size_y - 2 * self.margin)

		g:set_color(table.unpack(self.colors.lines))
		local ellipse_x = self.plan_size + self.margin
		local ellipse_y = self.margin
		local ellipse_width = size_x - 2 * self.margin
		local ellipse_height = size_y - 2 * self.margin
		local center_x = ellipse_x + ellipse_width / 2
		local center_y = ellipse_y + ellipse_height / 2
		local radius = ellipse_width / 2

		-- Draw YZ grid lines
		local vertical_lines = 8
		for i = 1, vertical_lines do
			local y_line = center_y - radius + (i * (2 * radius / vertical_lines))
			local x_offset = math.sqrt(radius ^ 2 - (y_line - center_y) ^ 2)
			g:draw_line(center_x - x_offset, y_line, center_x + x_offset, y_line, 1)
		end

		-- Draw concentric circles
		for i = 3, 7 do
			local circle_width = math.log(i) * (self.plan_size - self.margin)
			g:stroke_ellipse(
				self.plan_size + self.margin + (circle_width / 2),
				self.margin,
				(size_x - 2 * self.margin) - circle_width,
				size_y - 2 * self.margin,
				1
			)
		end

		-- Text
		text_x, text_y = 2 + self.plan_size, 1
		g:set_color(table.unpack(self.colors.text))
		g:draw_text("yz view", text_x, text_y, 50, 1)
		g:draw_line(self.plan_size, 0, self.plan_size, self.plan_size, 1)

		-- Draw speakers in YZ view
		for i = 1, self.nspeakers do
			local s = self.speakers_pos[i]
			local azi_deg = s.azi
			local ele_deg = s.ele
			local dis = s.dis or 1.0

			-- Convert to YZ coordinates
			local max_radius = (self.plan_size / 2) - self.margin
			local azi_rad = math.rad(azi_deg)
			local ele_rad = math.rad(ele_deg)

			-- For YZ view: X becomes depth, Z becomes height
			local depth = math.cos(ele_rad) * math.cos(azi_rad) * max_radius * dis
			local height = math.sin(ele_rad) * max_radius * dis

			local x_pos = center_x + depth
			local z_pos = center_y + height -- FIXED: Remove inversion so +ele = top, -ele = bottom

			local speaker_size = 6
			g:set_color(table.unpack(self.colors.speakers))
			g:fill_ellipse(x_pos - speaker_size / 2, z_pos - speaker_size / 2, speaker_size, speaker_size)

			-- Text label
			local offset = 4
			local text_x_offset = (x_pos < center_x) and offset or -offset - 6
			local text_y_offset = (z_pos < center_y) and offset or -offset - 6
			g:set_color(255, 255, 255)
			g:draw_text(tostring(i), x_pos + text_x_offset, z_pos + text_y_offset, 10, 3)
		end
	end
end

-- ─────────────────────────────────────
function panning:paint_layer_2(g)
	for i, source in pairs(self.sources) do
		if not self.sources[i].selected then
			local x = source.x
			local y = source.y
			local z = source.z
			local size = source.size

			-- Draw source in XY view
			g:set_color(table.unpack(source.color))
			g:stroke_ellipse(x - (size / 2), y - (size / 2), size, size, 1)

			local scale_factor = 0.7
			g:scale(scale_factor, scale_factor)
			local text_x, text_y = x - (size / 3), y - (size / 3)
			g:set_color(table.unpack(self.colors.source_text))
			g:draw_text(tostring(i), (text_x + 1) / scale_factor, (text_y - 1) / scale_factor, 20, 3)
			g:reset_transform()

			-- Draw source in YZ view
			if self.yzview then
				g:set_color(table.unpack(source.color))
				local yz_x = source.x + self.plan_size -- Shift to right panel
				local yz_y = source.z -- Use Z coordinate for YZ view (no inversion)
				g:stroke_ellipse(yz_x - (size / 2), yz_y - (size / 2), size, size, 1)

				g:scale(scale_factor, scale_factor)
				text_x = yz_x - (size / 3)
				text_y = yz_y - (size / 3)
				g:set_color(table.unpack(self.colors.source_text))
				g:draw_text(tostring(i), (text_x + 1) / scale_factor, (text_y - 1) / scale_factor, 20, 3)
				g:reset_transform()
			end
		end
	end
end

-- ─────────────────────────────────────
function panning:paint_layer_3(g)
	for i, source in pairs(self.sources) do
		if self.sources[i].selected then
			local x = source.x - (source.size / 2)
			local y = source.y - (source.size / 2)
			local size = source.size

			-- Draw selected source in XY view
			g:set_color(table.unpack(source.color))
			g:fill_ellipse(x, y, size, size)
			g:stroke_ellipse(x, y, size, size, 1)

			-- Source index text
			local text_x, text_y = x - (size / 1.5), y - (size / 2)
			g:set_color(table.unpack(self.colors.source_text))
			g:draw_text(tostring(i), text_x, text_y, 10, 3)

			-- Coordinate text
			text_x, text_y = x + (size / 1), y + (size / 2)
			local scale_factor = 0.7
			g:scale(scale_factor, scale_factor)
			g:set_color(table.unpack(self.colors.source_text))
			g:draw_text(
				string.format("%.0f° %.0f°", source.azi, source.ele),
				text_x / scale_factor,
				text_y / scale_factor,
				40,
				1
			)
			g:reset_transform()

			-- Draw selected source in YZ view
			if self.yzview then
				local yz_x = (source.x - (source.size / 2)) + self.plan_size
				local yz_y = source.z - (source.size / 2) -- No inversion

				g:set_color(table.unpack(source.color))
				g:fill_ellipse(yz_x, yz_y, size, size)
				g:stroke_ellipse(yz_x, yz_y, size, size, 1)

				-- Draw the number
				local offset = 4
				local text_x_offset = (yz_x < self.plan_size * 1.5) and offset or -offset - 6
				local text_y_offset = (yz_y < self.plan_size / 2) and offset or -offset - 6
				g:set_color(255, 255, 255)
				g:draw_text(tostring(i), yz_x + text_x_offset, yz_y + text_y_offset, 10, 3)
			end
		end
	end
end

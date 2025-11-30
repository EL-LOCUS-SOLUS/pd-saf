local roompanning = pd.Class:new():register("saf.roompanning")

-- ─────────────────────────────────────
function roompanning:initialize(_, args)
	self.inlets = 1
	self.outlets = 2

	self.colors = {
		background1 = { 19, 47, 80 },
		background2 = { 27, 55, 87 },
		lines = { 46, 73, 102 },
		text = { 127, 145, 162 },
		sources = { 255, 0, 0 },
		source_text = { 230, 230, 240 },
		speakers = { 255, 255, 0 },
		receiver = { 0, 255, 0 },
	}

	self.sources = {}

	-- Sistema de coordenadas: X+ = FRENTE, Y+ = ESQUERDA, Z+ = CIMA
	self.roomsize = { x = 5, y = 5, z = 5, prop = 40 }
	self.receivers = {
		{
			x = (self.roomsize.x * self.roomsize.prop) / 2,
			y = (self.roomsize.y * self.roomsize.prop) / 2,
			z = (self.roomsize.z * self.roomsize.prop) / 2,
			size = 8,
		},
	}

	self.loudspeakers = {}
	local nOut = 4
	local radius = math.min(self.roomsize.x, self.roomsize.y) * 0.5 * self.roomsize.prop
	local cx = (self.roomsize.x * self.roomsize.prop) / 2
	local cy = (self.roomsize.y * self.roomsize.prop) / 2

	for i = 0, nOut - 1 do
		local azi_deg = 360 / nOut * i
		local azi_rad = azi_deg * math.pi / 180

		-- center-space coordinates (for elevation calc)
		local x_local = math.cos(azi_rad) * radius
		local y_local = math.sin(azi_rad) * radius
		local z_local = 0 -- modify later for height speakers

		-- convert local → screen
		local x_screen = x_local + cx
		local y_screen = y_local + cy
		local position = 8

		-- minor fix for position
		if x_screen > (self.roomsize.x * self.roomsize.prop / 2) - 1 then
			if x_screen > (self.roomsize.x * self.roomsize.prop) - position then
				x_screen = x_screen - position
			else
				x_screen = x_screen - (position / 2)
			end
		end
		if y_screen > (self.roomsize.y * self.roomsize.prop / 2) - 1 then
			if y_screen > (self.roomsize.y * self.roomsize.prop) - position then
				y_screen = y_screen - position
			else
				y_screen = y_screen - (position / 2)
			end
		end

		-- elevation in degrees
		local ele_rad = math.atan(z_local, math.sqrt(x_local * x_local + y_local * y_local))
		local ele_deg = ele_rad * 180 / math.pi

		self.loudspeakers[i + 1] = {
			azi = azi_deg,
			ele = ele_deg,
			x = x_screen,
			y = y_screen,
			z = z_local,
			size = position,
		}
	end

	self.view = "xy" -- opções: "xy", "xz", "yz"
	self.wsize = self.roomsize.x * self.roomsize.prop
	self.hsize = self.roomsize.y * self.roomsize.prop
	self:set_size(self.wsize, self.hsize)

	return true
end

-- ──────────────────────────────────────────
function roompanning:postinitialize()
	self:outlet(1, "roomdim", { self.roomsize.x, self.roomsize.y, self.roomsize.z })
	self:outlet(1, "receiver", { 1, self.receivers[1].x, self.receivers[1].y, self.receivers[1].z })

	for i = 1, #self.loudspeakers do
		local speaker = self.loudspeakers[i]
		self:outlet(2, "speaker", { i, speaker.azi, speaker.ele })
	end
end

-- ─────────────────────────────────────
function roompanning:in_1_numspeakers(args)
	self.loudspeakers = {}
	local nOut = args[1]
	local radius = math.min(self.roomsize.x, self.roomsize.y) * 0.5 * self.roomsize.prop
	local cx = (self.roomsize.x * self.roomsize.prop) / 2
	local cy = (self.roomsize.y * self.roomsize.prop) / 2

	for i = 0, nOut - 1 do
		local azi_deg = 360 / nOut * i
		local azi_rad = azi_deg * math.pi / 180

		-- center-space coordinates (for elevation calc)
		local x_local = math.cos(azi_rad) * radius
		local y_local = math.sin(azi_rad) * radius
		local z_local = 0 -- modify later for height speakers

		-- convert local → screen
		local x_screen = x_local + cx
		local y_screen = y_local + cy
		local position = 8

		-- minor fix for position
		if x_screen > (self.roomsize.x * self.roomsize.prop / 2) - 1 then
			if x_screen > (self.roomsize.x * self.roomsize.prop) - position then
				x_screen = x_screen - position
			else
				x_screen = x_screen - (position / 2)
			end
		end
		if y_screen > (self.roomsize.y * self.roomsize.prop / 2) - 1 then
			if y_screen > (self.roomsize.y * self.roomsize.prop) - position then
				y_screen = y_screen - position
			else
				y_screen = y_screen - (position / 2)
			end
		end

		-- elevation in degrees
		local ele_rad = math.atan(z_local, math.sqrt(x_local * x_local + y_local * y_local))
		local ele_deg = ele_rad * 180 / math.pi

		self.loudspeakers[i + 1] = {
			azi = azi_deg,
			ele = ele_deg,
			x = x_screen,
			y = y_screen,
			z = z_local,
			size = position,
		}
		self:outlet(2, "speaker", { i + 1, azi_deg, ele_deg })
	end
	self:repaint()
end

--╭─────────────────────────────────────╮
--│               METHODS               │
--╰─────────────────────────────────────╯
function roompanning:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize("", {})
	self:repaint(1)
end

-- ─────────────────────────────────────
function roompanning:in_1_source(args)
	local index = args[1]
	local ym = args[2] -- X em metros (FRENTE+)
	local xm = args[3] -- Y em metros (ESQUERDA+)
	local zm = args[4] -- Z em metros (CIMA+)

	local px, py, pz = self:meters_to_pixels(xm, ym, zm)

	self.sources[index] = {
		size = self.roomsize.prop / 6,
		x = px,
		y = py,
		z = pz,
		fill = false,
		selected = false,
	}

	self:outlet(1, "source", { index, xm, ym, zm })

	self:repaint(2)
end

-- ─────────────────────────────────────
function roompanning:in_1_yzview(args)
	if #args < 1 then
		error("Wrong arguments")
	end

	if args[1] == 1 then
		self.view = "yz"
	else
		self.view = "xy"
	end
	self:repaint()
end

-- ─────────────────────────────────────
function roompanning:in_1_set(args)
	if #args < 1 then
		return
	end

	if args[1] == "source" then
		local index = args[2]
		local xm = args[3] -- X em metros (FRENTE+)
		local ym = args[4] -- Y em metros (ESQUERDA+)
		local zm = args[5] -- Z em metros (CIMA+)

		local px, py, pz = self:meters_to_pixels(xm, ym, zm)

		self.sources[index] = {
			size = self.roomsize.prop / 6,
			x = px,
			y = py,
			z = pz,
			fill = false,
			selected = false,
		}

		self:outlet(1, "set", { "source", index, xm, ym, zm })
		self:repaint(2)
	elseif args[1] == "roomdim" then
		self.roomsize.x = args[2] -- X (FRENTE)
		self.roomsize.y = args[3] -- Y (ESQUERDA)
		self.roomsize.z = args[4] -- Z (CIMA)
		self.roomsize.prop = args[5] -- proportion meter:pixel
		self:set_size(self.roomsize.x * self.roomsize.prop, self.roomsize.y * self.roomsize.prop)

		self.wsize = self.roomsize.x * self.roomsize.prop
		self.hsize = self.roomsize.y * self.roomsize.prop
		self:repaint(1)
	end
end

-- ─────────────────────────────────────
function roompanning:meters_to_pixels(xm, ym, zm)
	local sx, sy, sz = self.roomsize.x, self.roomsize.y, self.roomsize.z
	local prop = self.roomsize.prop

	if self.view == "xy" then
		-- X forward+: right → invert horizontally so X=0 becomes right side
		local px = (sx - xm) * prop

		-- Y left+: up → invert vertically
		local py = (sy - ym) * prop

		return px, py, zm * prop
	elseif self.view == "xz" then
		-- X forward+: right → SAME flip as XY
		local px = (sx - xm) * prop
		local py = (sz - zm) * prop

		return px, py, ym * prop
	else -- yz
		local px = ym * prop
		local py = (sz - zm) * prop
		return px, py, xm * prop
	end
end

-- ─────────────────────────────────────
function roompanning:pixels_to_meters(px, py)
	local sx, sy, sz = self.roomsize.x, self.roomsize.y, self.roomsize.z
	local prop = self.roomsize.prop

	if self.view == "xy" then
		-- invert X back
		local xm = sx - (px / prop)
		local ym = sy - (py / prop)
		local zm = self.receivers[1].z / prop
		return xm, ym, zm
	elseif self.view == "xz" then
		local xm = sx - (px / prop)
		local zm = sz - (py / prop)
		local ym = self.receivers[1].y / prop
		return xm, ym, zm
	else -- yz
		local ym = px / prop
		local zm = sz - (py / prop)
		local xm = self.receivers[1].x / prop
		return xm, ym, zm
	end
end

--╭─────────────────────────────────────╮
--│                MOUSE                │
--╰─────────────────────────────────────╯
function roompanning:mouse_drag(x, y)
	-- clamp nas bordas
	if x < 2 then
		x = 2
	end
	if x > self.wsize - 2 then
		x = self.wsize - 2
	end
	if y < 2 then
		y = 2
	end
	if y > self.hsize - 2 then
		y = self.hsize - 2
	end

	for i, s in pairs(self.sources) do
		if s.selected then
			local xm, ym, zm = self:pixels_to_meters(x, y)
			local px, py, _ = self:meters_to_pixels(xm, ym, zm)
			if self.view == "xy" then
				s.x, s.y = px, py
			elseif self.view == "xz" then
				s.x, s.z = px, py
			elseif self.view == "yz" then
				s.y, s.z = px, py
			end
			self:outlet(1, "source", { i, ym, xm, zm })
		end
	end

	self:repaint(2)
end

-- ─────────────────────────────────────
function roompanning:mouse_down(x, y)
	for _, s in pairs(self.sources) do
		local sx, sy
		if self.view == "xy" then
			sx, sy = s.x, s.y
		elseif self.view == "xz" then
			sx, sy = s.x, s.z
		else
			sx, sy = s.y, s.z
		end
		local size = s.size
		local dx = x - sx
		local dy = y - sy
		if dx * dx + dy * dy <= (size / 2) * (size / 2) then
			s.selected = true
			return self:repaint(2)
		else
			s.selected = false
		end
	end
end

-- ─────────────────────────────────────
function roompanning:mouse_up(_, _)
	for i, _ in pairs(self.sources) do
		self.sources[i].fill = false
		self.sources[i].selected = false
	end
	self:repaint(2)
end

--╭─────────────────────────────────────╮
--│                PAINT                │
--╰─────────────────────────────────────╯
function roompanning:draw_loudspeaker(g, x, y, size)
	local body_w, body_h = size * 0.5, size
	local speaker_w = size * 0.35

	-- Desenhar o corpo do alto-falante com cantos arredondados
	g:set_color(0, 0, 0) -- Preto
	g:fill_rect(x, y, body_w, body_h)

	-- Alto-falante maior (embaixo)
	g:set_color(255, 255, 255)
	g:stroke_ellipse(
		x + (body_w / 2) - (speaker_w / 2),
		y + (body_h / 2) - (speaker_w / 2) + speaker_w / 2,
		speaker_w,
		speaker_w,
		1
	)
	g:fill_ellipse(
		x + (body_w / 2) - (speaker_w / 2),
		y + (body_h / 2) - (speaker_w / 2) + speaker_w / 2,
		speaker_w,
		speaker_w
	)

	g:set_color(255, 255, 255)
	g:stroke_ellipse(x + (body_w / 2) - (speaker_w / 4), y + (body_h * 0.2), speaker_w / 2, speaker_w / 2, 1)
	g:fill_ellipse(x + (body_w / 2) - (speaker_w / 4), y + (body_h * 0.2), speaker_w / 2, speaker_w / 2)

	if true then
		return
	end
end

-- ─────────────────────────────────────
function roompanning:paint(g)
	g:set_color(table.unpack(self.colors.background1))
	g:fill_all()

	-- Define the number of small rectangles (rows and columns)
	local rows = 10
	local cols = 10

	g:set_color(table.unpack(self.colors.text))
	g:draw_text("xy view", 2, 2, 50, 1)

	-- Define padding and spacing between rectangles
	local rect_width = self.wsize / cols
	local rect_height = self.hsize / rows

	-- Draw the grid of small rectangles
	g:set_color(table.unpack(self.colors.lines))
	for row = 1, rows do
		for col = 1, cols do
			local x = 1 + (col - 1) * rect_width
			local y = 1 + (row - 1) * rect_height
			g:stroke_rect(x, y, rect_width, rect_height, 1)
		end
	end

	for i = 1, #self.loudspeakers do
		g:set_color(table.unpack(self.colors.speakers))
		g:stroke_ellipse(
			self.loudspeakers[i].x,
			self.loudspeakers[i].y,
			self.loudspeakers[i].size,
			self.loudspeakers[i].size,
			1
		)
	end
end

-- ─────────────────────────────────────
function roompanning:paint_layer_2(g)
	-- SOURCES
	for i, s in pairs(self.sources) do
		local px, py

		if self.view == "xy" then
			px, py = s.x, s.y
		elseif self.view == "xz" then
			px, py = s.x, s.z
		else -- yz
			px, py = s.y, s.z
		end

		g:set_color(255, 0, 0)
		g:stroke_ellipse(px - s.size / 2, py - s.size / 2, s.size, s.size, 1)

		if s.selected then
			g:fill_ellipse(px - s.size / 2, py - s.size / 2, s.size, s.size)
		end

		-- Texto
		g:set_color(255, 255, 255)
		g:draw_text(tostring(i), px + 5, py - 5, 20, 3)
	end

	-- RECEIVER
	for _, r in pairs(self.receivers) do
		local px, py

		if self.view == "xy" then
			px, py = r.x, r.y
		elseif self.view == "xz" then
			px, py = r.x, r.z
		else -- yz
			px, py = r.y, r.z
		end

		g:set_color(table.unpack(self.colors.receiver))
		g:stroke_ellipse(px - r.size / 2, py - r.size / 2, r.size, r.size, 1)
	end
end

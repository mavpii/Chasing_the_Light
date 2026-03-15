--
-- General GUI utility functions.
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2025 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

--
-- Helper to make markup text fancier by converting certain tags to use color
-- formatting.
--
-- NOTE:
-- In order to preserve semantics, if the input is nil then the output should
-- be nil as well.
--
function transform_markup(markup)
	if markup then
		return tostring(markup):gsub(
			"<b>([^<]+)</b>",
			"<span color='#baac7d'>%0</span>")
	else
		return nil
	end
end

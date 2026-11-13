-- Small formatting helpers shared by server and client.

local Format = {}

function Format.clock(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", total // 60, total % 60)
end

function Format.joinNames(names: { string }, maxShown: number?): string
	local limit = maxShown or 3
	if #names <= limit then
		return table.concat(names, ", ")
	end
	local shown = table.move(names, 1, limit, 1, {})
	return string.format("%s +%d", table.concat(shown, ", "), #names - limit)
end

return Format

-- Automatically add accent characters to lines
-- To use: add a tag block immediately before the character with "instructions"
-- syntax (regex): `!(a|b)([+-]\d+)?(.)` above/below -- vertical correction (positive = up) -- accent character
-- note: one tag should specify only one accent character
-- sample: {!a^} to place a caret above the character
-- sample: {!b+20˘} to place a breve below the character, then move up 20 pixels to correct position
-- Creates lines with an effect of "accent", automatically cleans all lines with this effect when running

-- Probably only works with lines that don't have a linebreak. May want to work on that...

script_name = "Accenter"
script_description = "Automatically create accents for lines"
script_author = "petzku"
script_version = "0.1.0"
script_namespace = "petzku.Accenter"

EFFECT = 'accent'

local DependencyControl = require("l0.DependencyControl")
local depctrl = DependencyControl{
    { "karaskel", "aegisub.util" },
    feed = "https://raw.githubusercontent.com/petzku/Aegisub-Scripts/master/DependencyControl.json"}

kara, util = depctrl:requireModules()

function clear_old(subs, sel)
    -- remove old generated lines
    to_delete = {}
    for i, line in ipairs(subs) do
        if line.effect and line.effect:find(EFFECT) then
            to_delete[#to_delete + 1] = i
        end
    end
    subs.delete(to_delete)
end

function preproc_chars(line)
    -- preprocess chars in line
    local chars = {}
    local left = line.left
    local i = 1
    -- TODO: this means we drop tags. fine if using just dialog style, not if not.
    for ch in unicode.chars(line.text_stripped) do
        char = {line = line, i = i}
        char.text = ch
        char.width, char.height, char.descent, _ = aegisub.text_extents(line.styleref, ch)
        char.left = left
        char.center = left + char.width/2
        table.insert(chars, char)

        left = left + char.width
    end
    return chars
end

function generate_accents(line)
    -- input line must be karaskel preproc'd
    chars = preproc_chars(line)

    -- iterate through tag blocks
    accents = {}
    i = 1
    tags_len = 0
    text = line.text
    local curr_tags = ""
    while true do
        s, e, tag = text:find("(%b{})", i)
        if tag == nil then break end
        tags_len = tags_len + tag:len()
        if tag:sub(2,2) == "!" then
            aegisub.log(5, "tag: '%s'\n", tag)
            ab, corr, accent = tag:sub(2, -2):match("!([ab])([+-]?%d*)(.+)")
            char = chars[e - tags_len + 1]
            acc_line = util.deep_copy(line)

            aegisub.log(5, "ab: '%s', corr: '%s', accent: '%s'\n", ab, corr, accent)
            x_pos = char.center
            y_pos = line.middle
            aegisub.log(5, "pos: %.2f, %.2f\n", x_pos, y_pos)
            if ab == 'b' then y_pos = y_pos + char.height - char.descent end
            if corr ~= "" and tonumber(corr) then y_pos = y_pos - tonumber(corr) end

            t = curr_tags:gsub("\\pos%b()",""):gsub("\\an?%d+", "")
            acc_line.text = string.format("{\\pos(%.2f,%.2f)\\an5%s}%s", x_pos, y_pos, t, accent)
            acc_line.effect = acc_line.effect .. EFFECT
            aegisub.log(5, "Generated line: %s\n", acc_line.text)
            table.insert(accents, acc_line)
        else
            curr_tags = curr_tags .. tag:sub(2,-2)
            aegisub.log(5, "curr_tags: %s\n", curr_tags)
        end
        i = e + 1
    end
    return accents
end

function process_lines(subs, sel)
    meta, styles = karaskel.collect_head(subs, false)

    to_add = {}
    count = #subs
    for i, line in ipairs(subs) do
        aegisub.progress.set(100 * i / count)
        if line.text and not line.comment and line.text:find("{!.*}") then
            -- god why does lua not have `continue`
            karaskel.preproc_line(subs, meta, styles, line)
            to_add[#to_add+1] = {location=i+1, lines=generate_accents(line)}
        end
    end

    for i = #to_add, 1, -1 do
        loc = to_add[i].location
        lines = to_add[i].lines
        for _, line in ipairs(lines) do
            subs.insert(loc, line)
        end
    end
end

function main(subs, sel)
    task = aegisub.progress.task
    
    task("Clearing old output...")
    clear_old(subs, sel)

    task("Generating new accents...")
    process_lines(subs, sel)

    aegisub.set_undo_point("generate accents")
end

depctrl:registerMacro(main)

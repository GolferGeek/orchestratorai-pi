-- keys.scpt <mode> <text>
-- mode: type (select-all then type) | append | key:<name>
on run argv
	set mode to item 1 of argv
	tell application "System Events"
		set frontmost of (first process whose name is "Pi") to true
		delay 0.4
		if mode is "type" then
			keystroke "a" using command down
			delay 0.2
			keystroke (item 2 of argv)
		else if mode is "append" then
			keystroke (item 2 of argv)
		else if mode is "clear" then
			keystroke "a" using command down
			delay 0.2
			key code 51
		else if mode is "esc" then
			key code 53
		else if mode is "return" then
			key code 36
		else if mode is "tab" then
			key code 48
		end if
	end tell
	return "OK " & mode
end run

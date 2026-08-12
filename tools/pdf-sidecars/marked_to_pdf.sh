#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 input.md output.pdf" >&2
  exit 2
fi

input_path="$1"
output_path="$2"
script_dir="${0:A:h}"

if [[ ! -f "$input_path" ]]; then
  echo "input file not found: $input_path" >&2
  exit 1
fi

output_dir="${output_path:h}"
output_name="${output_path:t}"
desktop_name="$(/usr/bin/uuidgen).pdf"

mkdir -p "$output_dir"

/usr/bin/open -a "/Applications/Marked 2.app" "$input_path"
sleep 2

/usr/bin/osascript - "$desktop_name" <<'APPLESCRIPT'
on run argv
	set outputName to item 1 of argv
	
	tell application "System Events"
		tell process "Marked 2"
			set frontmost to true
			
			click menu item "Print…" of menu 1 of menu bar item "File" of menu bar 1
			
			repeat 40 times
				if exists window "Print" then exit repeat
				delay 0.25
			end repeat
			
			if not (exists window "Print") then error "Print dialog did not appear."
			set printWin to window "Print"
			
			try
				set pdfButton to menu button "PDF" of printWin
			on error
				try
					set pdfButton to menu button 1 of group 2 of splitter group 1 of printWin
				on error
					error "Could not locate PDF menu in Print dialog."
				end try
			end try
			
			perform action "AXShowMenu" of pdfButton
			
			repeat 20 times
				try
					if exists menu item "Save as PDF…" of menu 1 of pdfButton then exit repeat
				end try
				delay 0.25
			end repeat
			
			click menu item "Save as PDF…" of menu 1 of pdfButton
			
			delay 1
			
			keystroke "d" using command down
			delay 0.5
			
			keystroke "a" using command down
			delay 0.2
			keystroke outputName
			delay 0.2
			key code 36
			delay 1
			keystroke "w" using command down
		end tell
	end tell

	delay 2
end run
APPLESCRIPT

desktop_pdf="$HOME/Desktop/$desktop_name"

for _ in {1..40}; do
  if [[ -f "$desktop_pdf" ]]; then
    mv -f "$desktop_pdf" "$output_path"
    "$script_dir/pdf_add_footer.py" "$output_path"
    exit 0
  fi
  sleep 0.25
done

echo "pdf was not created on Desktop: $desktop_pdf" >&2
exit 1

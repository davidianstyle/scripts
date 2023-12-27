# this forces Arena into full screen mode on startup, set back to 3 to reset
# note that if you go into the Arena "Graphics" preference panel, it will reset all of these
# and you will need to run these commands again
defaults write com.wizards.mtga "Screenmanager Fullscreen mode" -integer 0
defaults write com.wizards.mtga "Screenmanager Resolution Use Native" -integer 0

# you can also replace the long complicated integer bit with any other scaled 16:9
# resolution your system supports.
# to find the scaled resolutions, go to System Preferences --> Display and then
# divide the width by 16 and multiple by 9. on my personal system this ends up
# as 3456 x 1944 (versus the bizarre 1728x1117 it will very temporarily select
# when clicking the full screen option in the client
defaults write com.wizards.mtga "Screenmanager Resolution Width" -integer 5120
defaults write com.wizards.mtga "Screenmanager Resolution Height" -integer 1440


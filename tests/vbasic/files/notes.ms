# Notes (gate vb_files): two lines added, saved through the Save dialog,
# copied, a new page, the file opened again, pasted, quit with Yes
ready
bar "Notes" "File" "Edit"
pick 2 0
dialog 1
type The robin came back to the feeder.\n
events 1
pick 2 0
dialog 2
type Two wrens, one blue tit, no crows.\n
events 2
pick 1 2
dialog 3
pause 30
type \n
events 3
pick 2 1
events 4
pick 1 0
events 5
pick 1 1
dialog 4
pause 30
type N
pause 20
type \n
events 6
pick 2 2
events 7
pick 1 3
dialog 5
click 328 256
pause 60

import os
import shutil
import re

src = "/Users/dchang/Code/MTG-Art-Downloader/downloaded/mtgpics/"
dst = "/Users/dchang/Downloads/"
for dir, subdirs, files in os.walk(src):
    for filename in files:
        matches = re.match("([^\(]*)\s\(([^\)]*)\)\s\[(\w*)]\.(\w*)", filename)
        if (matches):
            filenameparts = matches.groups()
            shutil.copyfile(os.path.join(src, filename), os.path.join(dst, os.path.join(dst, filenameparts[0] + " (" + filenameparts[1] + ")" + " [" + filenameparts[2] + "] {davidianstyle proxy}." + filenameparts[3])))

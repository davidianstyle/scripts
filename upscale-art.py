import os
import re
import subprocess
import shlex

src = "/Users/dchang/Downloads/Proxy Art"
dst = "/Users/dchang/Downloads/Proxy Art"

for dir, subdirs, files in os.walk(src):
    for filename in files:
        matches = re.match("([^\.]*)\.(\w*)", filename)
        if (matches):
            filenameparts = matches.groups()
            command = ["/Users/dchang/Code/Real-ESRGAN/realesrgan-ncnn-vulkan", "-i", os.path.join(src, filename), "-o", os.path.join(dst, filenameparts[0] + ".png"), "-n", "realesrgan-x4plus-anime"]
            subprocess.check_output(command)
            upscale_process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            # command = ["ls", "-la", src]
            # upscale_process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            print(command)
            print("returncode: %d" % upscale_process.returncode)
            print("stdout: %s" % upscale_process.stdout)
            print("stderr: %s" % upscale_process.stderr)
            quit()

# Package
version     = "1.8.10"
author      = "Charles Blake"
description = "Infer & generate command-line interface/option/argument parser"
license     = "MIT/ISC"

# Deps
requires    "nim >= 0.20.2"
# NOTE: c-blake runs test.sh (OR gmake test) ON NIM BACK TO 0.20.2 EVEN ON NEW
# RELEASES OF cligen, *BUT* MUCH HELPER LIBRARY CODE NEEDS NEWER Nim.  IF YOU
# USE SUCH LIBRARY CODE AND USE AN OLDER Nim AND WOULD LIKE SOMETHING SPECIFIC
# TO WORK, RAISE AN ISSUE OR EVEN BETTER A PR.

skipDirs = @["test"]

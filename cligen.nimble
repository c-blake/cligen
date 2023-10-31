# Package
version     = "1.6.16"
author      = "Charles Blake"
description = "Infer & generate command-line interface/option/argument parser"
license     = "MIT/ISC"

# Deps
requires    "nim >= 0.20.2"
# NOTE: c-blake runs test.sh (OR gmake RUNNING test/) ON NIM BACK TO 0.20.2 EVEN
# ON NEW RELEASES OF cligen, *BUT* MUCH HELPER LIBRARY CODE NEEDS NEWER NIM IN
# SOME WAY.  IF YOU USE SUCH LIBRARY CODE AND USE AN OLDER NIM AND WOULD LIKE
# SOMETHING SPECIFIC TO WORK, RAISE AN ISSUE OR EVEN BETTER A PR.

skipDirs = @["test"]

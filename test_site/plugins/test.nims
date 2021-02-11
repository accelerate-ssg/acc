name: "Test script"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Test file for Acc nim script integration"
license: "MIT"

import distros

# Exported to acc and called if it exists
"*.md" -> context.proc.for_each_file.glob
proc for_each_file*( path: string ) =
  echo path

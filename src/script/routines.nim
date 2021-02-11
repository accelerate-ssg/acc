import compiler/[vmdef, vm, renderer]
import tables

import logger
from global_state import globalState

proc getFromContext*( args: VmArgs ) = {.gcsafe.}:
  let path:string = args.getString( 0 )
  let value:string = globalState.context[ path ]
  debug "getting " & value & " from " & path
  args.setResult( value )

proc setInContext*( args: VmArgs ) = {.gcsafe.}:
  let path:string = args.getString( 0 )
  let value:string = args.getString( 1 )
  debug "setting " & path & " to " & value
  globalState.context[ path ] = value

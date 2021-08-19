import strutils
import tables

import logging
import types/config

proc `[]`*( config: Config, field: string ):string =
  case field:
  of "name": return config.name
  of "dns_name": return config.dns_name
  of "domains": return config.domains.join(",")
  else:
    return config.map.get_or_default( field )

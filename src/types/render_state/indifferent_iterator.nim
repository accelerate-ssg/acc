import json


# Abstract the array/object difference. We only care about the values anyway.
# An object is essentially an array with named indexes for this purpose.
iterator each*(context: JsonNode): JsonNode =
  if context.kind == JObject:
    for k, v in context:
      yield v
  if context.kind == JArray:
    for v in context:
      yield v

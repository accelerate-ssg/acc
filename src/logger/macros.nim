macro log_section*(title: string, body: untyped): untyped =
  quote do:
    block:
      var parentSection: LogSection
      block:
        withLock(logger.lock):
          parentSection = logger.current
          let newSection = LogSection(
            name: `title`,
            entries: @[],
            subsections: @[],
            parent: logger.current,
            isOpen: true
          )
          logger.current.subsections.add(newSection)
          logger.current = newSection

      try:
        `body`
      finally:
        withLock(logger.lock):
          logger.current.isOpen = false
          logger.current = parentSection

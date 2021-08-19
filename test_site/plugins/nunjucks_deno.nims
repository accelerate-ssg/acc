name: "Nunjucks"
version: "0.1.0"
author: "Jonas Schubert Erlandsson"
description: "Render templates"
license: "MIT"

var
  workspace:string

workspace <- config.workspace_directory

notice "nunjucks **/*.tpl context.json -p " & workspace
info exe( "nunjucks **/*.tpl context.json -p " & workspace )

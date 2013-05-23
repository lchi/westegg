{spawn}       = require 'child_process'
fs            = require 'fs'

task 'build', 'build the whole jam', (cb) ->
  files = fs.readdirSync 'src'
  files = ("src/#{file}" for file in files when file.match(/\.coffee$/))
  clearLibJs ->
    runCoffee ['-c', '-o', 'lib/'].concat(files), ->
      runCoffee ['-c', 'index.coffee'], ->
        cb() if typeof cb is 'function'

task 'test', 'test server and browser support', (cb) ->
  runTests ->
    cb() if typeof cb is 'function'

task 'clean', 'clear out all generated files', (cb) ->
  clearLibJs ->
    cb() if typeof cb is 'function'

runCoffee = (args, cb) ->
  proc =  spawn 'coffee', args
  console.log args
  proc.stderr.on 'data', (buffer) -> console.log buffer.toString()
  proc.on        'exit', (status) ->
    process.exit(1) if status isnt 0
    cb() if typeof cb is 'function'

runTests = (cb) ->
  westegg = new (require("./src/westegg")).Cache({verbose:true})

  files = fs.readdirSync 'test'
  files = ("./test/#{file}" for file in files when file.match(/\.coffee$/))

  for f in files
    t = require f
    t.run westegg

  cb()

clearLibJs = (cb) ->
  files = fs.readdirSync 'lib'
  files = ("lib/#{file}" for file in files when file.match(/\.js$/))
  fs.unlinkSync f for f in files
  cb()

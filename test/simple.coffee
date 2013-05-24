assert = require 'assert'
fs     = require 'fs'

filename = "#{__dirname}/simple_test.txt"

file_old = "hello world!"
file_new = "hello world!!"

exports.run = run = (c, cb) ->
  _writeAndRead c, file_old, ->
    setTimeout((->
      _writeAndRead c, file_new, ->
        fs.unlinkSync filename
        cb()
    ), 1000)


_writeAndRead = (c, expected_data, cb) ->
  fs.writeFileSync "#{__dirname}/simple_test.txt", expected_data

  setTimeout((->
    c.load filename, (err, data) ->
      assert.equal err, null
      assert.equal data, expected_data
      cb()
  ), 1000)

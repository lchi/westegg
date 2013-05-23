utils                 = require './utils'
fs                    = require 'fs'
path                  = require 'path'
util                  = require 'util'

exports.Cache = class Cache

  constructor: (options) ->
    options               = options or {}
    @verbose              = options.verbose or false
    @defaultEncoding      = options.defaultEncoding or "utf8"
    @baseDir              = options.baseDir or "./"
    @transform            = options.transform or (->)
    @missing_file_recheck = options.missing_file_recheck or 1000

    @fileCache          = {} # filename -> view
    @fsErrorCache       = {} # filename -> timestamp last failed

  _log: (o) ->
    if @verbose
      if (typeof o) in ["string","number","boolean"]
        console.log "westegg: #{o}"
      else
        console.log "westegg: #{util.inspect o}"

  load: (filename, options) ->
    start_time           = Date.now()

    options              = options or {}
    realpath             = path.normalize path.resolve @baseDir, filename

    @_log "realpath: #{realpath}"

    v = (@_fileCacheGet realpath) or (@_loadCacheAndMonitor realpath, options)

    if v and not @fsErrorCache[realpath]
      [err, res] = [null, v]
    else
      [err, res] = ["Couldn't load #{realpath}", null]

    @_log "#{realpath} load in #{Date.now() - start_time}ms"

    return [err, res]

  _fileCacheGet: (filename) ->
    if not @fileCache[filename]?
      return null
    else if not @fsErrorCache[filename]?
      return @fileCache[filename]
    else if (Date.now() - @fsErrorCache[filename]) < @missing_file_recheck
      return @fileCache[filename]
    else
      return null

  _loadCacheAndMonitor: (filename, options) ->
    previous_fs_err = @fsErrorCache[filename]?
    try
      fileData = fs.readFileSync filename, options.encoding or @defaultEncoding
      @_clearFsErrorCache filename
    catch e
      fileData = null
      @fsErrorCache[filename] = Date.now()

    # if we hit an fs error and it already happened, just return that
    if not (@fsErrorCache[filename] and previous_fs_err and @fileCache[filename])
      @fileCache[filename] = if fileData then @transform fileData else "Error loading #{filename}"
      @_monitorForChanges filename, options

    return @fileCache[filename]

  _reloadFileInBkg: (filename, options) ->
    fs.readFile filename, 'utf8', (err, fileData) =>
      if err
        @_log "Error when re-reading #{filename} in background"
        @fsErrorCache[filename] = Date.now()
        fileData = null
      else
        @_log "#{filename} updated and ready"
        @_clearFsErrorCache filename

      @fileCache[filename] = if fileData then @transform fileData else "Error loading #{filename}"

  _monitorForChanges: (filename, options) ->
    ###
    we must continuously unwatch/rewatch because some editors/systems invoke a "rename"
    event and we'll end up following the wrong, old 'file' as a new one
    is dropped in its place.

    Files that are missing are ignored here because they get picked up by new calls to _loadCacheAndMonitor
    ###
    if not @fsErrorCache[filename]? # if there's an fsError, this will get rechecked on-demand occasionally
      fsw = null
      try
        @_log "#{filename} starting fs.watch()"
        fsw = fs.watch filename, {persistent: true}, (change) =>
          @_log "#{filename} closing fs.watch()"
          fsw.close()
          @_monitorForChanges filename, options
          @_reloadFileInBkg filename, options
      catch e
        @_log "fs.watch() failed for #{filename}; settings fsErrorCache = true"
        @fsErrorCache[filename] = Date.now()

  _resetFsErrorCache: (k) -> delete @fsErrorCache[k]

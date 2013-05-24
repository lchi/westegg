fs                    = require 'fs'
path                  = require 'path'
util                  = require 'util'

exports.Cache = class Cache

  constructor: (options) ->
    options               = options or {}
    @verbose              = options.verbose or false
    @defaultEncoding      = options.defaultEncoding or "utf8"
    @baseDir              = options.baseDir or "./"
    @transform            = options.transform or ((r, cb)-> cb null, r)
    @missing_file_recheck = options.missing_file_recheck or 1000

    @fileCache          = {} # filename -> view
    @fsErrorCache       = {} # filename -> timestamp last failed
    @fsWatchers         = {} # filename -> fswatcher or null

  _log: (o) ->
    if @verbose
      if (typeof o) in ["string","number","boolean"]
        console.log "westegg: #{o}"
      else
        console.log "westegg: #{util.inspect o}"

  unload: (filename) ->
    realpath = path.normalize path.resolve @baseDir, filename

    @_clearFileCache realpath
    @_clearFsErrorCache realpath
    @_clearFsWatcher realpath

  unloadAll: () ->
    v.close() for _, v of @fsWatchers
    c = {} for c in [@fileCache, @fsErrorCache, @fsWatchers]

  load: (filename, cb, options) ->
    start_time           = Date.now()
    options              = options or {}
    realpath             = path.normalize path.resolve @baseDir, filename

    @_log "realpath: #{realpath}"

    @_load realpath, options, (err, res) =>
      if err or not res
        [err, res] = ["Couldn't load #{realpath}", null]

      @_log "#{realpath} load in #{Date.now() - start_time}ms"

      cb err, res

  _load: (filename, options, cb) ->
    if (v = @_fileCacheGet filename)
      return cb(null, v)
    else
      @_loadCacheAndMonitor filename, options, cb

  _fileCacheGet: (filename) ->
    if not @fileCache[filename]?
      return null
    else if not @fsErrorCache[filename]?
      return @fileCache[filename]
    else if (Date.now() - @fsErrorCache[filename]) < @missing_file_recheck
      return @fileCache[filename]
    else
      return null

  _loadCacheAndMonitor: (filename, options, cb) ->
    previous_fs_err = @fsErrorCache[filename]?
    try
      fileData = fs.readFileSync filename, options.encoding or @defaultEncoding
      @_clearFsErrorCache filename
    catch e
      @_log "#{e} when loading #{filename}"
      fileData = null
      @fsErrorCache[filename] = Date.now()

    # if we hit an fs error and it already happened, just return that
    if not (@fsErrorCache[filename] and previous_fs_err and @fileCache[filename])

      if not fileData
        @_monitorForChanges filename, options
        return cb(@fileCache[filename] = "Error loading #{filename}", null)
      else
        @transform fileData, (err, transformedData) =>
          if err
            delete @fileCache[filename]
            @fsErrorCache[filename] = Date.now()
          else
            @fileCache[filename] = transformedData
            @_monitorForChanges filename, options

          cb err, @fileCache[filename]

  _reloadFileInBkg: (filename, options) ->
    fs.readFile filename, 'utf8', (err, fileData) =>
      if err
        @_log "Error when re-reading #{filename} in background: #{err}"
        @fsErrorCache[filename] = Date.now()
        fileData = null
      else
        @_log "#{filename} updated and ready"
        @_clearFsErrorCache filename

      if not fileData
        @fileCache[filename] = "Error loading #{filename}"
      else
        @transform fileData, (err, transformedData) =>
          if err
            delete @fileCache[filename]
            @fsErrorCache[filename] = Date.now()
          else
            @fileCache[filename] = transformedData
            @_monitorForChanges filename, options

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
        @fsWatchers[filename] = fsw = fs.watch filename, {persistent: true}, (change) =>
          @_log "#{filename} closing fs.watch()"
          fsw.close()
          delete @fsWatchers[filename]
          @_monitorForChanges filename, options
          @_reloadFileInBkg filename, options
      catch e
        @_log "fs.watch() failed for #{filename}; settings fsErrorCache = true"
        @fsErrorCache[filename] = Date.now()

  _clearFileCache: (k) -> delete @fileCache[k]
  _clearFsErrorCache: (k) -> delete @fsErrorCache[k]
  _clearFsWatcher: (k) -> delete @fsWatchers[k]

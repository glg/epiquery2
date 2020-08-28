events      = require 'events'
snowflake   = require 'snowflake-sdk'
log         = require 'simplog'

class SnowflakeDriver extends events.EventEmitter

  constructor: (@config) ->
      @valid = false

  execute: (query, context) ->
    log.debug "executing Snowflake query #{query}"
    stream = @conn.execute({sqlText: query}).streamRows()
    stream.on 'data', (record) =>
        @emit 'row', record
    stream.on 'end', (query) =>
        @emit 'endquery', query
    stream.on 'error', (error) =>
        @valid = false
        @emit 'error', error

  connect: (cb) ->
    log.debug "connecting snowflake account: ", @config.account
    snowflake.configure({insecureConnect: true})
    @conn = snowflake.createConnection(@config);
    @conn.connect (err, conn) =>
        if (err)
            log.error("Failed connecting to snowflake\n#{err}")
        else
            @valid = true
            log.debug("Connected to snowflake")
        cb(err, @)

  # do nothing, but we need this so we can be pooled
  disconnect: ->
    @conn.destroy (err, conn) =>
        log.debug "connection to %j closed", @config.account
        if (err)
            log.error("Error disconnecting from Snowflake\n#{err}")
        
  
  validate: ->
    @valid

module.exports.DriverClass = SnowflakeDriver

events          = require 'events'
log             = require 'simplog'
_               = require 'lodash-contrib'
tedious         = require 'tedious'
os              = require 'os'

lowerCaseTediousTypeMap = {}

# to make it so folks don't have to learn tedious' crazy casing of
# data types, we'll keep a map of lower cased type names for comparison
# to the inbound parameter type names ( in the case of a parameterized
# query request )
for propertyName in Object.getOwnPropertyNames(tedious.TYPES)
  type = tedious.TYPES[propertyName]
  lowerCaseTediousTypeMap[type.name.toLowerCase()] = type
  _.forEach type.aliases, (alias) =>
    lowerCaseTediousTypeMap[alias.toLowerCase()] = type
  # add some type helpers to cast things appropriately
  _.forEach lowerCaseTediousTypeMap, (value, key) ->
    # default transform does nothing, just returns what it was
    # given
    transformValue = (providedValue) -> providedValue
    #  our specialized value transformers for types that need that sort of thing
    if key is "bit"
      transformValue = (providedValue) ->
        log.debug "transforming bit value #{providedValue} with type #{typeof(providedValue)}"
        # lowercase any string values so we can do case insensitive string values
        if providedValue and (typeof(providedValue) is "string")
          providedValue = providedValue.toLowerCase()
        # 'cast' to number, this is sort of a specialization of the normal javascript rules
        if not isNaN(new Number(providedValue))
          log.debug "transforming bit value (#{providedValue}) as number with type #{typeof(providedValue)}"
          providedValue = new Number(providedValue).valueOf()
          log.debug "providedValue: #{providedValue}"
          if providedValue is 0
            return false
          else
            return true
        else if typeof(providedValue) is "string"
          log.debug "transforming bit value (#{providedValue}) as string with type #{typeof(providedValue)}"
          if providedValue is "false"
            return false
          else if providedValue is "true"
            return true
          else
            throw new Error "unexpected value (#{providedValue}) for bit type"
        else if typeof(providedValue) is 'boolean'
          return providedValue
      transformValue = transformValue
    else if key.startsWith("datetime")
      # make it a date object
      transformValue = (providedValue) ->
        if providedValue is null or providedValue is undefined or providedValue is 'null' or providedValue is 'undefined'
          providedValue = null
        else
          new Date(providedValue)
    # as a convenience, we'll allow you to pass an array in to a varchar or nvarchar param
    # when this happens we'll convert the array to a string
    else if key is 'varchar' or key is 'nvarchar'
      transformValue = (providedValue) ->
        if _.isArray(providedValue)
          # return the string version of provided array
          providedValue.toString()
        else
          # it wasn't an array, so we just go with the historical behavior
          providedValue
    value.transformValue = transformValue

class MSSQLDriver extends events.EventEmitter
  constructor: (@config) ->
    @valid = false

  escapeTemplateContext: (context) ->
    _.walk.preorder context, (value, key, parent) ->
      if parent
        parent[key] = value.replace(/'/g, "''") if _.isString(value)

  # returns an object containing the pertinent information about a parameter declaration from 
  # a tepmlate.
  # Parameter lines look something like this
  #  --@sandwich varchar
  #  --@jeans varchar(25)
  #  --@biscuits varchar(25) = gravy
  # generally the format is 
  # In the following format specification <> indicates a required portion, and () optional
  # --@<variable name> <type name>(length | <precision>, <scale>) (= inbound parameter name [if differs from <variable name>])
  #  <type specifier> is basically the same as a SQL type declaration with the length declaration being
  #    optional. The optinality of the length is not a good idea, it's a concession to backwards compatability
  parseQueryParameters2: (query, context) ->

      lines = query.match ///^--@.*$///mg

      _.map lines, (line) =>
        line = line.replace '--', ''
        line = line.replace '=', ''

        [variableName, type, paramName] = line.split(/\s+/)
        variableName = variableName.replace('@','')
        typeMatch = type.match(/([^()]*)(\(.*\))?/)
        type = typeMatch[1]
        typeLengthPrecisionOrScale = typeMatch[2]
        precision = null
        scale = null
        typeLength = null
        # we use the same name for the parameter name (used when looking up the value in the request) 
        # as the variable name UNLESS a paramter name was explicitly defined
        paramName = variableName unless paramName
        # if we have a 'length' value, which is to say if our type declaration came with a 
        # parenthesized component, it will either be a length, precision, or precision and 
        # scale value. If it's precision and scale it will have a ',' as part of the value.
        if typeLengthPrecisionOrScale
            # first, we pick of the parenthesis, to leave us with just the stuff inside
            typeLengthPrecisionOrScale = typeLengthPrecisionOrScale.replace('(', '').replace(')', '')
            # if the contents of the parens (the value now in typeLength) has a comma in it
            # then it's actually precison and scale information
            # so, if we don't have a comma it's a length or simply precision, otherwise it's
            # precision and scale so we have to pick it apart
            if typeLengthPrecisionOrScale.indexOf(',') != -1
                [precision, scale] = typeLengthPrecisionOrScale.split(',')
            else
                # if we don't have a comma, then the value could be the length or the precision
                # depending on the data type. Our job isn't to determine what the types are only
                # to collect the data so we'll go ahead and treat length and precision as the same
                # setting both to the same thing
                precision = typeLength = typeLengthPrecisionOrScale

        # here we can use the unescaped context because
        # parameter values are not subject to the sql injection problems that
        # raw sql is, and our escaping would render parmeter values incorrect e.g.
        # duplicating 's
        value = _.reduce paramName.split('.'), (doc,prop) ->
          doc[prop]
        , context.unEscapedTemplateContext

        {varName: variableName, type, typeLength, precision, scale, paramName, value}

  parseQueryParameters: (query, context) ->

    lines = query.match ///^--@.*$///mg

    _.map lines, (line) =>
      line = line.replace '--', ''
      line = line.replace '=', ''

      [varName,type,value] = line.split /\s+/
      varName = varName.replace('@','')
      type = type.replace /\(.*\)/

      # as a convenience, we'll let you omit the value declaration in which case we'll use the name of the parametr
      # as the name of the value
      value = varName unless value

      # here we can use the unescaped context because
      # parameter values are not subject to the sql injection problems that
      # raw sql is, and our escaping would render parmeter values incorrect e.g.
      # duplicating 's
      value = _.reduce value.split('.'), (doc,prop) ->
        doc[prop]
      , context.unEscapedTemplateContext

      { varName, type, value }

  connect: (cb) ->
    @conn = new tedious.Connection @config

    @conn.on 'debug', (message) => log.debug message
    @conn.on 'connect', (err) =>
      if err
        cb(err)
      else
        @valid = true
        cb(err, @)
    @conn.on 'errorMessage', (message) =>
      log.error "tedious errorMessage: %j", message
      @emit 'errorMessage', message
    @conn.on 'error', (message) =>
      # on error we mark this instance invalid, JIC
      @valid = false
      log.error "tedious error: #{message}"
      @emit 'error', message

  disconnect: ->
    @conn.close()

  validate: ->
    @valid

  invalidate: -> @valid = false

  resetForReleaseToPool: (cb) -> @conn.reset(cb)

  execute: (query, context) =>
    rowSetStarted = false
    # in an attempt to make thing easier to track down on the SQL server side
    # we're going to insert the name of the template that we're executing
    query = "-- #{context.templateName}\n#{query}"
    log.debug "query as sent to server:\n#{query}"
    request = new tedious.Request query, (err,rowCount) =>
      return @emit('error', err) if err
      @emit('endrowset') if rowSetStarted
      @emit('endquery')

    # we use this event to split up multipe result sets as each result set
    # is preceeded by a columnMetadata event
    request.on 'columnMetadata', () =>
      @emit('endrowset') if rowSetStarted
      @emit('beginrowset')
      rowSetStarted = true

    request.on 'row', (columns) =>
      @emit('beginrowset') if not rowSetStarted
      rowSetStarted = true
      @emit 'row', @mapper(columns)
    
    parameters = @parseQueryParameters2(query,context)

    if _.isEmpty parameters
      @conn.execSqlBatch request, (error) =>
        log.error "[q:#{context.queryId}, t:#{context.templateName}] connect failed %j", error
        @emit 'error', error
    else
      # so, I really don't think it should but there are cases (in v1.13.0 at least) where the execSql method can
      # raise an exception, so we'll attempt to handle that gracefully by catching errors, we'll also
      # take advantage of the fact that we have to do this to allow creation of errors in the 'transformValue'
      # functions
      try
        parameters.forEach (param) =>
          lowerCaseTypeName = param.type.toLowerCase()
          tediousType = lowerCaseTediousTypeMap[lowerCaseTypeName]
          throw new TypeError("Unknown parameter type (#{param.type}) for #{param.varName}") if not tediousType
          transformedValue = tediousType.transformValue(param.value)
          paramOptions = {}
          # we entered into this with the ability to not specify length, precision or scale in our
          # param declarations, so we're gonna start by fixing nvarchar and varchar lengths if they're
          # under a threshold, then we'll come back and add first class support for length
          if lowerCaseTypeName is 'varchar' or lowerCaseTypeName is 'nvarchar' or lowerCaseTypeName is 'varbinary'
            # if we have a parameter length specified we will use that, ELSE we'll fall back to legacy behavior
            if param.typeLength
              paramOptions.length = param.typeLength
            else
              # if we have a value, we want to set the param length to 255 UNLESS it's greater
              # so we don't truncate anything
              # there is a check here for no transformed value. if we have no value, thus our parameter value is null,
              # so we'll just fix all our char lengths to 255 unless we have a value and it's length is greater than 255
              if transformedValue and transformedValue.length > 255
                paramOptions.length = 8001
              else
                paramOptions.length = 255
          else if lowerCaseTypeName in ["time", "datetime2", "datetimeoffset"]
            # these are the types that support only a scale value, and since they support only a scale value 
            # that value will be assigned to both precision and scale (simply due to the way we parse types)
            # we'll use the length
            paramOptions.scale = param.typeLength
          else if lowerCaseTypeName in ["decimal", "numeric"]
            # these are our types that upport a precision and _optionally_ a scale we will assume that the parsing
            # has worked correctly and we'll only have a scale if we have a precision however we won't validate that fact
            paramOptions.precision = param.precision
            if param.scale
              paramOptions.scale = param.scale

          log.debug "adding parameter #{param.varName}, length (#{transformedValue?.length}), value (#{param.value}) as type #{tediousType.name} with lowerCaseTypeName #{lowerCaseTypeName}, transformed value: #{transformedValue}\n\tOptions: #{JSON.stringify(paramOptions)}"
          request.addParameter(param.varName, tediousType, transformedValue, paramOptions)
        @conn.execSql request
      catch e
        log.error "Exception raised by execSql: \n#{e.stack}"
        @emit 'error', e

module.exports.DriverClass = MSSQLDriver

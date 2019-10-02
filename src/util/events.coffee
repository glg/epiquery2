config    = require '../config.coffee'
log       = require './log.coffee'
eClient   = require '@azure/event-hubs'
uuid      = require 'uuid/v4'

class EventPublisher
  @publisher: undefined

  constructor: () ->
    if (config.isPublishEnabled()) && (@publisher == undefined)
      try
        @publisher = eClient.EventHubClient.createFromConnectionString(
                  config.eventHubConnString, config.eventHubName)

      catch err
        log.error err

  @buildMessageFromContext: (context) ->
    # compose the json for the event
    # clone the template context, and remove extra crap. small message please.
    ctx = JSON.parse(JSON.stringify(context.templateContext))
    delete ctx['connection']
    delete ctx['host']
    delete ctx['cache-control']
    delete ctx['sec-fetch-mode']
    delete ctx['sec-fetch-user']
    delete ctx['sec-fetch-site']
    delete ctx['cookie']
    delete ctx['upgrade-insecure-requests']
    delete ctx['user-agent']
    delete ctx['accept']
    delete ctx['accept-encoding']
    delete ctx['accept-language']

    #Extract the template name and directory path to construct event type string
    offset = context.templateName.lastIndexOf('/')
    theName = context.templateName.substr(offset + 1, context.templateName.length)
    thePrefix = ''
    thePrefix = ".#{context.templateName.substr(0, offset)}".replace('/', '.') if offset > 0

    return [
      {
        id: uuid().toString(),
        template: theName,
        eventType: 'glg.epiquery.post' + thePrefix,
        dataVersion: '1.0',
        params: ctx
      }
    ]

  scrub: (eventMsg) =>
    #the data in this list should not be broadcast in the open
    badFieldNames = [
      'ssn',
      'tax_id',
      'bank_account',
      'bank_routing',
      'bank_swift'
    ]
    #iterate through the params property names
    params = Object.keys(eventMsg[0].params)

    #slug values
    for bad in badFieldNames
      for param in params
        #if it starts with a taboo name, slug it.
        if param.toLowerCase().startsWith(bad)
          log.info "Potential sensitive data, slugging value: #{param}"
          eventMsg[0][param] = '***********'


  @isDangerTemplate: (eventMsg) =>
    #this list will grow as needed.
    #MUST be lowercase!
    dangerZone = [
      'createpaymentaccount.mustache'
    ]
    #single element array, pull the template name
    checkVal = eventMsg[0].template.toLowerCase()
    for target in dangerZone
      if checkVal == target
        log.info "Reserved template encountered, skipping event publish: #{eventMsg[0].template}"
        return true
    return false
    
  publish: (eventMsg) =>
    # publish
    #is the publisher enabled in the env vars?
    if config.isPublishEnabled()
      #is this template on the naughty list?
      if !EventPublisher.isDangerTemplate(eventMsg)
        this.scrub(eventMsg)

        @publisher.send(eventMsg).catch((err) => 
          log.error err
      )
    else
      #If in development mode, and publish is disabled, emit to the console instead
      if config.isDevelopmentMode()
        console.log JSON.stringify(event)

module.exports.EventPublisher = EventPublisher

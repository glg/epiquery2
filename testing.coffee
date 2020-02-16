
_ = require "lodash"

query = [
    "--@pants varchar(25) = sandwich",
    "--@another nvarchar = monkey"
].join("\n")

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
parseQueryParameters = (query) ->

    lines = query.match ///^--@.*$///mg

    console.log "lines: ", lines.length

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

        {variableName, type, typeLength, precision, scale, paramName}

console.log(parseQueryParameters(query))
console.log(parseQueryParameters("--@aDecimal decimal(3)"))
console.log(parseQueryParameters("--@anotherDecimal decimal(3,1)"))

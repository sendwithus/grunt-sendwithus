###
# grunt-sendwithus
# https://github.com/sendwithus/grunt-sendwithus
#
# Copyright (c) 2015 sendwithus
# Licensed under the MIT license.
###

pkg       = require '../package.json'
_         = require 'lodash'
Q         = require 'q'
normalize = require('path').normalize
grunt     = require 'grunt'
request   = require 'request'
crypto    = require 'crypto'

task =
    name: 'sendwithus'
    description: 'Grunt plugin to deploy your local HTML email templates to sendwithus'

# helper method to get a normalized home folder path
getUserHome = () ->
  return process.env[if process.platform is 'win32' then 'USERPROFILE' else 'HOME']

# promise-powered request helper
requestp = (options) ->
    deferred = Q.defer()
    request options, (err, res, body) =>
        if err and res.statusCode isnt 200
            grunt.log.error 'API request failed with statusCode:', res.statusCode
            deferred.reject err

        deferred.resolve JSON.parse(body)

    return deferred.promise


class Sendwithus

    constructor: (apiKey) ->
        @version = 1
        @url     = "https://api.sendwithus.com/api/v#{@version}/"
        @apiKey  = apiKey

        @indexFile     = normalize("#{getUserHome()}/#{pkg.name}.json")
        @indexContents = []

        @initIndex()

    buildURL: (segments) ->
        return "#{@url}#{segments.join "/"}"

    api: (segments) ->
        requestOptions =
            url: @buildURL(segments)
            auth:
                user: @apiKey
                password: ''
            headers:
                accept: 'application/json'

        return requestp(requestOptions).then(
            (data) ->
                return data
            (err) ->
                grunt.log.error 'API request failed with statusCode:', res.statusCode
                return err
        )

    # Get all templates from the API
    getTemplates: () ->
        return @api(['templates']).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not retrieve a list of templates: #{err}"
                return  err
        )

    # Get all templates from the API
    getTemplateVersions: (template) ->
        return @api(['templates', template.id, 'versions']).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not retrieve a list of template versions: #{err}"
                return  err
        )

    # Update template with ID through API
    updateTemplate: (template) ->
        return @api(['templates']).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not retrieve a list of templates: #{err}"
                return  err
        )

    # Generate an MD5 hash from an arbitrary string
    generateHash: (string) ->
        return crypto.createHash('md5').update(string).digest('hex')

    # Check that the index file is present
    initIndex: () ->
        @indexNeedsUpdate = false

        # Check if the local cache file exists or not
        if not grunt.file.exists @indexFile
            grunt.log.ok "Cache file doesn't exist, creating..."
            grunt.file.write @indexFile, '[]' # write a blank file
        else
            grunt.log.ok 'Cache file exists, continuing...'

        # Read the contents of the index file
        @indexContents = grunt.file.readJSON @indexFile

        if @indexContents.length is 0
            grunt.log.ok 'Index is empty, populating for first run...'

        # Get all the templates from the api
        @getTemplates().then (templates) =>
            grunt.log.writeln "#{@indexContents.length} templates in the local index" if @indexContents.length isnt 0

            promises = []

            # Loop through the templates from the api
            _.forEach templates, (apiTemplate) =>
                # Get the indexed template and it's versions if it exists
                template = _.filter @indexContents, (t) -> return apiTemplate.id is t.id

                # If an entry for this template doesn't exist in the index, create one to use
                if not template.length
                    @indexNeedsUpdate = true
                    grunt.log.writeln "--> Template #{apiTemplate.id} not indexed, creating one..."
                    template = apiTemplate
                else
                    grunt.log.writeln "--> Template #{apiTemplate.id} indexed, continuing..."
                    template = template[0]

                promises.push @getTemplateVersions(template).then (versions) =>
                    # Clone the apiTemplate to a new variable and
                    # swap out the versions with the new full versions
                    t = _.cloneDeep(template)
                    t.versions = versions

                    # Resolve the template
                    return t

            return Q.allSettled promises

        .then (templatePromises) =>
            # Loop through the templates from the API
            return _.forEach templatePromises, (result) =>
                if result.state is "fulfilled"
                    apiTemplate = result.value
                else
                    reason = result.reason

                # Loop through the template versions to generate the hash to compare
                # against api template to local indexed template
                return _.forEach apiTemplate.versions, (apiVersion) =>
                    # Get the indexed template and it's versions if it exists
                    indexedTemplate = _.find(@indexContents, (t) -> return t.id is apiTemplate.id) or apiTemplate

                    # Get the version from the indexedTemplate
                    version = _.find indexedTemplate.versions, (v) -> return v.id is apiVersion.id

                    # Generate the current version hash from the api version
                    htmlHash = @generateHash apiVersion.html
                    textHash = @generateHash apiVersion.text

                    # If the upstream hash is the same as the indexed hash for the version
                    if htmlHash is version.htmlHash
                        grunt.log.error "Version with id #{version.id} HTML hash matches upstream, continuing..."
                    else if textHash is version.textHash
                        grunt.log.error "Version with id #{version.id} plain text hash matches upstream, continuing..."
                    else
                        grunt.log.error "Template hash upstream doesn't match indexed template hash, updating..."
                        @indexNeedsUpdate = true

                    if @indexNeedsUpdate
                        # Assign the HTML and text hashes to the version
                        version.htmlHash = version.htmlHash or htmlHash
                        version.textHash = version.textHash or textHash

                        delete version.html
                        delete version.text

                    return version

        .then (templatesWithVersionsPromises) =>
            templates = []
            _.forEach templatesWithVersionsPromises, (result) =>
                if result.state is "fulfilled"
                    template = result.value
                else
                    reason = result.reason

                templates.push template if not reason?

            if @indexNeedsUpdate
                @indexContents = templates
                grunt.log.writeln 'Writing index file contents'
                grunt.file.write @indexFile, JSON.stringify(@indexContents, null, 2)


module.exports = (grunt) ->
  grunt.registerMultiTask task.name, task.description, () ->
    done      = @async()
    fileCount = @filesSrc.length
    opts      = @data.options

    # If there's no files, just run the callback
    done() if fileCount < 1

    # Check if the apiKey was provided
    if opts.hasOwnProperty 'apiKey' and opts.apiKey?
      # return an error message from the plugin
      return grunt.log.error 'You need to include your sendwithus API key in the task options'

    # Generate a new Sendwithus with the apiKey
    swu = new Sendwithus(opts.apiKey)

    # Iterate over files to upload
    # @filesSrc.forEach (filepath) ->
    #   options = _.clone(opts)
    #   # options.file = filepath
    #   options.body = grunt.file.read(filepath)

    #   # Setup the data to send for the template
    #   data =
    #     name    : options.name    or 'grunt-sendwithus'
    #     subject : options.subject or 'grunt-sendwithus'
    #     html    : options.body    or '<html><head></head><body></body></html>'
    #     text    : options.text    or ''

    #   # Create the template
    #   api.createTemplate(data, (err, data) ->
    #     return grunt.log.error(err) if err?

    #     fileCount--

    #     console.dir data
    #     msg = options.file or 'sendwithus template'
    #     grunt.log.writeln "Uploaded #{msg} to sendwithus."

    #     # Last iteration? Execute and return the callback
    #     return done() if fileCount < 1
    #   )

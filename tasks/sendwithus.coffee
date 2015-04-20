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
cheerio   = require 'cheerio'
crypto    = require 'crypto'
grunt     = require 'grunt'
request   = require 'request'

path      = require('path')
normalize = path.normalize
basename  = path.basename

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

        deferred.resolve body

    return deferred.promise


class Sendwithus

    constructor: (apiKey) ->
        @version = 1
        @url     = "https://api.sendwithus.com/api/v#{@version}/"
        @apiKey  = apiKey

        @indexFile     = normalize("#{getUserHome()}/#{pkg.name}.json")
        @indexContents = @getIndexContents()

    # Generate an MD5 hash from an arbitrary string
    generateHash: (string) ->
        return crypto.createHash('md5').update(string).digest('hex')

    # build URL from given url path
    buildURL: (path) ->
        return "#{@url}#{path}"

    # API handler
    api: (path, options = {}) ->
        url = @buildURL(path)
        # grunt.log.writeln 'Request url:', url
        defaultOptions =
            method: 'GET'
            url: url
            auth:
                user: @apiKey
                password: ''
            headers:
                accept: 'application/json'

        requestOptions = _.defaults options, defaultOptions
        console.log requestOptions

        return requestp(requestOptions).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error 'API request failed with statusCode:', err.statusCode
                return err
        )

    # Get all templates from the API
    getTemplates: () ->
        path = 'templates'

        return @api(path).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not retrieve a list of templates: #{err}"
                return err
        )

    # Get all templates from the API
    getTemplateVersions: (template) ->
        path = "templates/#{template.id}/versions"

        return @api(path).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not retrieve a list of template versions: #{err}"
                return err
        )

    # create template in the api, return response
    createTemplate: (data) ->
        path    = 'templates'
        options =
            method : 'POST'
            json   : data

        return @api(path, options).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not update or create template: #{err}"
                return err
        )

    # update a template given a template id and version id
    updateTemplateVersion: (templateId, versionId, data) ->
        path    = "templates/#{templateId}/versions/#{versionId}"
        options =
            method : 'POST'
            json   : data

        return @api(path, options).then(
            (data) ->
                return data

            (err) ->
                grunt.log.error "Could not update or create template: #{err}"
                return err
        )

    # Get the contents of the index
    getIndexContents: () ->
        # Check if the local cache file exists or not
        if not grunt.file.exists @indexFile
            grunt.log.ok "Cache file doesn't exist, creating..."
            grunt.file.write @indexFile, '[]' # write a blank file with an array for valid JSON
        else
            grunt.log.ok 'Cache file exists, continuing...'

        # Read the contents of the index file
        return grunt.file.readJSON @indexFile

    # Write the given contents to the index file
    writeIndexContents: (contents) ->
        grunt.log.ok 'Writing index file contents'
        grunt.file.write @indexFile, JSON.stringify(contents, null, 2)

    # Do index stuff
    initIndex: () ->
        @indexNeedsUpdate = false

        if @indexContents.length is 0
            grunt.log.ok 'Index is empty, populating for first run...'

        # Get all the templates from the api
        return @getTemplates().then (templates) =>
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
                @writeIndexContents(@indexContents)


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
            return grunt.log.error 'API key not found in the task options'

        # Generate a new Sendwithus instance with the apiKey
        swu = new Sendwithus(opts.apiKey)

        # Iterate over files to upload
        @filesSrc.forEach (filepath) =>
            options = _.clone opts
            html    = grunt.file.read filepath
            $       = cheerio.load html

            # Setup the data to send for the template
            versionData =
                name    : basename(filepath, '.html').replace /[_-]/g, ' '
                subject : $('title').text()
                html    : html

            # Setup the data to be used in the index file
            indexData =
                filepath : filepath
                htmlHash : swu.generateHash html

            # Create the template here
            return swu.createTemplate(versionData).then (template) ->
                # Decrement the file counter
                fileCount--

                grunt.log.writeln "Uploaded #{FILEPATH} to sendwithus."

                indexData = _.defaults versionData, indexData

                console.log indexData

                # Update the index with the filepath
                # swu.updateIndex(template.id, indexData)

                # Last iteration? Execute and return the callback
                return done() if fileCount < 1

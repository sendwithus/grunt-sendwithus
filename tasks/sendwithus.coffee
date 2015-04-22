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

        return requestp(requestOptions).then(
            (data) =>
                return data

            (err) =>
                grunt.log.error 'API request failed with statusCode:', err.statusCode
                return err
        )

    # Get all templates from the API
    getTemplates: () ->
        path = 'templates'

        return @api(path).then(
            (data) =>
                return data

            (err) =>
                grunt.log.error "Could not retrieve a list of templates: #{err}"
                return err
        )

    # Get all templates from the API
    getTemplateVersions: (template) ->
        path = "templates/#{template.id}/versions"

        return @api(path).then(
            (data) =>
                return data

            (err) =>
                grunt.log.error "Could not retrieve a list of template versions: #{err}"
                return err
        )

    # create template in the api, return response
    createTemplate: (data) =>
        path    = 'templates'
        options =
            method : 'POST'
            json   : data

        return @api(path, options).then(
            (data) =>
                return data

            (err) =>
                grunt.log.error "Could not update or create template: #{err}"
                return err
        )

    # update a template in the API and in the cache
    updateTemplateVersion: (indexedVersion, baseVersionData) ->
        htmlHash = @generateHash baseVersionData.html

        if indexedVersion.htmlHash isnt htmlHash
            grunt.log.writeln '-> Version hash is different than cached, updating in API'

            path    = "templates/#{indexedVersion.templateId}/versions/#{indexedVersion.id}"
            options =
                method : 'PUT'
                json   : baseVersionData

            return @api(path, options).then(
                (apiVersion) =>
                    grunt.log.writeln "   └── Updated version #{apiVersion.id} in API"

                    # Update the index entry
                    position = _.findIndex @indexContents, (v) -> return v.id is apiVersion.id

                    # Setup the data to be added to the version for the index file
                    indexData =
                        templateId : indexedVersion.templateId
                        id         : apiVersion.id
                        name       : apiVersion.name
                        subject    : apiVersion.subject
                        htmlHash   : htmlHash
                        filepath   : indexedVersion.filepath


                    # Merge the base data and index data together
                    versionIndexData = _.defaults baseVersionData, indexData

                    delete versionIndexData.html
                    delete versionIndexData.text

                    @indexContents.splice position, 1, versionIndexData
                    @writeIndexContents(@indexContents)

                    return data

                (err) =>
                    grunt.log.error "Could not update or create template: #{err}"
                    return err
            )
        else
            return grunt.log.writeln '   └── Ignoring, version hash is the same'

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
        grunt.log.ok 'Writing contents to index file...'
        grunt.file.write @indexFile, JSON.stringify(contents, null, 2)


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
            baseVersionData =
                name    : basename(filepath, '.html').replace /[_-]/g, ' '
                subject : $('title').text()
                html    : html

            # Get the indexed version by its filepath
            indexedVersion = swu.indexContents.filter (v) -> return filepath is v.filepath

            # Check if we have a cached file and need to update it,
            # or create a new template in the api
            if indexedVersion.length isnt 0
                grunt.log.ok "Found template #{filepath} in cache, updating..."
                swu.updateTemplateVersion indexedVersion[0], baseVersionData
            else
                grunt.log.ok "Didn't find template #{filepath} in cache, creating a new one.."

                # Create the template here
                swu.createTemplate(baseVersionData).then (template) =>
                    grunt.log.writeln "-> Uploaded #{filepath} to sendwithus"

                    # get the newly created template and its new version
                    swu.getTemplateVersions(template).then (versions) =>
                        version = JSON.parse(versions)[0]

                        # Setup the data to be added to the version for the index file
                        indexData =
                            templateId : template.id
                            id         : version.id
                            name       : version.name
                            subject    : version.subject
                            htmlHash   : swu.generateHash html
                            filepath   : filepath

                        # Merge the base data and index data together
                        versionIndexData = _.defaults baseVersionData, indexData

                        # Update the index with the filepath
                        swu.updateIndex versionIndexData

            # decrement the file count
            fileCount--

            return done() if fileCount < 1

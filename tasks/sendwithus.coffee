###
# grunt-sendwithus
# https://github.com/sendwithus/grunt-sendwithus
#
# Copyright (c) 2015 sendwithus
# Licensed under the MIT license.
###

pkg = require '../package.json'
_ = require 'lodash'
Q = require 'q'
cheerio = require 'cheerio'
crypto = require 'crypto'
grunt = require 'grunt'
request = require 'request'

path = require('path')
normalize = path.normalize
basename = path.basename

task =
  name: 'sendwithus'
  description: 'Grunt plugin to deploy your local HTML email templates to sendwithus'

# helper method to get a normalized home folder path
getUserHome = () ->
  return process.env[if process.platform is 'win32' then 'USERPROFILE' else 'HOME']

# promise-powered request helper
requestp = (options) ->
  deferred = Q.defer()
  request options, (err, res, body) ->
    if res.statusCode is 200
      deferred.resolve body

    if err
      deferred.reject err
    else
      deferred.reject res

  return deferred.promise


class Sendwithus

  constructor: (apiKey, debug=false) ->
    @version = 1
    @url = "https://api.sendwithus.com/api/v#{@version}/"
    @apiKey = apiKey
    @debug = debug

    @indexFile = normalize("#{pkg.name}.json")
    @indexContents = @getIndexContents()

  # Generate an MD5 hash from an arbitrary string
  generateHash: (string) ->
    return crypto.createHash('md5').update(string).digest('hex')

  # build URL from given url path
  buildURL: (path) ->
    return "#{@url}#{path}"

  # API handler
  api: (path, options = {}) ->
    defaultOptions =
      method: 'GET'
      url: @buildURL(path)
      auth:
        user: @apiKey
        password: ''
      headers:
        accept: 'application/json'
        'X-SWU-API-CLIENT': "grunt-#{pkg.version}"

    url = defaultOptions.url
    grunt.log.ok "API hit: #{url}"

    requestOptions = _.merge {}, defaultOptions, options
    requestPromise = requestp(requestOptions)

    return requestPromise.then(
      (res) ->
        grunt.log.ok "API success: #{defaultOptions.url}"
        return res
      (err) ->
        throw new Error("API request failed: status #{err.statusCode}, #{err.body}")
    )

  # Get all templates from the API
  getTemplates: () ->
    return @api('templates')

  # Get all templates from the API
  getTemplateVersions: (template) ->
    return @api("templates/#{template.id}/versions")

  # create template in the api, return response
  createTemplate: (jsonData) =>
    return @api('templates', {
      method: 'POST'
      json: jsonData
    })

  # update a template in the API and in the cache
  updateTemplateVersion: (indexedVersion, baseVersionData) ->
    grunt.log.writeln '   └── Version hash is different than cached, updating in API'
    path = "templates/#{indexedVersion.templateId}/versions/#{indexedVersion.id}"
    return @api(path, {
      method: "PUT"
      json: baseVersionData
    })

  # Get the contents of the index
  getIndexContents: () ->
    # Check if the local cache file exists or not
    if not grunt.file.exists @indexFile
      grunt.log.ok "Cache file doesn't exist"
      legacyPath = "#{getUserHome()}/#{pkg.name}.json"
      if grunt.file.exists legacyPath
        legacyContents = grunt.file.readJSON legacyPath
        grunt.log.ok "Found legacy manifest, creating project manifest"
        @writeIndexContents(legacyContents)
      else
        grunt.log.ok "Creating project manifest"
        grunt.file.write @indexFile, '[]' # write a blank file with an array for valid JSON
    else
      grunt.log.ok 'Cache file exists, continuing…'
    # Read the contents of the index file
    return grunt.file.readJSON @indexFile

  # Write the given contents to the index file
  writeIndexContents: (contents) ->
    grunt.log.ok 'Writing contents to index file…'
    grunt.file.write @indexFile, JSON.stringify(contents, null, 2)

  updateIndex: (apiVersion) ->
    indexNeedsUpdate = false

    # Generate the HTML hash from the api version to compare againts
    htmlHash = @generateHash apiVersion.html

    # Lookup the api version in the index
    indexedVersion = @indexContents.filter (v) -> return apiVersion.id is v.id

    # If the indexed version doesnt exist
    if indexedVersion.length is 0
      # set the indexed version as teh api version and add it to the index contents
      indexedVersion = apiVersion
      indexNeedsUpdate = true
    else
      indexedVersion = indexedVersion[0]

      # If the upstream hash is the same as the indexed hash for the version
      if htmlHash is indexedVersion.htmlHashå
        grunt.log.error "Version with id #{indexedVersion.id} HTML hash matches upstream, continuing…"
      else
        grunt.log.error "Template hash upstream doesn't match indexed template hash, updating…"
        indexNeedsUpdate = true

    if indexNeedsUpdate
      delete indexedVersion.html
      delete indexedVersion.text

      @indexContents.push indexedVersion
      @writeIndexContents(@indexContents)


module.exports = (grunt) ->
  grunt.registerMultiTask task.name, task.description, () ->
    done = @async()
    fileCount = @filesSrc.length
    opts = if not @data.options then @options() else @data.options

    # If there's no files, just run the callback
    done() if fileCount < 1

    # Check if the apiKey was provided
    if not opts.hasOwnProperty 'apiKey' or not opts.apiKey?
      # return an error message from the plugin
      msg = 'API key not found in the task options'
      grunt.log.error msg
      grunt.fail.warn msg

    if opts.hasOwnProperty 'debug' or opts.debug?
      grunt.log.ok 'Running in debug mode!'

    # Generate a new Sendwithus instance with the apiKey
    swu = new Sendwithus(opts.apiKey, opts.debug)

    # Iterate over files to upload
    @filesSrc.forEach (filepath) ->
      html = grunt.file.read filepath
      $ = cheerio.load html

      # Setup the data to send for the template
      baseVersionData =
        name: basename(filepath, '.html').replace /[_-]/g, ' '
        subject: $('title').text()
        html: html

      # Get the indexed version by its filepath
      indexedVersion = swu.indexContents.filter (v) -> return filepath is v.filepath

      # Check if we have a cached file and need to update it,
      # or create a new template in the api
      if indexedVersion.length isnt 0
        grunt.log.ok "Found template #{filepath} in cache, updating…"
        htmlHash = swu.generateHash baseVersionData.html
        if indexedVersion?[0]?.htmlHash isnt htmlHash
          swu.updateTemplateVersion(indexedVersion[0], baseVersionData)
            .then (apiVersion) ->
              grunt.log.ok "   └── Updated version #{apiVersion.id} in API"

              # Update the index entry
              position = _.findIndex swu.indexContents, (v) -> return v.id is apiVersion.id

              # Setup the data to be added to the version for the index file
              indexData =
                templateId: indexedVersion[0].templateId
                id: apiVersion.id
                name: apiVersion.name
                subject: apiVersion.subject
                htmlHash: htmlHash
                filepath: indexedVersion[0].filepath


              # Merge the base data and index data together
              versionIndexData = _.merge {}, indexData, baseVersionData

              delete versionIndexData.html
              delete versionIndexData.text

              swu.indexContents.splice position, 1, versionIndexData
              return swu.writeIndexContents(swu.indexContents)
            .catch (err) ->
              grunt.log.error err
            .done () ->
              # decrement the file count
              fileCount--
        else
          fileCount--
          return grunt.log.writeln '   └── Ignoring, version hash is the same'
      else
        grunt.log.ok "Didn't find template #{filepath} in cache, creating a new one…"

        # Create the template here
        swu.createTemplate(baseVersionData)
          .then (template) ->
            grunt.log.ok "Uploaded #{filepath} to sendwithus"

            # get the newly created template and its new version
            return swu.getTemplateVersions(template)
              .then (versions) ->
                version = JSON.parse(versions)[0]

                # Setup the data to be added to the version for the index file
                indexData =
                  templateId: template.id
                  id: version.id
                  name: version.name
                  subject: version.subject
                  htmlHash: swu.generateHash(html)
                  filepath: filepath

                # Merge the base data and index data together
                versionIndexData = _.merge {}, indexData, baseVersionData

                # Update the index with the filepath
                return swu.updateIndex versionIndexData
          .catch (err) ->
            grunt.log.error err
          .done () ->
            # decrement the file count
            fileCount--

      return done() if fileCount < 1

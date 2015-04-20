###
# grunt-sendwithus
# https://github.com/sendwithus/grunt-sendwithus
#
# Copyright (c) 2015 sendwithus
# Licensed under the MIT license.
###

# Get the config from the swu file
config = require(require('path').normalize(__dirname + '/../swu.json'))

module.exports = (grunt) ->

  # load all npm grunt tasks
  require('load-grunt-tasks')(grunt)

  # Project configuration.
  grunt.initConfig(
    clean:
      tests: ['tmp']
    sendwithus:
      default:
        options:
          apiKey: config.apiKey
        src: ['test/fixtures/*.html']
    nodeunit:
      tests: ['test/*_test.js']
  )

  # Actually load this plugin's task(s).
  grunt.loadTasks 'tasks'

  # Whenever the "test" task is run, first clean the "tmp" dir, then run this
  # plugin's task(s), then test the result.
  grunt.registerTask 'test', [
    'clean'
    'sendwithus'
    'nodeunit'
  ]

  # By default, lint and run all tests.
  # grunt.registerTask('default', ['jshint', 'test']);
  grunt.registerTask 'default', [
    'clean'
    'sendwithus'
  ]

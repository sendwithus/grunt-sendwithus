grunt = require 'grunt'

###
#  ======== A Handy Little Nodeunit Reference ========
#  https://github.com/caolan/nodeunit
#
#  Test methods:
#    test.expect(numAssertions)
#    test.done()
#  Test assertions:
#    test.ok(value, [message])
#    test.equal(actual, expected, [message])
#    test.notEqual(actual, expected, [message])
#    test.deepEqual(actual, expected, [message])
#    test.notDeepEqual(actual, expected, [message])
#    test.strictEqual(actual, expected, [message])
#    test.notStrictEqual(actual, expected, [message])
#    test.throws(block, [error], [message])
#    test.doesNotThrow(block, [error], [message])
#    test.ifError(value)
###

exports.sendwithus =
  setUp: (done) ->
    # setup here if necessary
    done()

  template_successful: (test) ->
    test.expect 1

    actual = grunt.file.read 'test/fixtures/template1.html'
    expected = grunt.file.read 'test/expected/template1.html'
    test.equal actual, expected, 'Template should match'

    test.done()

  template_successful_with_snippet: (test) ->
    test.expect 1

    actual = grunt.file.read 'test/fixtures/template2.html'
    expected = grunt.file.read 'test/expected/template2.html'
    test.equal actual, expected, 'Template should match including snippet content'

    test.done()

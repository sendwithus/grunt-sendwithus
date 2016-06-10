grunt-sendwithus
===

> Grunt plugin to deploy your local HTML email templates to [sendwithus](https://sendwithus.com)

## Getting Started

This plugin requires Grunt.

If you haven't used [Grunt](http://gruntjs.com/) before, be sure to check out the [Getting Started](http://gruntjs.com/getting-started) guide, as it explains how to create a [Gruntfile](http://gruntjs.com/sample-gruntfile) as well as install and use Grunt plugins. Once you're familiar with that process, you may install this plugin with this command:

```shell
npm install grunt-sendwithus --save-dev
```

Once the plugin has been installed, it may be enabled inside your Gruntfile with this line of JavaScript:

```js
grunt.loadNpmTasks('grunt-sendwithus');
```

This plugin was designed to work with Grunt 0.4.x. If you're still using grunt v0.3.x it's strongly recommended that [you upgrade](http://gruntjs.com/upgrading-from-0.3-to-0.4).

## The "sendwithus" task

### Overview

In your project's Gruntfile, add a section named `sendwithus` to the data object passed into `grunt.initConfig()`.

```js
grunt.initConfig({
  sendwithus: {
    default: {
      options: {}, // Task-specific options go here
      src: [] // Target-specific file list goes here
    }
  }
})
```

### Options

#### options.apiKey

Type: `String`
Default value: `null`

The API key from your sendwithus account. **Note**: it's recommended that you don't hard-code this api into the gruntfile, but rather require it from an external source like a config file or something.

### Usage Examples

#### Default Options

```js
grunt.initConfig({
  sendwithus: {
    default: {
      options: {
        apiKey: 'xxxxxxxxxx'  
      },
      src: ['src/testing.html', 'src/**/*.html']
    }
  }
})
```

## Contributing

In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Lint and test your code using [Grunt](http://gruntjs.com/).

## Testing

In order to run this plugin, you need to create a `swu.json` file in the root directory above where this project exists and populate it with

```json
{
  "apiKey": "YOUR SENDWITHUS PRODUCTION API KEY"
}
```

## Release History

0.0.3 - Fix an issue where templates might silently fail when uploading  
0.0.2 - Fix the README, and fix named tasks  
0.0.1 - Initial release  

## License
Copyright (c) 2015 sendwithus. Licensed under the MIT license.

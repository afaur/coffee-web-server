# Allow mixins in classes
# http://tinyurl.com/otbcg9y
mixins = require 'coffeescript-mixins'
mixins.bootstrap()

# Allow modules in classes
# http://tinyurl.com/lw2gag5
#{Module} = require 'coffeescript-module'

fs       = require 'fs'
http     = require 'http'
uri      = require 'url'
qs       = require 'querystring'
yaml     = require 'js-yaml'
jade     = require 'jade'
nstatic  = require 'node-static'

ROOT     = "#{__dirname}/.."
CONFIG   = "#{ROOT}/config"
VIEWPATH = "#{ROOT}/view"
CONFTYPE = process.env.CONFIG_TYPE || 'yml'

class Reader

  _file: ""

  _ext: ->
    CONFTYPE.toLowerCase()

  _type: ->
    CONFTYPE.toUpperCase()

  _data: ->
    fs.readFileSync @_file, 'utf8'

  _parse: ->
    JSON.parse @_data() if @_type() is 'JSON'
    yaml.safeLoad @_data() if @_type() is 'YML'

  keys: (object) ->
     (k for k of object)

  values: (object) ->
     (v for _,v of object)

  objects: (object) ->
    object

class Config

  @include Reader

  constructor: () ->
    @_file     = "#{CONFIG}/#{@_type()}/settings.#{@_ext()}"
    @_settings = @_parse()

  server: (option) ->
    if @_settings['server']?[option]?
      @_settings['server'][option]

class Router

  # Not fin/implemented yet. Need
  # logic moved out from being contained
  # inside the WebRequest to having
  # the Router read routes.yml and
  # be able to return the controller
  # and method found in the yml file

  @include Reader

  constructor: () ->
    @_file     = "#{CONFIG}/#{@_type()}/routes.#{@_ext()}"
    @_routes   = @_parse()

  route: (method, url) ->
    @objects(value) if value = @_routes[method]?[url]?

class FooController

  index: (getParams, postParams, staticParams, response) ->
    data = jade.renderFile "#{VIEWPATH}/Foo/index.jade", {}
    response.writeHead 200,
      'Content-Type':   'text/html'
      'Content-Length': data.length
    response.end data

class WebServer

  constructor: (port, handler) ->
    @_server = http.createServer(handler)
    @_server.listen(port)
    return @_server

class WebRequest

  constructor: (request,response,config) ->
    @_req     = request
    @_res     = response

    # Get the request method all uppercase
    @_method  = @method()

    # Save the true url of this request
    @_url_raw = @_req.url

    # Get the URL minus any GET parameters all uppercase
    @_url     = @url()

    # Initialize empty string for storing request body
    @_body    = ""

    @_req.on 'data', (chunk) =>
      # Retrieve data from request
      @_body += chunk.toString()

    @_req.on 'end', =>
      # Get all of our GET and POST params
      @params()

      # Lookup route and set action
      @route()

      # Match action to controller and run method
      @control()

      # Debugging
      console.log('----------------------------')
      console.log("RAW :       ", @_url_raw)
      console.log("GET :       ", @_GET)
      console.log("POST:       ", @_POST)
      console.log("CONTROLLER: ", @_action['controller'])
      console.log("METHOD:     ", @_action['method'])
      console.log('----------------------------')

  url: () ->
    if @_req.url.indexOf('?') > -1
      @_req.url.substr( 0, @_req.url.indexOf('?') ).toUpperCase()
    else
      @_req.url.toUpperCase()

  method: () ->
    @_req.method.toUpperCase()

  params: () ->
    @_GET  = uri.parse( @_url_raw, true ).query
    @_POST = qs.parse(@_body)

  # Move this out into Router class and use a routes.yml for mapping
  route: () ->
    # If path has extension that isn't json,xml,yml
    if @_url.match(/^([^.]+\.(?!json|xml|yml)[^\\/.]+)$/gmi)?[0]?
      @_action = {"controller": "public", "method": ""}
    else if @routes[@_method]?[@_url]?
      @_action = @routes[@_method][@_url]
    else
      @_action = {"controller": "404", "method": "index"}

  # Move this out into Router class and use a routes.yml for mapping
  routes:
    'GET':
      '/FOO': {"controller": 'FooController', "method": 'index'}
      '/BAR': {"controller": 'FooController', "method": 'bar'}
    'POST':
      '/FOO': {"controller": 'FooController', "method": 'index'}

  # Needs error handling and clean up
  control: () ->
    if @_action['controller'] is 'public'
      # Provide handling for static files in public directory
      file = new (nstatic.Server) "#{ROOT}/public",
        cache: 600,
        headers:
          'X-Powered-By': 'node-static'
      file.serve @_req, @_res, (err, result) -> console.log ''
    else
      # Hack for class lookup table (need refactor)
      classes      = { FooController: FooController }
      # Params that will be read from a yml/json file
      # That will be specific to a controller and method
      staticParams = {}
      # Lookup controller we need based on action
      controller = new classes[@_action['controller']]
      # Call the method (index) on the controller (FooController)
      controller[@_action['method']](@_GET, @_POST, staticParams, @_res)

class WebRequestManager

  _count: 0
  _requests: {}

  add: (web_request) ->
    @_requests[@_count] = web_request
    @_count = @_count + 1

  list: =>
    for i,request of @_requests
      console.log(i, ": ", request)


config              = new Config()
web_request_manager = new WebRequestManager
requests_count      = 0

# Handler to pass into our webserver
web_request_handler = (request, response) =>
  web_request_manager.add( new WebRequest(request, response) )

web_server          = new WebServer( config.server('port'), web_request_handler )

# Tracks all web requests
monitor_requests = () =>
  if web_request_manager._count > requests_count
    # Update monitored requests
    requests_count = web_request_manager._count
    console.log('----------------------------')
    console.log('New Web Request.')
    console.log('Total Requests: ', requests_count)
    console.log('----------------------------')

setInterval(monitor_requests, 250)


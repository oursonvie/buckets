express = require 'express'
hbs = require 'hbs'
cloudinary = require 'cloudinary'
url = require 'url'
glob = require 'glob'
fs = require 'fs'
favicon = require 'serve-favicon'
_ = require 'underscore'
marked = require 'marked'

config = require '../config'
plugins = require '../lib/plugins'
passport = require '../lib/auth'
User = require '../models/user'

module.exports = app = express()

{adminSegment} = config

hbs.registerHelper 'json', (context) ->
  new hbs.handlebars.SafeString JSON.stringify(context)

app.set 'views', "#{__dirname}/../views"

faviconFile = "#{__dirname}/../../public/favicon.ico"
app.use favicon faviconFile if fs.existsSync faviconFile

app.use express.static "#{__dirname}/../../public/", maxAge: 86400000 * 7 # One week

app.set 'plugins', plugins.load()

# Special case for install
app.post '/login', passport.authenticate('local', failureRedirect: "/#{adminSegment}/login"), (req, res, next) ->
  res.redirect if req.user and req.body.next
    req.body.next
  else
    "/#{adminSegment}/"

app.post '/checkLogin', (req, res) ->
  passport.authenticate('local', (err, user, authErr) ->
    if authErr
      res.status(401).send errors: [authErr]
    else if user
      res.status(200).end()
    else
      res.status(500).send err
  )(req, res)

app.get '/logout', (req, res) ->
  req.logout()
  res.redirect "/#{adminSegment}/"

app.get "/help-html/*", (req, res, next) ->
  glob "../../docs/user-docs/#{req.params[0]}", cwd: __dirname, (e, files) ->
    return res.status(404).end() unless files.length
    fs.readFile "#{__dirname}/#{files[0]}", encoding: 'utf-8', (e, content) ->
      return res.status(400).end() unless content and html = marked(content)
      res.status(200).send html

app.all '*', (req, res) ->
  User.count({}).exec (err, userCount) ->
    res.send 500 if err

    localPlugins = _.filter app.get('plugins'), (plugin) ->
      plugin.client or plugin.clientStyle

    if config.cloudinary
      parsed = url.parse(config.cloudinary)
      [api_key,api_secret] = parsed.auth.split(':')
      cloud_name = parsed.host

      cloudinaryData =
        timestamp: Date.now() # Lasts 1 hour
        use_filename: yes
        callback: "http://#{req.get('host')}/vendor/cloudinary_js/html/cloudinary_cors.html"
        image_metadata: yes
        exif: yes
        colors: yes
        faces: yes
        eager: 'w_300,h_600,c_fit,q_30'
      signature = cloudinary.utils.sign_request cloudinaryData,
        cloud_name: cloud_name
        api_key: api_key
        api_secret: api_secret
      .signature
      cloudinaryData.signature = signature
      cloudinaryData.api_key = api_key
      cloudinaryData.cloud_name = cloud_name
    else
      cloudinaryData = {}

    res.render 'admin',
      user: req.user
      env: config.env
      plugins: localPlugins
      adminSegment: adminSegment
      apiSegment: config.apiSegment
      needsInstall: userCount is 0
      cloudinary: cloudinaryData

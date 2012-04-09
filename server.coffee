#http = require 'http'

try
  redis = require 'redis'
express = require 'express'
app = express.createServer()

app.use express.static("#{__dirname}/")
port = 8123


# How frequently (in ms) should we advance the world
dt = 33
snapshotDelay = 5

run = (error, value) ->
  value = JSON.parse value if value
  
  galaxy = new require('./galaxy') value

  WebSocketServer = require('ws').Server
  wss = new WebSocketServer {server: app}

  frame = 0
  setInterval ->
      frame++
      galaxy.step dt

      if (frame % snapshotDelay) is 0
        # Update clients
        for c in wss.clients
          snapshot = galaxy.snapshot c.data.knownBodies, c.data.viewport
          c.send JSON.stringify {snapshot}

        #db?.set 'boilerplate', JSON.stringify(simulator.grid)
    , dt

  wss.on 'connection', (c) ->
    c.data =
      viewport: null
      knownBodies: {}

    c.on 'message', (msg) ->
      try
        msg = JSON.parse msg

        if msg.viewport
          c.data.viewport = msg.viewport
        else
          # Unknown message.
          console.log msg

      catch e
        console.log 'invalid JSON', e, msg


  app.listen port
  console.log "Listening on port #{port}"

if redis?
  db = redis.createClient()
  db.on 'ready', -> db.get 'space', run
else
  run null, '{}'

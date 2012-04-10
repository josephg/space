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
  
wire = require './wire'

run = (error, initialSnapshot) ->
  initialSnapshot = JSON.parse initialSnapshot if initialSnapshot
  
  galaxy = new require('./galaxy') initialSnapshot, {snapshotDelay, dt}

  WebSocketServer = require('ws').Server
  wss = new WebSocketServer {server: app}

  frame = 0

  bytesSent = 0
  bytesReceived = 0

  setInterval ->
      frame++
      galaxy.step dt

      if (frame % snapshotDelay) is 0
        # Update clients
        for c in wss.clients
          snapshot = galaxy.snapshot frame, c.data
          msg = wire.snapshot.pack snapshot
          #console.log snapshot
          #msg = JSON.stringify {snapshot}
          bytesSent += msg.byteLength
          c.send new DataView(msg), binary:true

        #db?.set 'boilerplate', JSON.stringify(simulator.grid)
    , dt

  wss.on 'connection', (c) ->
    c.data =
      viewport: null
      # Maps object id -> false if the client can't see the object now, true if it can.
      # Objects aren't in the map if the client has never seen them.
      seenObjects: {}
      # This is a list of ids of the elements which the client saw last frame.
      # It is a copy of the keys in seenObjects which map to true.
      visibleLastFrame: []

    c.on 'message', (msg) ->
      try
        bytesReceived += msg.length
        msg = JSON.parse msg

        if msg.viewport
          c.data.viewport = msg.viewport
        else
          # Unknown message.
          console.log msg

      catch e
        console.log 'invalid JSON', e, msg

  setInterval ->
      console.log "TX: #{bytesSent}  RX: #{bytesReceived}"
      bytesSent = bytesReceived = 0
    , 1000

  app.listen port
  console.log "Listening on port #{port}"

if redis?
  db = redis.createClient()
  db.on 'ready', -> db.get 'space', run
else
  run null, '{}'

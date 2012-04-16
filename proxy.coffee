express = require 'express'
net = require 'net'

app = express.createServer()

app.use express.static("#{__dirname}/")
port = 8123

initialSnapshot = JSON.parse initialSnapshot if initialSnapshot

WebSocketServer = require('ws').Server
wss = new WebSocketServer {server: app}

wss.on 'connection', (client) ->
  # Open a separate TCP connection for every WS connection
  console.log 'incoming connection from client'

  closed = false

  socket = net.connect 8765, 'sephsmac.local', ->
    # connected to server.
    console.log 'connected to server'

  socket.on 'end', ->
    closed = true
    console.log 'Server socket closed'
    client.close()
  client.on 'close', ->
    closed = true
    console.log 'Client closed'
    socket.end()

  socket.on 'error', (e) ->
    console.log e
    closed = true
    client.close()

  lenBuf = new Buffer 4

  client.on 'message', (msg, {binary}) ->
    if binary
      # I need to prefix the packet with the length.
      lenBuf.writeUInt32LE(msg.length - 4, 0)
      socket.write lenBuf
      socket.write msg
    else
      # Text packets get wrapped in a buffer and sent as user messages
      header = new Buffer 5
      text = new Buffer msg
      header.writeUInt32LE text.length + 1, 0
      header.writeUInt8 200, 4
      socket.write header
      socket.write text

  buffers = []
  # Offset into the first buffer
  offset = 0
  # Length of the packet we're currently trying to read
  packetLength = -1

  readBytes = (dest, num = dest.length) ->
    # Read num bytes from the pending buffers into dest (another buffer)
    # There has to be enough bytes to read.
    p = 0
    while true
      read = buffers[0].copy dest, p, offset
      p += read
      offset += read
      if offset is buffers[0].length
        offset = 0
        buffers.shift()

      return dest if p == num

  socket.on 'data', (data) ->
    return if closed
    buffers.push data

    bytes = -offset
    bytes += b.length for b in buffers

    while true
      if packetLength is -1
        if bytes >= 4
          readBytes lenBuf
          packetLength = lenBuf.readUInt32LE(0)
          bytes -= 4
        else
          break
      else
        if bytes >= packetLength
          packet = new Buffer packetLength
          readBytes packet
          bytes -= packetLength
          packetLength = -1

          client.send packet, binary:true
          #console.log "proxied #{packet.length} bytes"
        else
          break

app.listen port
console.log "Listening on port #{port}"


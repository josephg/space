canvas = document.getElementsByTagName('canvas')[0]
canvas.width = 1024
canvas.height = 768

ctx = canvas.getContext '2d'

ws = new WebSocket "ws://#{window.location.host}"
ws.binaryType = 'arraybuffer'

space = new cp.Space

# Map from id -> body.
bodies = {}

frame = null

# MUST match the server's snapshotDelay value
snapshotDelay = 5 # Frames between subsequent snapshots.

delay = 5 # Our delay in frames behind realtime
pendingSnapshots = []

dt = 33 # dt per tick (ms). Must match server.

viewportX = viewportY = 0

requestAnimationFrame = window.requestAnimationFrame or window.mozRequestAnimationFrame or
                        window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

packetHeaders =
  100:
    name: 'snapshot'
    read: (r) ->
      snapshot = {}

      return snapshot unless r.bytesLeft()
      for [0...r.uint16()]
        # Read an update packet.
        id = r.uint32()
        snapshot[id] = s = {}
        s[k] = r.float32() for k in ['x', 'y', 'a', 'vx', 'vy', 'w', 'ax', 'ay', 'aw']

      return snapshot unless r.bytesLeft()
      for [0...r.uint16()]
        # Create packets
        id = r.uint32()
        throw new Error "Got a create but no update for #{id}" unless snapshot[id]
        s = snapshot[id]
        s.m = r.float32()
        s.i = r.float32()

        numShapes = r.uint16()
        s.shapes = new Array numShapes
        for i in [0...numShapes]
          numVerts = r.uint16()
          verts = s.shapes[i] = new Array numVerts * 2
          for v in [0...numVerts * 2]
            verts[v] = r.float32()

      return snapshot unless r.bytesLeft()
      for [0...r.uint16()]
        # Remove objects.
        id = r.uint32()
        snapshot[id] = null

      throw new Error 'Misaligned bytes' unless r.bytesLeft() is 0
      snapshot
  101: # lua messages.
    name: 'lua message'
    read: (r) ->
      # bleh ignore for now.
  
  102:
    name: 'set avatar'
    read: (r) -> r.uint32()


readPacket = (data) ->
  r = read data
  type = r.uint8()
  unless packetHeaders[type]
    console.error 'Not a valid message type!'
    return

  type: packetHeaders[type].name
  data: packetHeaders[type].read r



prevSnapshot = null
applySnapshot = (snapshot) ->
  if prevSnapshot isnt null and snapshot.frame isnt prevSnapshot.frame + snapshotDelay
    throw new Error "Snapshots not applied in order: #{prevSnapshot.frame} -> #{snapshot.frame}"

  # Look for new objects in the snapshot and add them to the bodies set
  for id, s of snapshot.data when s isnt null and bodies[id] is undefined
    # Make a new body using the data and add it to the space.
    throw new Error "missing data for #{id}" unless s.shapes
    #console.log "adding #{id}"
    b = bodies[id] = new cp.Body s.m, s.i
    b.geometry = []
    for verts in s.shapes
      b.geometry.push new cp.PolyShape b, verts, cp.v(0,0)

  for id, b of bodies # Bodies that are no longer in the region sent by the server
    s = snapshot.data[id]

    if s is null
      # Remove the object from the space.
      #console.log "removing #{id}"
      space.removeBody b
      space.removeShape shape for shape in b.geometry

    # Skip objects that aren't on the screen and aren't being re-added.
    continue if !b.space and !s

    if s is undefined
      # The body is just drifting. Update it based on its last snapshot position.
      throw new Error 'Missing data' unless prevSnapshot?.data[id]
      p = prevSnapshot.data[id]
      
      mult = dt * snapshotDelay / 1000

      s = snapshot.data[id] =
        a: p.a + p.w * mult
        x: p.x + p.vx * mult
        y: p.y + p.vy * mult
        w: p.w
        vx: p.vx
        vy: p.vy
        ax: p.ax
        ay: p.ay
        aw: p.aw

    b.setAngle s.a # Angle
    b.setPos cp.v(s.x, s.y)
    b.w = s.w # Angular momentum
    b.setVelocity cp.v(s.vx, s.vy)

    b.ax = s.ax
    b.ay = s.ay
    b.aw = s.aw

    if !b.space
      # re-add the body to the space.
      #console.log "inserting #{id}"
      space.addBody b
      space.addShape s for s in b.geometry
    else
      space.reindexShape s for s in b.shapeList

  prevSnapshot = snapshot
  
  console.log "time warping from #{frame} to #{snapshot.frame}" if frame isnt snapshot.frame
  frame = snapshot.frame


snapshotted = false
update = ->
  #console.log 'update'
  return if frame is null # No snapshots yet

  frame++

  return if frame < 0 # Delaying for extra smoothness

  snapshot = null
  skip = false

  while (pendingSnapshots.length > 0 and pendingSnapshots[0].frame <= frame) or
      pendingSnapshots.length >= 2
    skip = true
    applySnapshot pendingSnapshots.shift()

  snapshotted = skip

  space.eachBody (body) ->
    if body.ax || body.ay || body.aw
      a = cp.v.rotate cp.v(body.ax, body.ay), body.rot
      body.vx += dt/1000 * a.x
      body.vy += dt/1000 * a.y
      #body.setVelocity cp.v(body.vx + dt/1000, body.vy + dt/1000)
      body.w += dt/1000 * body.aw

  space.step dt/1000 unless skip

dirty = false
draw = ->
  return unless dirty # Only draw once despite how many updates have happened
  #console.log 'draw'
  ctx.fillStyle = 'black'
  ctx.fillRect 0, 0, 1024, 768

  if frame is null or frame < 0
    ctx.font = '60px Helvetica'
    ctx.fillText 'Buffering gameplay', 0, 0, 0

  #ctx.fillStyle = 'green'
  #ctx.fillRect 100*pendingSnapshots.length, 0, 100, 100
  
  #ctx.fillStyle = 'red'
  #ctx.fillRect 25, 25, 50, 50 if snapshotted

  #ctx.strokeStyle = 'blue'
  #ctx.strokeRect 100, 100, 600, 400

  ctx.save()
  ctx.translate 0, 768
  ctx.scale 1, -1

  ctx.translate -viewportX, -viewportY

  space.eachShape (shape) ->
    ctx.strokeStyle = 'grey'
    #ctx.fillStyle = 'rgba(0, 0, 0, 0.2)'
    #console.log "draw #{shape.body.p.x}"
    col = 255 - Math.floor shape.body.m / 100 * 255
    ctx.fillStyle = "rgb(#{col}, #{col}, #{col})"

    shape.draw()

  ctx.restore()

  dirty = false

lastFrame = 0

runFrame = ->
  nominalTime = lastFrame + dt
  actualTime = Date.now()
  setTimeout runFrame, Math.max(0, nominalTime - actualTime + dt)
  lastFrame = nominalTime

  update()
  if !dirty
    dirty = true
    requestAnimationFrame draw

nextSnapshotFrame = 0
ws.onmessage = (msg) ->
  if typeof msg.data is 'string'
    msg = JSON.parse msg.data
    console.log msg.data
  else
    # Binary.
    msg = readPacket msg.data
    return unless msg

    switch msg.type
      when 'snapshot'
        snapshot =
          data: msg.data
          frame: nextSnapshotFrame
        #console.log "frame #{frame} got snapshot #{snapshot.frame}"
        #console.log snapshot.data
        nextSnapshotFrame += snapshotDelay
        pendingSnapshots.push snapshot

        if frame is null
          # This is the first snapshot.
          frame = -delay

      when 'lua message'
        console.log 'ignoring lua message'

      when 'set avatar'
        console.log 'avatar', msg.data

send = (msg) -> ws.send JSON.stringify msg

queuedMessage = false
sendViewportToServer = ->
  # Send a rate limited viewport message to the server.
  return if queuedMessage
  queuedMessage = true
  setTimeout ->
      send viewport:{x:viewportX, y:viewportY, w:canvas.width, h:canvas.height}
      queuedMessage = false
    , 100

ws.onopen = ->
  username = prompt "LOGIN PLOX"
  ws.send username
  sendViewportToServer()
  lastFrame = Date.now()
  runFrame()

document.onmousewheel = (e) ->
  #console.log "mouse scroll", e
  viewportX -= e.wheelDeltaX
  viewportY += e.wheelDeltaY
  sendViewportToServer()
  e.preventDefault()

downKeys = {}

keyEvent = (e, down) ->
  key = String.fromCharCode e.keyCode
  #console.log e.keyCode, key

  m = {'W':'up', 'A':'left', 'S':'down', 'D':'right', ' ':'fire'}
  if m[key]
    e.stopPropagation()
    e.preventDefault()

    # Ignore (debounce!)
    return if down and downKeys[key]

    downKeys[key] = down

    ws.send "#{m[key]} #{if down then 'on' else 'off'}"
    #send {key, down}


document.onkeydown = (e) -> keyEvent e, true
document.onkeyup = (e) -> keyEvent e, false

cp.PolyShape::draw = ->
  ctx.beginPath()

  verts = @tVerts
  len = verts.length

  ctx.moveTo verts[len - 2], verts[len - 1]

  for i in [0...len] by 2
    ctx.lineTo verts[i], verts[i+1]

  ctx.fill()
  ctx.stroke()



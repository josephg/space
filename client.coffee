canvas = document.getElementsByTagName('canvas')[0]
canvas.width = 1024
canvas.height = 768

ctx = canvas.getContext '2d'

ws = new WebSocket "ws://#{window.location.host}"
ws.binaryType = 'arraybuffer'

ws.onerror = (e) -> console.log e

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

shipTypes = "ship bullet".split(' ')

lastFrame = 0

radar = []

models = [
  {verts:[-25, -25, -20, 0, 0, 20, 20, 0, 25, -25]}, # Ship
  {verts:[-3, -5, 0, 5, 3, -5]}, # bullet
]
m.offset = cp.v.neg cp.centroidForPoly m.verts for m in models

packetHeaders =
  100:
    name: 'snapshot'
    read: (r) ->
      data = {}

      flags = r.uint8()

      if flags & 1 # Update frames
        for [0...r.uint16()]
          # Read an update packet.
          id = r.uint32()
          data[id] = s = {}
          s[k] = r.float32() for k in ['x', 'y', 'a', 'vx', 'vy', 'w', 'ax', 'ay', 'aw']

      if flags & 2 # Create frames
        for [0...r.uint16()]
          # Create packets
          id = r.uint32()
          throw new Error "Got a create but no update for #{id}" unless data[id]
          s = data[id]
          s.type = shipTypes[r.uint8()]
          s.model = models[r.uint8()]
          s.m = r.float32()
          s.i = r.float32()
          s.color = "rgb(#{r.uint8()}, #{r.uint8()}, #{r.uint8()})"

      if flags & 4 # Remove frames
        for [0...r.uint16()]
          # Remove objects.
          id = r.uint32()
          data[id] = null

      if flags & 8 # Radar
        rad = []
        for [0...r.uint16()]
          h =
            x: r.float32()
            y: r.float32()
            heat: r.float32()
          rad.push h

      throw new Error 'Misaligned bytes' unless r.bytesLeft() is 0
      {data, radar:rad}

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

  radar = snapshot.radar if snapshot.radar

  # Look for new objects in the snapshot and add them to the bodies set
  for id, s of snapshot.data when s isnt null and bodies[id] is undefined
    # Make a new body using the data and add it to the space.
    throw new Error "missing data for #{id}" unless s.model?
    #console.log "adding #{id}"
    b = bodies[id] = new cp.Body s.m, s.i
    b.model = s.model
    b.type = s.type
    b.geometry = [new cp.PolyShape b, b.model.verts, b.model.offset]
    b.color = s.color

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

    b.prevSnapshot = s
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
  
  if frame isnt snapshot.frame
    console.log "time warping from #{frame} to #{snapshot.frame}"
    lastFrame = Date.now()
    
  frame = snapshot.frame

lerp = (a, b, t) -> a*(1 - t) + b*t

update = ->
  #console.log 'update'
  return if frame is null # No snapshots yet

  snapshot = null
  skip = false

  # If we get super lag or disconnected, pause the simulation.
  return if pendingSnapshots.length == 0

  frame++

  while (pendingSnapshots.length >= 2 and pendingSnapshots[0].frame <= frame) or
      pendingSnapshots.length >= 2
    skip = true
    applySnapshot pendingSnapshots.shift()

  if pendingSnapshots.length == 1 and pendingSnapshots[0].frame == frame
    # We've caught up to the server. Wait for the next snapshot frame.
    frame--
    skip = true

  unless skip
    nextSnapshot = pendingSnapshots[0]
    space.eachBody (body) ->
      if body.ax || body.ay || body.aw
        a = cp.v.rotate cp.v(body.ax, body.ay), body.rot
        body.vx += dt/1000 * a.x
        body.vy += dt/1000 * a.y
        #body.setVelocity cp.v(body.vx + dt/1000, body.vy + dt/1000)
        body.w += dt/1000 * body.aw

    space.step dt/1000

    # We'll also just lerp toward the angle and velocity of the subsequent snapshot frame. This
    # makes animation smoother.
    t = 1 + (frame - nextSnapshot.frame) / snapshotDelay
    for id, s of nextSnapshot.data when s and bodies[id]?.space
      b = bodies[id]
      p = bodies[id].prevSnapshot
      # Track towards our next acceleration. I would lerp, but I'm lazy.
      #console.log p.a, s.a, t, lerp p.a, s.a, t
      b.setAngle lerp p.a, s.a, t
      #body.ay = mix * body.ay + (1-mix) * nextSnapshot.data[body.id].ay
      #body.aw = mix * body.aw + (1-mix) * nextSnapshot.data[body.id].aw


  if (body = bodies[avatar])
    viewportX = body.p.x - canvas.width/2
    viewportY = body.p.y - canvas.height/2


starfield = ({
    x: Math.random()*canvas.width
    y: Math.random()*canvas.height
    d: Math.random()*0.3+0.01
    r: Math.random()*2
    t: Math.random()
} for [1..200])

dirty = false
draw = ->
  return unless dirty # Only draw once despite how many updates have happened
  #console.log 'draw'
  ctx.fillStyle = 'black'
  ctx.fillRect 0, 0, canvas.width, canvas.height

  if frame is null or frame < 0
    ctx.font = '60px Helvetica'
    ctx.fillText 'Buffering gameplay', 0, 0, 0

  #ctx.fillStyle = 'green'
  #ctx.fillRect 100*pendingSnapshots.length, 0, 100, 100
  
  #ctx.strokeStyle = 'blue'
  #ctx.strokeRect 100, 100, 600, 400


  for {x, y, d, t} in starfield
    r = d * 6
    #grd = ctx.createRadialGradient x, y, 0, x, y, r
    #grd.addColorStop 0, "hsla(#{Math.max(45,t*90)}, 50%, #{t*100}%, 1)"
    #grd.addColorStop 1, "hsla(#{Math.max(45,t*90)}, 50%, #{t*50}%, 0)"
    #ctx.fillStyle = grd
    ctx.fillStyle = "hsl(#{t*45}, 100%, #{t*50}%)"
    ctx.beginPath()
    x = (x - viewportX * d) % canvas.width
    x += canvas.width if x < 0
    y = (y + viewportY * d) % canvas.height
    y += canvas.height if y < 0
    ctx.arc x, y, r, 0, Math.PI*2
    ctx.fill()


  ctx.save()
  ctx.translate 0, canvas.height
  ctx.scale 1, -1

  #ctx.translate canvas.width/2, canvas.height/2
  #if bodies[avatar]
  #  ctx.rotate -bodies[avatar].a
  #ctx.translate -canvas.width/2, -canvas.height/2

  ctx.translate -viewportX, -viewportY

  cx = viewportX + canvas.width / 2
  cy = viewportY + canvas.height / 2
  radius = Math.min(canvas.width, canvas.height) / 2

  for {x, y, heat} in radar when x < viewportX or x > viewportX + canvas.width or
      y < viewportY or y > viewportY + canvas.height

    ctx.fillStyle = "rgba(255, 100, 100, 0.5)"
  
    vect = cp.v(x - cx, y - cy)
    dist = cp.v.len vect
    dot = cp.v.mult(cp.v.normalize(vect), radius)

    #console.log dot.x, dist, radius
    
    r = 1/Math.log(Math.E + (dist - radius) / 100) * 50
    ctx.beginPath()
    ctx.arc dot.x + cx, dot.y + cy, r, 0, Math.PI*2
    #ctx.arc cx, cy, 100, 0, Math.PI*2
    ctx.fill()


  space.eachShape (shape) ->
    ctx.strokeStyle = 'grey'
    #ctx.fillStyle = 'rgba(0, 0, 0, 0.2)'
    #console.log "draw #{shape.body.p.x}"
    col = 255 - Math.floor shape.body.m / 100 * 255
    ctx.fillStyle = shape.body.color

    shape.draw()

  ctx.restore()

  dirty = false

avatar = null

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
          data: msg.data.data
          radar: msg.data.radar
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
        avatar = msg.data
        console.log 'avatar', msg.data


send = (msg) -> ws.send JSON.stringify msg

rateLimit = (fn) ->
  queuedMessage = false
  (arg) ->
    return if queuedMessage
    queuedMessage = true
    setTimeout ->
        queuedMessage = false
        fn(arg)
      , 200

username = if window.location.hash
  window.location.hash.substr(1)
else
  prompt "LOGIN PLOX"
  window.location.hash = username

ws.onopen = ->
  ws.send username
  #sendViewportToServer()
  lastFrame = Date.now()
  runFrame()

document.onmousewheel = (e) ->
  #console.log "mouse scroll", e
  viewportX -= e.wheelDeltaX
  viewportY += e.wheelDeltaY
  e.preventDefault()

if username is 'seph'
  sendTarget = rateLimit (e) ->
    x = e.offsetX - canvas.width / 2
    y = canvas.height / 2 - e.offsetY
    targetAngle = Math.atan2 -x, y
    # Round it a bit to make the message smaller
    targetAngle = Math.floor(targetAngle * 100) / 100
    ws.send "a #{targetAngle}"
    #ws.send "#{e.offsetX} #{canvas.height - e.offsetY}"

  canvas.onmousemove = (e) -> sendTarget e
    

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


